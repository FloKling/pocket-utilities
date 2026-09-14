import AppKit
import IOKit.pwr_mgt
import ServiceManagement
import Testing
import UtilityCore
@testable import PocketUtilities

final class StubWindows: WindowAccessibility {
    let first = AXUIElementCreateApplication(101)
    let second = AXUIElementCreateApplication(102)
    var useSecond = false
    var firstFrame = CGRect(x: 15, y: 22, width: 333, height: 444)
    var secondFrame = CGRect(x: 66, y: 77, width: 555, height: 666)
    var refuse = false
    var partialFailure = false
    func focusedWindow(pid: pid_t?) throws -> AXUIElement { useSecond ? second : first }
    func frame(_ window: AXUIElement) throws -> CGRect { CFEqual(window, first) ? firstFrame : secondFrame }
    func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
        if refuse { throw UtilityError("Refused") }
        let actual = partialFailure ? CGRect(origin: frame.origin, size: CGSize(width: 200, height: 200)) : frame
        if CFEqual(window, first) { firstFrame = actual } else { secondFrame = actual }
        if partialFailure { throw UtilityError("Partial") }
    }
}

struct WindowManagerTests {
    @Test func snapBackIsPerWindowAndRestoresImmediatelyPreviousFrame() throws {
        let access = StubWindows()
        let originalFirst = access.firstFrame, originalSecond = access.secondFrame
        let manager = WindowManager(accessibility: access, settings: SettingsStore(defaults: nil), screenFrames: { [CGRect(x: 0, y: 0, width: 1200, height: 900)] })
        try manager.perform(.leftHalf)
        let half = access.firstFrame
        try manager.perform(.rightThird)
        try manager.perform(.snapBack)
        #expect(access.firstFrame == half)
        access.useSecond = true
        try manager.perform(.maximize)
        try manager.perform(.snapBack)
        #expect(access.secondFrame == originalSecond)
        access.useSecond = false
        try manager.perform(.snapBack)
        #expect(access.firstFrame != originalFirst)
        #expect(access.firstFrame == CGRect(x: 800, y: 0, width: 400, height: 900))
    }
    @Test func noOpAndRejectedMovesKeepUsefulSnapBackWhilePartialMovesReplaceIt() throws {
        let access = StubWindows()
        let original = access.firstFrame
        let manager = WindowManager(accessibility: access, settings: SettingsStore(defaults: nil), screenFrames: { [CGRect(x: 0, y: 0, width: 1200, height: 900)] })
        try manager.perform(.leftHalf)
        try manager.perform(.leftHalf)
        access.refuse = true
        #expect(throws: UtilityError.self) { try manager.perform(.rightHalf) }
        access.refuse = false
        try manager.perform(.snapBack)
        #expect(access.firstFrame == original)
        access.partialFailure = true
        #expect(throws: UtilityError.self) { try manager.perform(.maximize) }
        #expect(access.firstFrame != original)
        access.partialFailure = false
        try manager.perform(.snapBack)
        #expect(access.firstFrame == original)
    }
    @Test func displayActionsAndMissingHistory() throws {
        let access = StubWindows()
        let manager = WindowManager(accessibility: access, settings: SettingsStore(defaults: nil), screenFrames: { [CGRect(x: 0, y: 0, width: 1200, height: 900), CGRect(x: -900, y: 0, width: 900, height: 1600)] })
        #expect(throws: UtilityError.self) { try manager.perform(.snapBack) }
        try manager.perform(.nextDisplayMaximize)
        #expect(access.firstFrame == CGRect(x: -900, y: 0, width: 900, height: 1600))
        try manager.perform(.previousDisplay)
        #expect(access.firstFrame == CGRect(x: 0, y: 0, width: 1200, height: 900))
    }
}

