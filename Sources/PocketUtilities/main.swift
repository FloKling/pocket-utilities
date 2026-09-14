import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore(defaults: CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--preview") ? nil : .standard)
    let accessibility = AccessibilityService()
    let hotkeys = HotkeyManager()
    let awake = KeepAwakeService()
    lazy var jiggler = MouseJigglerService(settings: settings)
    lazy var store = ClipboardStore(settings: settings)
    lazy var monitor = ClipboardMonitor(settings: settings, store: store)
    lazy var windowManager = WindowManager(accessibility: accessibility, settings: settings)
    lazy var clipboard = ClipboardHistoryController(store: store, monitor: monitor, settings: settings)
    lazy var preferences = SettingsController(settings: settings, accessibility: accessibility, hotkeys: hotkeys)
    var menu: MenuBarController?
    var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // A second launch must not create another recorder or conflicting global shortcuts.
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.PocketUtilities").count > 1 {
            NSApp.terminate(nil); return
        }
        let testing = CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--preview")
        if !testing { store.configure(); monitor.start() }
        hotkeys.shortcuts = settings.value.shortcuts
        if !testing { hotkeys.start() }
        menu = MenuBarController(settings: settings, windowManager: windowManager, accessibility: accessibility,
            hotkeys: hotkeys, awake: awake, jiggler: jiggler, clipboard: clipboard, monitor: monitor, store: store, preferences: preferences)
        hotkeys.onAction = { [weak self] action in self?.menu?.shortcut(action) }
        if !testing {
            let errors = settings.startup.restore(awake: awake, enableJiggler: { try self.jiggler.setEnabled($0) })
            recordUtilityState()
            menu?.rebuild()
            if !errors.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Some startup settings could not be restored"
                alert.informativeText = errors.joined(separator: "\n")
                alert.runModal()
            }
        }
        awake.onChange = { [weak self] in
            self?.recordUtilityState(); self?.menu?.refreshAwakeState()
        }
        jiggler.onChange = { [weak self] in self?.recordUtilityState() }
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.hotkeys.shortcuts = self.settings.value.shortcuts
            self.jiggler.reconfigure(); self.monitor.resetBaseline(); self.store.configure()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.monitor.sessionAvailable = false; self?.jiggler.sessionAvailable = false
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.monitor.sessionAvailable = true; self?.jiggler.sessionAvailable = true; self?.awake.expireIfNeeded()
            })
        }
        if CommandLine.arguments.contains("--smoke-test") {
            // Exercise application setup without reading or changing the general clipboard.
            monitor.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
        if CommandLine.arguments.contains("--preview") { monitor.paused = true; preferences.show() }
    }
    private func recordUtilityState() {
        var state = settings.startup
        state.keepAwake = awake.active
        state.awakeDeadline = awake.deadline
        state.mouseJiggler = jiggler.active
        settings.startup = state
    }
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup releases resources without persisting a synthetic OFF state.
        awake.onChange = nil; jiggler.onChange = nil
        awake.disable(); try? jiggler.setEnabled(false); hotkeys.stop(); monitor.stop(); store.shutdown()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
