import AppKit
import SwiftUI
import ImageIO
import UtilityCore

final class ClipboardHistoryController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let settings: SettingsStore
    private var target: NSRunningApplication?
    init(store: ClipboardStore, monitor: ClipboardMonitor, settings: SettingsStore) {
        self.store = store; self.monitor = monitor; self.settings = settings
    }
    func show(target: NSRunningApplication?) {
        self.target = target
        store.prune()
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 500), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Clipboard History"
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = true
            panel.delegate = self
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: ClipboardHistoryView(store: store, select: { [weak self] in self?.select($0) }, close: { [weak self] in self?.panel?.orderOut(nil) }))
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame, let panel {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    private func select(_ item: ClipboardItem) {
        do {
            try monitor.restore(item)
            panel?.orderOut(nil)
            guard settings.value.pasteImmediately, AXIsProcessTrusted(), let target, !target.isTerminated,
                  target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            target.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
                let source = CGEventSource(stateID: .privateState)
                let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                down?.flags = .maskCommand; up?.flags = .maskCommand
                down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
            }
        } catch { store.error = "Could not restore this clipboard item. It may be unavailable or storage may be locked." }
    }
    func windowDidResignKey(_ notification: Notification) { panel?.orderOut(nil) }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardStore
    let select: (ClipboardItem) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var selection: UUID?
    @FocusState private var searchFocused: Bool
    private var filtered: [ClipboardItem] { store.items.filter { query.isEmpty || $0.preview.localizedCaseInsensitiveContains(query) || $0.kind.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 8) {
            TextField("Search local clipboard history", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                .accessibilityLabel("Search clipboard history")
                .onSubmit { choose() }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            if filtered.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No clipboard history" : "No matches", systemImage: "clipboard", description: Text("Copy something in another app. Brief copies and excluded apps are ignored."))
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { item in
                        HStack(spacing: 10) {
                            ClipboardThumbnail(item: item, store: store)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.preview.replacingOccurrences(of: "\n", with: " ")).lineLimit(2)
                                Text("\(item.kind) · \(item.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if item.pinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned") }
                        }
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { select(item) }
                        .contextMenu {
                            Button("Copy to Clipboard") { select(item) }
                            Button(item.pinned ? "Unpin" : "Pin") { store.pin(item.id) }
                            Button("Delete", role: .destructive) { store.delete(item.id) }
                        }
                    }
                }.listStyle(.inset)
            }
            HStack {
                Text("↑↓ Navigate · Return Select · Esc Close").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Pin") { if let selection { store.pin(selection) } }.disabled(selection == nil)
                Button("Delete") { remove() }.keyboardShortcut(.delete, modifiers: .command).disabled(selection == nil)
            }
        }
        .padding(12).frame(minWidth: 440, minHeight: 440)
        .onAppear { searchFocused = true; selection = filtered.first?.id }
        .onChange(of: query) { _, _ in selection = filtered.first?.id }
        .onChange(of: store.items) { _, _ in if !filtered.contains(where: { $0.id == selection }) { selection = filtered.first?.id } }
        .background(PanelKeyHandler { event in
            switch event.keyCode {
            case 125: navigate(1)
            case 126: navigate(-1)
            case 36, 76: choose()
            case 53: close()
            case 51 where event.modifierFlags.contains(.command): remove()
            default: return false
            }
            return true
        })
    }
    private func choose() { if let item = filtered.first(where: { $0.id == selection }) ?? filtered.first { select(item) } }
    private func remove() { if let selection { store.delete(selection) } }
    private func navigate(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = filtered.firstIndex(where: { $0.id == selection }) ?? 0
        selection = filtered[min(max(0, current + delta), filtered.count - 1)].id
    }
}

/// Intercepts navigation before the focused native search field consumes arrow keys.
private struct PanelKeyHandler: NSViewRepresentable {
    var handle: (NSEvent) -> Bool
    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) { view.handle = handle }
    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.stop() }
    final class KeyView: NSView {
        var handle: ((NSEvent) -> Bool)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                return self.handle?(event) == true ? nil : event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { stop() }
    }
}

struct ClipboardThumbnail: View {
    let item: ClipboardItem
    let store: ClipboardStore
    @State private var thumbnail: NSImage?
    var body: some View {
        Group {
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
            else { Image(systemName: item.kind == "Image" ? "photo" : item.kind == "File" ? "doc" : "text.alignleft").foregroundStyle(.secondary) }
        }.frame(width: 36, height: 36).task(id: item.id) {
            guard item.kind == "Image", let payload = try? store.payload(for: item), let entry = payload.entries.first,
                  let data = entry[NSPasteboard.PasteboardType.png.rawValue] ?? entry[NSPasteboard.PasteboardType.tiff.rawValue],
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 80, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
            thumbnail = NSImage(cgImage: image, size: .zero)
        }
    }
}