struct KeepAwakeTests {
    @Test func preventsDisplaySleepAsWellAsIdleSystemSleep() {
        #expect(KeepAwakeService.assertionType == kIOPMAssertionTypePreventUserIdleDisplaySleep)
    }
    @Test func timedAssertionExpiresAndOffIsIdempotent() throws {
        var now = Date(timeIntervalSince1970: 10000)
        var released: [UInt32] = []
        let service = KeepAwakeService(createAssertion: { 42 }, releaseAssertion: { released.append($0) }, now: { now })
        try service.enable(minutes: 15)
        #expect(service.active)
        now = now.addingTimeInterval(899)
        service.expireIfNeeded(); #expect(service.active)
        now = now.addingTimeInterval(1)
        service.expireIfNeeded(); #expect(!service.active)
        #expect(service.deadline == nil)
        service.disable(); #expect(released == [42])
    }
    @Test func replacingAndDeinitializingReleaseAssertions() throws {
        var released: [UInt32] = []
        var id: UInt32 = 0
        var service: KeepAwakeService? = KeepAwakeService(createAssertion: { id += 1; return id }, releaseAssertion: { released.append($0) })
        try service?.enable(minutes: 30)
        try service?.enable()
        #expect(released == [1])
        #expect(service?.deadline == nil)
        service = nil
        #expect(released == [1, 2])
    }
    @Test func failureDoesNotReportActive() {
        let service = KeepAwakeService(createAssertion: { throw UtilityError("Power management unavailable") })
        #expect(throws: UtilityError.self) { try service.enable() }
        #expect(!service.active)
        #expect(service.deadline == nil)
    }
}

struct ShortcutSettingsTests {
    @Test func utilityCommandsRouteToTheirServices() {
        #expect(UtilityShortcut.keepAwake.command == "awake:toggle")
        #expect(UtilityShortcut.jiggler.command == "jiggler")
        #expect(UtilityShortcut.clipboard.command == "clipboard")
    }

    @Test func bindingsPersistClearAndResetWithoutChangingOtherSettings() throws {
        let name = "PocketUtilities.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.value.jigglerInterval = 120
        let shortcut = Shortcut(keyCode: 51, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌫")
        #expect(settings.assign(shortcut, to: "keepAwake") == nil)
        #expect(SettingsStore(defaults: defaults).value.shortcuts["keepAwake"]?.matches(shortcut) == true)
        #expect(settings.assign(shortcut, to: "jiggler") == "Already used by Toggle Keep Awake.")
        #expect(settings.value.shortcuts["jiggler"] == nil)
        #expect(settings.assign(nil, to: "keepAwake") == nil)
        #expect(SettingsStore(defaults: defaults).value.shortcuts["keepAwake"] == nil)
        #expect(settings.assign(shortcut, to: "jiggler") == nil)
        settings.resetShortcuts()
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.value.shortcuts["jiggler"] == nil)
        #expect(reloaded.value.shortcuts.count == Preferences.defaults.shortcuts.count)
        #expect(reloaded.value.jigglerInterval == 120)
    }
}


struct WindowFrameWriterTests {
    @Test func minimumWidthIsAcceptedAndPositionStillApplied() throws {
        var actual = CGRect(x: 0, y: 0, width: 900, height: 700)
        let requested = CGRect(x: 600, y: 0, width: 600, height: 900)
        var operations: [String] = []
        try WindowFrameWriter.apply(resizable: true, setSize: {
            operations.append("size")
            actual.size = CGSize(width: max(800, requested.width), height: requested.height)
            return .success
        }, setPosition: {
            operations.append("position")
            actual.origin = requested.origin
            return .success
        })
        #expect(actual == CGRect(x: 600, y: 0, width: 800, height: 900))
        #expect(operations == ["size", "position", "size"])
    }

    @Test func acceptedAsynchronousWritesDoNotRequireImmediateGeometry() throws {
        var pending: [String] = []
        try WindowFrameWriter.apply(resizable: true,
            setSize: { pending.append("size"); return .success },
            setPosition: { pending.append("position"); return .success })
        #expect(pending == ["size", "position", "size"])
    }

