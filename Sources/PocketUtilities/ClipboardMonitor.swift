import AppKit
import UtilityCore

final class ClipboardMonitor: ObservableObject {
    @Published var paused = false { didSet { pending = nil; lastCount = NSPasteboard.general.changeCount } }
    var sessionAvailable = true { didSet { pending = nil; lastCount = NSPasteboard.general.changeCount } }
    private let settings: SettingsStore
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastCount: Int
    private var pending: (count: Int, source: String?, time: Date)?
    private var lastPrune = Date()
    init(settings: SettingsStore, store: ClipboardStore) {
        self.settings = settings; self.store = store
        lastCount = NSPasteboard.general.changeCount
    }
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func resetBaseline() { pending = nil; lastCount = NSPasteboard.general.changeCount }
    func stop() { timer?.invalidate(); timer = nil; pending = nil }
    private func tick() {
        guard sessionAvailable else { return }
        if Date().timeIntervalSince(lastPrune) > 60 { store.prune(); lastPrune = Date() }
        let board = NSPasteboard.general
        guard !paused, settings.value.clipboardEnabled, store.error == nil else { resetBaseline(); return }
        if board.changeCount != lastCount {
            lastCount = board.changeCount
            let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let types = Set((board.types ?? []).map(\.rawValue))
            guard ClipboardPrivacyFilter.allows(types: types, source: source, exclusions: settings.value.exclusions) else { pending = nil; return }
            pending = (lastCount, source, Date())
            if !settings.value.ignoreBriefCopies { capture(board) }
        } else if let pending, Date().timeIntervalSince(pending.time) >= 2 { capture(board) }
    }
    private func capture(_ board: NSPasteboard) {
        guard let pending else { return }
        self.pending = nil
        guard pending.count == board.changeCount else { return }
        let types = Set((board.types ?? []).map(\.rawValue))
        guard ClipboardPrivacyFilter.allows(types: types, source: pending.source, exclusions: settings.value.exclusions) else { return }
        let maxBytes = max(1, settings.value.clipboardMaxMB) * 1_048_576
        let supported: Set<NSPasteboard.PasteboardType> = [.string, .rtf, .rtfd, .html, .URL, .fileURL, .png, .tiff]
        var entries: [[String: Data]] = []
        var byteCount = 0
        for item in board.pasteboardItems ?? [] {
            guard ClipboardPrivacyFilter.allows(types: Set(item.types.map(\.rawValue)), source: pending.source, exclusions: settings.value.exclusions) else { return }
            var entry: [String: Data] = [:]
            for type in item.types where supported.contains(type) {
                if let data = item.data(forType: type) {
                    guard data.count <= maxBytes - byteCount else { return }
                    byteCount += data.count; entry[type.rawValue] = data
                }
            }
            if !entry.isEmpty { entries.append(entry) }
        }
        guard !entries.isEmpty, board.changeCount == pending.count else { return }
        let payload = ClipboardPayload(entries: entries)
        let first = entries[0]
        var preview = "Clipboard item"
        var kind = "Text"
        if let file = first[NSPasteboard.PasteboardType.fileURL.rawValue], let text = String(data: file, encoding: .utf8) {
            preview = URL(string: text)?.path ?? text; kind = "File"
        } else if let data = first[NSPasteboard.PasteboardType.string.rawValue], let text = String(data: data, encoding: .utf8) {
            preview = String(text.prefix(300)); kind = first[NSPasteboard.PasteboardType.URL.rawValue] == nil ? "Text" : "URL"
        } else if let data = first[NSPasteboard.PasteboardType.URL.rawValue], let text = String(data: data, encoding: .utf8) {
            preview = text; kind = "URL"
        } else if first[NSPasteboard.PasteboardType.png.rawValue] != nil || first[NSPasteboard.PasteboardType.tiff.rawValue] != nil {
            preview = "Image · \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))"; kind = "Image"
        } else if let data = first[NSPasteboard.PasteboardType.rtf.rawValue], let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string {
            preview = text; kind = "Rich text"
        } else { kind = "Rich text"; preview = "Rich text content" }
        store.insert(payload, preview: preview, kind: kind)
    }
    func restore(_ item: ClipboardItem) throws {
        let payload = try store.payload(for: item)
        let objects = payload.entries.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            // Other clipboard managers should not create another copy of restored history.
            item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
            return item
        }
        let board = NSPasteboard.general
        board.clearContents()
        guard board.writeObjects(objects) else { throw UtilityError("Could not restore this item to the system clipboard.") }
        resetBaseline()
    }
    deinit { timer?.invalidate() }
}
