import AppKit
import Combine
import UtilityCore

enum UtilityShortcut: String, CaseIterable, Identifiable {
    case clipboard, keepAwake, jiggler
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clipboard: return "Clipboard History"
        case .keepAwake: return "Toggle Keep Awake"
        case .jiggler: return "Toggle Mouse Jiggler"
        }
    }
    var command: String { self == .keepAwake ? "awake:toggle" : rawValue }
}

struct Preferences: Codable {
    var layout = LayoutSettings()
    var shortcuts: [String: Shortcut] = [:]
    var jigglerInterval: Double = 60
    var subtleJiggler = true
    var jigglerExclusions = ""
    var clipboardEnabled = true
    var clipboardPersistent = false
    var clipboardLimit = 100
    var clipboardAgeDays = 7
    var clipboardMaxMB = 5
    var ignoreBriefCopies = true
    var clearOnQuit = false
    var pasteImmediately = false
    var excludedApps = ClipboardPrivacyFilter.defaultExclusions.joined(separator: "\n")
    var exclusions: Set<String> { Set(excludedApps.split(whereSeparator: \.isWhitespace).map(String.init)) }
    static var defaults: Preferences {
        var result = Preferences()
        let flags = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue
        let keys: [(UInt16, String)] = [(123,"←"),(124,"→"),(126,"↑"),(125,"↓"),(32,"U"),(34,"I"),(38,"J"),(40,"K"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(36,"↩"),(8,"C"),(51,"⌫"),(47,"."),(43,","),(46,"M")]
        for (action, key) in zip(WindowAction.allCases, keys) {
            result.shortcuts[action.rawValue] = Shortcut(keyCode: key.0, modifiers: flags, label: key.1)
        }
        result.shortcuts["clipboard"] = Shortcut(keyCode: 9, modifiers: flags, label: "V")
        return result
    }
}

final class SettingsStore: ObservableObject {
    @Published var startup: StartupState {
        didSet {
            if let data = try? JSONEncoder().encode(startup) { defaults?.set(data, forKey: "startupState") }
        }
    }
    @Published var value: Preferences { didSet { save() } }
    var onChange: (() -> Void)?
    private let defaults: UserDefaults?
    private var isSaving = false
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        startup = defaults?.data(forKey: "startupState").flatMap { try? JSONDecoder().decode(StartupState.self, from: $0) } ?? StartupState()
        if let data = defaults?.data(forKey: "preferences"), let value = try? JSONDecoder().decode(Preferences.self, from: data) {
            self.value = value
        } else { value = .defaults }
    }
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        value.layout.margin = value.layout.margin.isFinite ? min(200, max(0, value.layout.margin)) : 0
        value.layout.horizontalGap = value.layout.horizontalGap.isFinite ? min(100, max(0, value.layout.horizontalGap)) : 0
        value.layout.verticalGap = value.layout.verticalGap.isFinite ? min(100, max(0, value.layout.verticalGap)) : 0
        value.jigglerInterval = value.jigglerInterval.isFinite ? min(3600, max(10, value.jigglerInterval)) : 60
        if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: "preferences") }
        onChange?()
    }
    func resetShortcuts() { value.shortcuts = Preferences.defaults.shortcuts }
    func assign(_ shortcut: Shortcut?, to action: String) -> String? {
        if let shortcut, let conflict = value.shortcuts.first(where: { $0.key != action && $0.value.matches(shortcut) }) {
            return "Already used by \(WindowAction(rawValue: conflict.key)?.title ?? UtilityShortcut(rawValue: conflict.key)?.title ?? conflict.key)."
        }
        value.shortcuts[action] = shortcut
        return nil
    }
}

extension Shortcut {
    var display: String {
        let flags = CGEventFlags(rawValue: modifiers)
        return (flags.contains(.maskControl) ? "⌃" : "") + (flags.contains(.maskAlternate) ? "⌥" : "") + (flags.contains(.maskShift) ? "⇧" : "") + (flags.contains(.maskCommand) ? "⌘" : "") + label
    }
}