    @Test func rejectedInitialSizeDoesNotMoveWindow() {
        var moved = false
        #expect(throws: UtilityError.self) {
            try WindowFrameWriter.apply(resizable: true, setSize: { .cannotComplete },
                setPosition: { moved = true; return .success })
        }
        #expect(!moved)
    }

    @Test func rejectedPositionAndFinalSizeRemainErrors() {
        #expect(throws: UtilityError.self) {
            try WindowFrameWriter.apply(resizable: true, setSize: { .success }, setPosition: { .cannotComplete })
        }
        var sizes = 0
        #expect(throws: UtilityError.self) {
            try WindowFrameWriter.apply(resizable: true,
                setSize: { sizes += 1; return sizes == 1 ? .success : .cannotComplete },
                setPosition: { .success })
        }
        #expect(sizes == 2)
    }

    @Test func fixedSizeWindowOnlyMoves() throws {
        var sizes = 0
        var moved = false
        try WindowFrameWriter.apply(resizable: false,
            setSize: { sizes += 1; return .failure },
            setPosition: { moved = true; return .success })
        #expect(sizes == 0)
        #expect(moved)
    }
}

struct WindowResolutionTests {
    private let app = AXUIElementCreateApplication(201)
    private let first = AXUIElementCreateApplication(202)
    private let second = AXUIElementCreateApplication(203)

    private func service(_ values: [String: CFTypeRef], error: AXError? = nil) -> AccessibilityService {
        AccessibilityService { _, name in
            if name == kAXFocusedWindowAttribute, let error { return (error, nil) }
            if name == kAXSubroleAttribute { return (.success, kAXStandardWindowSubrole as CFString) }
            if let value = values[name] { return (.success, value) }
            return (.noValue, nil)
        }
    }
    @Test func focusedWindowTakesPriorityOverMainWindow() throws {
        let access = service([kAXFocusedWindowAttribute: first, kAXMainWindowAttribute: second])
        #expect(CFEqual(try access.resolveWindow(in: app), first))
    }
    @Test func mainWindowWorksWhenFocusedWindowIsUnsupported() throws {
        let access = service([kAXMainWindowAttribute: second], error: .attributeUnsupported)
        #expect(CFEqual(try access.resolveWindow(in: app), second))
    }
    @Test func focusedControlSuppliesContainingWindowBeforeMainWindow() throws {
        let access = service([kAXFocusedUIElementAttribute: app, kAXWindowAttribute: first, kAXMainWindowAttribute: second])
        #expect(CFEqual(try access.resolveWindow(in: app), first))
    }
    @Test func singleWindowFallbackWorksButAmbiguousWindowsAreRejected() throws {
        #expect(CFEqual(try service([kAXWindowsAttribute: [first] as CFArray]).resolveWindow(in: app), first))
        for windows in [[], [first, second]] as [[AXUIElement]] {
            #expect(throws: UtilityError.self) {
                try service([kAXWindowsAttribute: windows as CFArray]).resolveWindow(in: app)
            }
        }
    }
    @Test func timeoutDoesNotSelectAnotherWindow() {
        #expect(throws: UtilityError.self) {
            try service([kAXMainWindowAttribute: second], error: .cannotComplete).resolveWindow(in: app)
        }
    }
    @Test func focusedDialogDoesNotFallBackToMainWindow() {
        let access = AccessibilityService { element, name in
            if name == kAXFocusedWindowAttribute { return (.success, first) }
            if name == kAXMainWindowAttribute { return (.success, second) }
            if name == kAXSubroleAttribute {
                return (.success, (CFEqual(element, first) ? kAXDialogSubrole : kAXStandardWindowSubrole) as CFString)
            }
            return (.noValue, nil)
        }
        #expect(throws: UtilityError.self) { try access.resolveWindow(in: app) }
    }
    @Test func minimizedAndFullscreenWindowsRemainExcluded() {
        for values: [String: CFTypeRef] in [
            [kAXMainWindowAttribute: first, kAXMinimizedAttribute: kCFBooleanTrue!],
            [kAXMainWindowAttribute: first, "AXFullScreen": kCFBooleanTrue!]
        ] {
            #expect(throws: UtilityError.self) { try service(values).resolveWindow(in: app) }
        }
    }
}


