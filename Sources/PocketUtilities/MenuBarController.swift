import AppKit
import UtilityCore

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let settings: SettingsStore
    private let windowManager: WindowManager
    private let accessibility: AccessibilityService
    private let hotkeys: HotkeyManager
    private let awake: KeepAwakeService
    private let jiggler: MouseJigglerService
    private let clipboard: ClipboardHistoryController
    private let monitor: ClipboardMonitor
    private let store: ClipboardStore
    private let preferences: SettingsController
    private var lastApplication: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    init(settings: SettingsStore, windowManager: WindowManager, accessibility: AccessibilityService,
         hotkeys: HotkeyManager, awake: KeepAwakeService, jiggler: MouseJigglerService,
         clipboard: ClipboardHistoryController, monitor: ClipboardMonitor, store: ClipboardStore, preferences: SettingsController) {
        self.settings = settings; self.windowManager = windowManager; self.accessibility = accessibility
        self.hotkeys = hotkeys; self.awake = awake; self.jiggler = jiggler; self.clipboard = clipboard
        self.monitor = monitor; self.store = store; self.preferences = preferences
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Pocket Utilities")
        statusItem.button?.toolTip = "Pocket Utilities"
        menu.delegate = self; statusItem.menu = menu
        lastApplication = NSWorkspace.shared.frontmostApplication
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.lastApplication = application
        })
        rebuild()
    }
    func menuNeedsUpdate(_ menu: NSMenu) { awake.expireIfNeeded(); hotkeys.start(); rebuild() }
    func refreshAwakeState() {
        guard let item = menu.items.first(where: { ($0.representedObject as? String) == "awake:toggle" }) else { return }
        item.title = awake.active ? (awake.deadline.map { "On until " + $0.formatted(date: .omitted, time: .shortened) } ?? "On indefinitely") : "Off"
        item.state = awake.active ? .on : .off
    }
    private func item(_ title: String, _ command: String, in menu: NSMenu, checked: Bool = false) {
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = command; item.state = checked ? .on : .off
        menu.addItem(item)
    }
    private func section(_ title: String) { menu.addItem(NSMenuItem.sectionHeader(title: title)) }
    private func group(_ title: String, actions: [WindowAction]) {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for action in actions { addWindowAction(action, to: submenu) }
        parent.submenu = submenu; menu.addItem(parent)
    }
    private func addWindowAction(_ action: WindowAction, to menu: NSMenu) {
        let shortcut = settings.value.shortcuts[action.rawValue].map { "    " + $0.display } ?? ""
        item(action.title + shortcut, "window:" + action.rawValue, in: menu)
    }
    func rebuild() {
        menu.removeAllItems()
        section("Window Management")
        for action: WindowAction in [.leftHalf, .rightHalf, .topHalf, .bottomHalf] { addWindowAction(action, to: menu) }
        group("Quarters", actions: [.topLeft, .topRight, .bottomLeft, .bottomRight])
        group("Thirds", actions: [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds])
        for action: WindowAction in [.maximize, .center, .snapBack] { addWindowAction(action, to: menu) }
        group("Move to Display", actions: [.nextDisplay, .previousDisplay, .nextDisplayMaximize])
        menu.addItem(.separator())
        section("Keep Awake")
        let state = awake.deadline.map { "On until " + $0.formatted(date: .omitted, time: .shortened) } ?? "On indefinitely"
        item(awake.active ? state : "Off", "awake:toggle", in: menu, checked: awake.active)
        let durations = NSMenuItem(title: "Set Duration", action: nil, keyEquivalent: "")
        let options = NSMenu()
        for (title, minutes) in [("15 Minutes", 15), ("30 Minutes", 30), ("1 Hour", 60), ("2 Hours", 120), ("Indefinitely", 0)] {
            item(title, "awake:\(minutes)", in: options)
        }
        durations.submenu = options; menu.addItem(durations)
        menu.addItem(.separator())
        section("Mouse Jiggler")
        item(jiggler.active ? "On · every \(Int(max(10, settings.value.jigglerInterval))) seconds" : "Off", "jiggler", in: menu, checked: jiggler.active)
        menu.addItem(.separator())
        section("Clipboard")
        item("Show History…" + (settings.value.shortcuts["clipboard"].map { "    " + $0.display } ?? ""), "clipboard", in: menu)
        item("Direct Paste", "directPaste", in: menu, checked: settings.value.pasteImmediately)
        item("Pause Recording", "pause", in: menu, checked: monitor.paused)
        if !settings.value.clipboardEnabled { menu.addItem(NSMenuItem.sectionHeader(title: "Recording disabled in Settings")) }
        if store.error != nil { menu.addItem(NSMenuItem.sectionHeader(title: "Storage error — open History for details")) }
        item("Clear History…", "clear", in: menu)
        item("Clipboard Settings…", "clipboardSettings", in: menu)
        menu.addItem(.separator())
        item(accessibility.trusted ? "Accessibility: Allowed" : "Accessibility: Permission Needed…", "permission", in: menu)
        item("Configure Shortcuts…", "shortcutSettings", in: menu)
        item("Settings…", "settings", in: menu)
        item("Quit Pocket Utilities", "quit", in: menu)
    }
    @objc private func run(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        execute(command)
    }
    func shortcut(_ action: String) {
        execute(UtilityShortcut(rawValue: action)?.command ?? "window:" + action)
    }
    private func execute(_ command: String) {
        do {
            if command.hasPrefix("window:"), let action = WindowAction(rawValue: String(command.dropFirst(7))) {
                // Menu-bar menus do not normally change focus; Settings/History do.
                let front = NSWorkspace.shared.frontmostApplication
                let target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastApplication : front
                try windowManager.perform(action, pid: target?.processIdentifier)
            } else if command.hasPrefix("awake:") {
                let value = String(command.dropFirst(6))
                if value == "toggle" { if awake.active { awake.disable() } else { try awake.enable() } }
                else if let minutes = Int(value) { try awake.enable(minutes: minutes == 0 ? nil : minutes) }
            } else {
                switch command {
                case "jiggler": try jiggler.setEnabled(!jiggler.active)
                case "clipboard": clipboard.show(target: lastApplication)
                case "directPaste": settings.value.pasteImmediately.toggle()
                case "pause": monitor.paused.toggle()
                case "clear":
                    let alert = NSAlert(); alert.messageText = "Clear all clipboard history?"
                    alert.informativeText = "This also removes pinned items and encrypted history files. The current system clipboard is unchanged."
                    alert.addButton(withTitle: "Clear History"); alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn { store.clear(); monitor.resetBaseline() }
                case "settings": preferences.show()
                case "shortcutSettings": preferences.show(tab: "shortcuts")
                case "clipboardSettings": preferences.show(tab: "clipboard")
                case "permission": preferences.show(tab: "permissions")
                case "quit": NSApp.terminate(nil)
                default: break
                }
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "Action unavailable"; alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    deinit { for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}
