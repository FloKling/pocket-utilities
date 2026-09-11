import Testing
import CryptoKit
import AppKit
@testable import PocketUtilities

final class ClipboardStoreTests {
    var directory: URL!
    var settings: SettingsStore!
    let key = SymmetricKey(size: .bits256)
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        settings = SettingsStore(defaults: nil)
    }
    deinit {
        if FileManager.default.fileExists(atPath: directory.path) { try? FileManager.default.removeItem(at: directory) }
    }
    func store() -> ClipboardStore { ClipboardStore(settings: settings, directory: directory, keyProvider: { self.key }) }
    var payload: ClipboardPayload { ClipboardPayload(entries: [[NSPasteboard.PasteboardType.string.rawValue: Data("private-test-content".utf8), NSPasteboard.PasteboardType.rtf.rawValue: Data("{\\rtf1 rich text}".utf8)]]) }
    @Test func testMemoryOnlyNeverCreatesFilesAndDeduplicates() throws {
        let store = store(); store.configure()
        store.insert(payload, preview: "private-test-content", kind: "Text")
        let id = try requireValue(store.items.first?.id)
        let reordered = ClipboardPayload(entries: [[NSPasteboard.PasteboardType.rtf.rawValue: Data("{\\rtf1 rich text}".utf8), NSPasteboard.PasteboardType.string.rawValue: Data("private-test-content".utf8)]])
        store.insert(reordered, preview: "private-test-content", kind: "Text")
        expectEqual(store.items.count, 1)
        expectEqual(store.items.first?.id, id)
        expectEqual(try store.payload(for: store.items[0]).entries, payload.entries)
        expectFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    @Test func testEncryptedPayloadAndIndexSurviveReloadWithoutPlaintext() throws {
        settings.value.clipboardPersistent = true
        let first = store(); first.configure(); first.insert(payload, preview: "private-test-content", kind: "Text")
        expectNil(first.error)
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: url)
            expectNil(data.range(of: Data("private-test-content".utf8)))
            expectEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        let reloaded = store(); reloaded.configure()
        expectNil(reloaded.error)
        expectEqual(reloaded.items.count, 1)
        expectEqual(try reloaded.payload(for: reloaded.items[0]).entries, payload.entries)
    }
    @Test func testModifiedCiphertextIsRejected() throws {
        settings.value.clipboardPersistent = true
        let store = store(); store.configure(); store.insert(payload, preview: "private-test-content", kind: "Text")
        let item = try requireValue(store.items.first)
        let url = directory.appendingPathComponent(item.id.uuidString + ".enc")
        var encrypted = try Data(contentsOf: url)
        encrypted[encrypted.count / 2] ^= 1
        try encrypted.write(to: url)
        expectThrows(try store.payload(for: item))
    }
    @Test func testDisablingPersistenceClearsDiskAndHistory() {
        settings.value.clipboardPersistent = true
        let store = store(); store.configure(); store.insert(payload, preview: "private-test-content", kind: "Text")
        settings.value.clipboardPersistent = false; store.configure()
        expectNil(store.error)
        expectTrue(store.items.isEmpty)
        expectFalse(FileManager.default.fileExists(atPath: directory.path))
        store.insert(payload, preview: "private-test-content", kind: "Text")
        expectEqual(store.items.count, 1)
        expectFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    @Test func testKeyFailurePausesRecordingWithoutPlaintextFallback() {
        settings.value.clipboardPersistent = true
        let store = ClipboardStore(settings: settings, directory: directory, keyProvider: { throw UtilityError("Test key failure") })
        store.configure(); store.insert(payload, preview: "private-test-content", kind: "Text")
        expectNotNil(store.error)
        expectTrue(store.items.isEmpty)
        expectFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    @Test func testPinDeleteClearAndQuitPolicy() throws {
        settings.value.clipboardPersistent = true
        let store = store(); store.configure(); store.insert(payload, preview: "private-test-content", kind: "Text")
        let id = try requireValue(store.items.first?.id)
        store.pin(id); expectEqual(store.items.first?.pinned, true)
        store.delete(id); expectTrue(store.items.isEmpty)
        expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(id.uuidString + ".enc").path))
        store.insert(payload, preview: "private-test-content", kind: "Text")
        settings.value.clearOnQuit = true; store.shutdown()
        let reload = self.store(); reload.configure(); expectTrue(reload.items.isEmpty)
    }
    @Test func testSettingsClampInvalidNumbersAndRejectShortcutDuplicates() {
        settings.value.jigglerInterval = -.infinity
        settings.value.layout.margin = -100
        expectEqual(settings.value.jigglerInterval, 60)
        expectEqual(settings.value.layout.margin, 0)
        let shortcut = settings.value.shortcuts["clipboard"]!
        expectNotNil(settings.assign(shortcut, to: "leftHalf"))
        expectNil(settings.assign(nil, to: "clipboard"))
        expectNil(settings.assign(shortcut, to: "leftHalf"))
    }
}