struct DirectPasteSettingsTests {
    @Test func directPastePersistsAcrossLaunchesAndNotifiesLiveSettings() throws {
        let name = "PocketUtilities.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.value.pasteImmediately)
        var observed: [Bool] = []
        settings.onChange = { observed.append(settings.value.pasteImmediately) }
        settings.value.pasteImmediately.toggle()
        #expect(SettingsStore(defaults: defaults).value.pasteImmediately)
        settings.value.pasteImmediately.toggle()
        #expect(!SettingsStore(defaults: defaults).value.pasteImmediately)
        #expect(observed == [true, false])
    }
}


struct StartupTests {
    @Test func oldPreferencesAndUtilityStateSurviveReload() throws {
        let name = "PocketUtilities.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var existing = Preferences.defaults
        existing.pasteImmediately = true
        existing.layout.margin = 17
        defaults.set(try JSONEncoder().encode(existing), forKey: "preferences")
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.value.pasteImmediately)
        #expect(settings.value.layout.margin == 17)
        #expect(settings.startup == StartupState())
        settings.startup = StartupState(restoreUtilities: true, keepAwake: true,
            awakeDeadline: Date(timeIntervalSince1970: 10000), mouseJiggler: true)
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.startup == settings.startup)
        #expect(reloaded.value.pasteImmediately)
        #expect(reloaded.value.shortcuts.count == existing.shortcuts.count)
    }
    @Test func timedSessionRetainsDeadlineAndExpiresWithoutRestartingDuration() {
        var now = Date(timeIntervalSince1970: 10000)
        var released: [UInt32] = []
        let awake = KeepAwakeService(createAssertion: { 42 }, releaseAssertion: { released.append($0) }, now: { now })
        let end = now.addingTimeInterval(23)
        let state = StartupState(keepAwake: true, awakeDeadline: end, mouseJiggler: true)
        var jiggler = false
        #expect(state.restore(awake: awake, enableJiggler: { jiggler = $0 }).isEmpty)
        #expect(awake.active && jiggler)
        #expect(awake.deadline == end)
        now = end
        awake.expireIfNeeded()
        #expect(!awake.active)
        #expect(released == [42])
        #expect(state.restore(awake: awake, enableJiggler: { _ in }).isEmpty)
        #expect(!awake.active)
    }
    @Test func indefiniteSessionRestoresAndOptOutSkipsServices() {
        let awake = KeepAwakeService(createAssertion: { 42 }, releaseAssertion: { _ in })
        var state = StartupState(restoreUtilities: false, keepAwake: true, mouseJiggler: true)
        var calls = 0
        #expect(state.restore(awake: awake, enableJiggler: { _ in calls += 1 }).isEmpty)
        #expect(!awake.active && calls == 0)
        state.restoreUtilities = true
        #expect(state.restore(awake: awake, enableJiggler: { _ in calls += 1 }).isEmpty)
        #expect(awake.active && awake.deadline == nil && calls == 1)
    }
    @Test func failureInOneUtilityDoesNotPreventRestoringTheOther() {
        let awake = KeepAwakeService(createAssertion: { throw UtilityError("Unavailable") })
        var jiggler = false
        let errors = StartupState(keepAwake: true, mouseJiggler: true)
            .restore(awake: awake, enableJiggler: { jiggler = $0 })
        #expect(errors.count == 1)
        #expect(!awake.active && jiggler)
    }
    @Test func loginRegistrationReflectsApprovalAndExternalChanges() {
        var status = SMAppService.Status.notRegistered
        let login = LoginItemService(readStatus: { status }, register: { status = .requiresApproval }, unregister: { status = .notRegistered })
        login.setEnabled(true)
        #expect(login.requested && login.status == .requiresApproval)
        status = .enabled
        login.refresh()
        #expect(login.status == .enabled)
        login.setEnabled(false)
        #expect(!login.requested && login.error == nil)
    }
    @Test func loginFailuresDoNotClaimSuccess() {
        let login = LoginItemService(readStatus: { .notRegistered }, register: { throw UtilityError("Denied") }, unregister: {})
        login.setEnabled(true)
        #expect(!login.requested && login.error != nil)
        let enabled = LoginItemService(readStatus: { .enabled }, register: {}, unregister: { throw UtilityError("Denied") })
        enabled.setEnabled(false)
        #expect(enabled.requested && enabled.error != nil)
    }
}
