import AppKit
import SwiftUI
import UtilityCore

final class SettingsController: NSObject, NSWindowDelegate, ObservableObject {
    @Published var selectedTab = "layout"
    private var window: NSWindow?
    let settings: SettingsStore
    let accessibility: AccessibilityService
    let hotkeys: HotkeyManager
    init(settings: SettingsStore, accessibility: AccessibilityService, hotkeys: HotkeyManager) {
        self.settings = settings; self.accessibility = accessibility; self.hotkeys = hotkeys
    }
    func show(tab: String? = nil) {
        if let tab { selectedTab = tab }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 570), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Pocket Utilities Settings"
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, accessibility: accessibility, hotkeys: hotkeys, controller: self))
            window.isReleasedWhenClosed = false; window.delegate = self
            window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { hotkeys.suspended = false }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let accessibility: AccessibilityService
    let hotkeys: HotkeyManager
    @ObservedObject var controller: SettingsController
    var body: some View {
        TabView(selection: $controller.selectedTab) {
            Form {
                Section("Spacing in points") {
                    number("Outer margin", value: $settings.value.layout.margin, range: 0...200)
                    number("Horizontal gap", value: $settings.value.layout.horizontalGap, range: 0...100)
                    number("Vertical gap", value: $settings.value.layout.verticalGap, range: 0...100)
                }
                Text("Layouts respect menu bars and the Dock. Adjacent layouts share one gap. SnapBack restores the frame immediately before the last action.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).tabItem { Label("Layout", systemImage: "rectangle.split.2x2") }.tag("layout")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Click a shortcut and press a combination. Escape cancels; unmodified Delete clears. Use Command, Control or Option.").font(.caption).foregroundStyle(.secondary)
                    ForEach(WindowAction.allCases) { action in shortcutRow(action.title, key: action.rawValue) }
                    Divider()
                    ForEach(UtilityShortcut.allCases) { action in shortcutRow(action.title, key: action.rawValue) }
                    Button("Restore Default Shortcuts") { settings.resetShortcuts() }
                    Text("Duplicates within this app are rejected. macOS provides no complete conflict list for other apps. If a shortcut is already used elsewhere, choose another combination.").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
            Form {
                Section("Mouse Jiggler") {
                    number("Interval (seconds)", value: $settings.value.jigglerInterval, range: 10...3600)
                    Toggle("Subtle mode (1 point; otherwise 2)", isOn: $settings.value.subtleJiggler)
                    Text("Excluded application bundle IDs (one per line)").font(.caption)
                    TextEditor(text: $settings.value.jigglerExclusions).frame(height: 65).font(.system(.caption, design: .monospaced))
                    Text("Skips recent input, held buttons/modifiers, full-screen-sized windows and unavailable sessions. For games, add their bundle IDs or turn Jiggler off.").font(.caption).foregroundStyle(.secondary)
                }
                Section("General") {
                    Text("Keep Awake and Mouse Jiggler always start OFF. Keep Awake keeps the Mac and display awake while enabled. Manual locking, lid closure, separate screen-saver timers and managed security policies remain under macOS control.")
                    Text("One menu-bar icon. No accounts, network services or automatic updates.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "slider.horizontal.3") }.tag("general")
            Form {
                Section("Clipboard privacy") {
                    Toggle("Record clipboard history", isOn: $settings.value.clipboardEnabled)
                    Toggle("Persist encrypted history on this Mac", isOn: $settings.value.clipboardPersistent)
                    Text("Default: memory-only. Turning persistence off clears all history. Persistent data uses AES-GCM and a local Keychain key.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Ignore copies that last less than 2 seconds", isOn: $settings.value.ignoreBriefCopies)
                    Toggle("Clear history when quitting normally", isOn: $settings.value.clearOnQuit)
                    Toggle("Direct Paste (requires Accessibility)", isOn: $settings.value.pasteImmediately)
                    Text("Double-click or press Return to close History and paste into the previous app. When Direct Paste is off, selection only copies to the clipboard.").font(.caption).foregroundStyle(.secondary)
                    Stepper("Maximum items: \(settings.value.clipboardLimit)", value: $settings.value.clipboardLimit, in: 10...500, step: 10)
                    Stepper("Maximum age: \(settings.value.clipboardAgeDays) days", value: $settings.value.clipboardAgeDays, in: 1...90)
                    Stepper("Maximum item size: \(settings.value.clipboardMaxMB) MB", value: $settings.value.clipboardMaxMB, in: 1...20)
                    Text("Pins stay above normal entries but still obey all limits.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Excluded source apps — bundle IDs") {
                    TextEditor(text: $settings.value.excludedApps).frame(height: 85).font(.system(.caption, design: .monospaced))
                    Text("Known password-manager markings are always ignored. Source app detection is best effort; pause recording before copying sensitive data from other apps.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Clipboard", systemImage: "clipboard") }.tag("clipboard")
            PermissionsView(accessibility: accessibility, hotkeys: hotkeys).tabItem { Label("Permissions", systemImage: "hand.raised") }.tag("permissions")
        }.padding(8).frame(width: 610, height: 570)
    }
    private func number(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField(title, value: value, format: .number).frame(width: 70); Stepper("", value: value, in: range).labelsHidden() }
    }
    private func shortcutRow(_ title: String, key: String) -> some View {
        HStack { Text(title); Spacer(); ShortcutRecorder(settings: settings, hotkeys: hotkeys, action: key).frame(width: 180, height: 26) }
    }
}

struct PermissionsView: View {
    let accessibility: AccessibilityService
    let hotkeys: HotkeyManager
    @State private var granted = AXIsProcessTrusted()
    @State private var running = false
    var body: some View {
        Form {
            Section("Accessibility") {
                Label(granted ? "Permission granted" : "Permission needed for window control", systemImage: granted ? "checkmark.circle.fill" : "hand.raised")
                Text("Pocket Utilities uses Accessibility to move the window you request, handle global shortcuts and optionally synthesize paste or tiny pointer movements. Clipboard copying and Keep Awake work without it.")
                Button("Open Accessibility Settings…") { accessibility.requestPermission() }
                Button("Recheck Permission & Start Shortcuts") { granted = accessibility.trusted; hotkeys.start(); running = hotkeys.running }
                Text(running ? "Global shortcuts active" : "Shortcuts are inactive until permission is granted and rechecked.").font(.caption)
                Text("Enable Pocket Utilities in Privacy & Security → Accessibility. macOS may also ask for Input Monitoring for the event tap. If necessary, grant it and restart the app. No permission prompts are shown repeatedly.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { granted = accessibility.trusted; running = hotkeys.running }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var settings: SettingsStore
    let hotkeys: HotkeyManager
    let action: String
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button; button.action = #selector(RecorderButton.begin)
        button.settings = settings; button.hotkeys = hotkeys; button.actionID = action
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        if button.monitor == nil { button.title = settings.value.shortcuts[action]?.display ?? "Click to record…" }
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.finish() }
}

final class RecorderButton: NSButton {
    var settings: SettingsStore!
    weak var hotkeys: HotkeyManager?
    var actionID = ""
    var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private static weak var activeRecorder: RecorderButton?
    @objc func begin() {
        guard monitor == nil else { return }
        Self.activeRecorder?.finish()
        Self.activeRecorder = self
        toolTip = nil
        hotkeys?.suspended = true; title = "Press shortcut…"
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.finish() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(HotkeyManager.modifierMask)
            if event.keyCode == 53 && flags.isEmpty { self.finish(); return nil }
            if event.keyCode == 51 && flags.isEmpty { _ = self.settings.assign(nil, to: self.actionID); self.finish(); return nil }
            guard !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { self.title = "Add ⌘, ⌃ or ⌥"; return nil }
            let names: [UInt16: String] = [123:"←",124:"→",125:"↓",126:"↑",36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",117:"⌦"]
            let label = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            let shortcut = Shortcut(keyCode: event.keyCode, modifiers: flags.rawValue, label: label)
            if let error = self.settings.assign(shortcut, to: self.actionID) { self.title = "Conflict — try again"; self.toolTip = error }
            else { self.finish() }
            return nil
        }
    }
    func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil; monitor = nil
        if Self.activeRecorder === self { Self.activeRecorder = nil; hotkeys?.suspended = false }
        toolTip = nil
        title = settings?.value.shortcuts[actionID]?.display ?? "Click to record…"
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) }; if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) } }
}
