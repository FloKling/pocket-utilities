import AppKit
import IOKit.pwr_mgt

final class KeepAwakeService {
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?
    private(set) var deadline: Date?
    var onChange: (() -> Void)?
    private let createAssertion: () throws -> IOPMAssertionID
    private let releaseAssertion: (IOPMAssertionID) -> Void
    private let now: () -> Date
    static let assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep
    init(createAssertion: @escaping () throws -> IOPMAssertionID = {
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(KeepAwakeService.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Pocket Utilities — Keep Awake" as CFString, &identifier)
        guard result == kIOReturnSuccess else { throw UtilityError("macOS could not create a sleep-prevention assertion (\(result)).") }
        return identifier
    }, releaseAssertion: @escaping (IOPMAssertionID) -> Void = { IOPMAssertionRelease($0) }, now: @escaping () -> Date = Date.init) {
        self.createAssertion = createAssertion; self.releaseAssertion = releaseAssertion; self.now = now
    }
    var active: Bool { assertion != 0 }
    func enable(minutes: Int? = nil) throws {
        disable()
        assertion = try createAssertion()
        if let minutes {
            deadline = now().addingTimeInterval(Double(minutes) * 60)
            let timer = Timer(timeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in self?.disable() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        onChange?()
    }
    func expireIfNeeded() { if let deadline, now() >= deadline { disable() } }
    func disable() {
        timer?.invalidate(); timer = nil; deadline = nil
        if assertion != 0 { releaseAssertion(assertion); assertion = 0 }
        onChange?()
    }
    deinit { if assertion != 0 { releaseAssertion(assertion) }; timer?.invalidate() }
}

final class MouseJigglerService {
    private var timer: Timer?
    private let settings: SettingsStore
    var active: Bool { timer != nil }
    var sessionAvailable = true
    var onChange: (() -> Void)?
    init(settings: SettingsStore) { self.settings = settings }
    func setEnabled(_ enabled: Bool) throws {
        timer?.invalidate(); timer = nil
        if enabled {
            guard AXIsProcessTrusted() else { throw UtilityError("Mouse Jiggler requires Accessibility permission.") }
            let timer = Timer(timeInterval: max(10, settings.value.jigglerInterval), repeats: true) { [weak self] _ in self?.jiggle() }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        onChange?()
    }
    func reconfigure() { if active { try? setEnabled(true) } }
    private func jiggle() {
        guard sessionAvailable, AXIsProcessTrusted(), NSApp.currentSystemPresentationOptions.isEmpty,
              let front = NSWorkspace.shared.frontmostApplication,
              !Set(settings.value.jigglerExclusions.split(whereSeparator: \.isWhitespace).map(String.init)).contains(front.bundleIdentifier ?? "") else { return }
        // Fail closed if we cannot establish that the frontmost app has a normal window.
        // CGWindow metadata avoids reading Accessibility trees for this unrelated utility.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for screen in NSScreen.screens {
            let full = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
            if frame.width >= full.width - 4 && frame.height >= full.height - 4 { return }
        }
        for number in 0..<32 {
            if CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32(number))!) { return }
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved) > 5,
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) > 5,
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel) > 5,
              let position = CGEvent(source: nil)?.location else { return }
        let delta: CGFloat = settings.value.subtleJiggler ? 1 : 2
        let shifted = CGPoint(x: position.x + (position.x > frame.midX ? -delta : delta), y: position.y)
        let source = CGEventSource(stateID: .privateState)
        // Queue the pair together: never restore after a delay that could overwrite a real movement.
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: shifted, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: position, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    deinit { timer?.invalidate() }
}
