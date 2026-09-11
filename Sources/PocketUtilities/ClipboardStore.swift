import AppKit
import CryptoKit
import Security
import UtilityCore

struct ClipboardPayload: Codable {
    var entries: [[String: Data]]
    var byteCount: Int { entries.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }
    func encoded() throws -> Data { try PropertyListEncoder().encode(self) }
}

/// All disk payloads AND the searchable index are authenticated encrypted blobs.
/// No clipboard contents or previews are written to UserDefaults or logs.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var error: String?
    private var memory: [UUID: ClipboardPayload] = [:]
    private var key: SymmetricKey?
    private(set) var persistent = false
    private let directory: URL
    private let settings: SettingsStore
    private let keyProvider: (() throws -> SymmetricKey)?
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    init(settings: SettingsStore, directory: URL? = nil, keyProvider: (() throws -> SymmetricKey)? = nil) {
        self.settings = settings
        self.keyProvider = keyProvider
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PocketUtilities/Clipboard", isDirectory: true)
    }
    private func keychainKey() throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "local.PocketUtilities.clipboard",
                                  kSecAttrAccount as String: "history-encryption-v1"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw UtilityError("Clipboard encryption key is unavailable. Recording is paused; unlock the Keychain and retry persistence.") }
        // Do not replace a missing key if encrypted history already exists.
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.enc").path) else {
            throw UtilityError("The encryption key for existing history is missing. Clear history before creating a new key.")
        }
        let newKey = SymmetricKey(size: .bits256)
        var insert = query
        insert[kSecValueData as String] = newKey.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw UtilityError("Could not save the clipboard key to the local Keychain.") }
        return newKey
    }
    private func encrypt(_ data: Data) throws -> Data {
        guard let key, let combined = try AES.GCM.seal(data, using: key).combined else { throw UtilityError("Clipboard encryption is unavailable.") }
        return combined
    }
    private func decrypt(_ data: Data) throws -> Data {
        guard let key else { throw UtilityError("Clipboard encryption is unavailable.") }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".enc") }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func configure() {
        if settings.value.clipboardPersistent != persistent {
            do {
                if settings.value.clipboardPersistent {
                    key = try keyProvider?() ?? keychainKey()
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let index = directory.appendingPathComponent("index.enc")
                    if FileManager.default.fileExists(atPath: index.path) {
                        let saved = try decoder.decode([ClipboardItem].self, from: decrypt(Data(contentsOf: index)))
                        items = saved.filter { FileManager.default.fileExists(atPath: url($0.id).path) } + items
                    }
                    for (id, payload) in memory { try write(encrypt(payload.encoded()), to: url(id)) }
                    persistent = true
                    try saveIndex()
                    memory.removeAll()
                } else {
                    // Switching to memory-only intentionally clears history, including all disk data.
                    try eraseDisk()
                    items.removeAll(); memory.removeAll(); key = nil; persistent = false
                }
                error = nil
            } catch { self.error = "Clipboard storage could not be configured. History recording is paused. Check Keychain access or clear history and retry."; return }
        }
        prune()
    }
    private func saveIndex() throws {
        if persistent { try write(encrypt(encoder.encode(items)), to: directory.appendingPathComponent("index.enc")) }
    }
    private func eraseDisk() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func payload(for item: ClipboardItem) throws -> ClipboardPayload {
        if persistent { return try decoder.decode(ClipboardPayload.self, from: decrypt(Data(contentsOf: url(item.id)))) }
        guard let payload = memory[item.id] else { throw UtilityError("This clipboard entry is unavailable.") }
        return payload
    }
    func insert(_ payload: ClipboardPayload, preview: String, kind: String) {
        guard error == nil else { return }
        do {
            let canonical = JSONEncoder()
            canonical.outputFormatting = [.sortedKeys]
            let encoded = try canonical.encode(payload)
            let digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
            if let index = items.firstIndex(where: { $0.digest == digest }) {
                items[index].date = Date()
            } else {
                let item = ClipboardItem(preview: String(preview.prefix(300)), kind: kind, digest: digest, byteCount: payload.byteCount)
                if persistent { try write(encrypt(payload.encoded()), to: url(item.id)) } else { memory[item.id] = payload }
                items.insert(item, at: 0)
            }
            prune()
        } catch { self.error = "Clipboard history could not be saved. Recording is paused." }
    }
    func prune() {
        guard error == nil else { return }
        let keep = HistoryPolicy.retained(items, limit: settings.value.clipboardLimit, maxAgeDays: settings.value.clipboardAgeDays, maxBytes: settings.value.clipboardMaxMB * 1_048_576, totalByteBudget: (persistent ? 256 : 32) * 1_048_576)
        let ids = Set(keep.map(\.id))
        do {
            for item in items where !ids.contains(item.id) {
                if persistent, FileManager.default.fileExists(atPath: url(item.id).path) { try FileManager.default.removeItem(at: url(item.id)) }
                memory[item.id] = nil
            }
            items = keep
            try saveIndex()
            if persistent {
                // Remove payloads left by an interrupted write before index commit.
                let allowed = Set(items.map { $0.id.uuidString + ".enc" }).union(["index.enc"])
                for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !allowed.contains(file.lastPathComponent) {
                    try FileManager.default.removeItem(at: file)
                }
            }
        } catch { self.error = "Clipboard pruning failed. Recording is paused until storage is available." }
    }
    func delete(_ id: UUID) {
        do {
            if persistent { try FileManager.default.removeItem(at: url(id)) }
            memory[id] = nil; items.removeAll { $0.id == id }
            try saveIndex()
        } catch { self.error = "The clipboard entry could not be deleted." }
    }
    func pin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle(); prune()
    }
    func clear() {
        do {
            try eraseDisk()
            items.removeAll(); memory.removeAll(); error = nil
            if persistent {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try saveIndex()
            }
        } catch { self.error = "Clipboard files could not be removed. Check local storage permissions." }
    }
    func shutdown() { if settings.value.clearOnQuit { clear() }; memory.removeAll() }
}
