import AppKit
import ApplicationServices
import UtilityCore

struct UtilityError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

protocol WindowAccessibility {
    func focusedWindow(pid: pid_t?) throws -> AXUIElement
    func frame(_ window: AXUIElement) throws -> CGRect
    func setFrame(_ frame: CGRect, of window: AXUIElement) throws
}

final class AccessibilityService: WindowAccessibility {
    private let readAttribute: (AXUIElement, String) -> (AXError, CFTypeRef?)
    init(readAttribute: @escaping (AXUIElement, String) -> (AXError, CFTypeRef?) = { element, name in
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return (result, value)
    }) { self.readAttribute = readAttribute }
    var trusted: Bool { AXIsProcessTrusted() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        let (result, value) = readAttribute(element, name)
        return result == .success ? value : nil
    }
    private func windowAttribute(_ element: AXUIElement, _ name: String) throws -> AXUIElement? {
        let (result, value) = readAttribute(element, name)
        switch result {
        case .success:
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        case .noValue, .attributeUnsupported: return nil
        case .cannotComplete:
            throw UtilityError("The application did not respond to Accessibility. Try again when it is responsive.")
        case .apiDisabled:
            throw UtilityError("Accessibility access is unavailable. Recheck Pocket Utilities in macOS Accessibility settings.")
        default: throw UtilityError("The application's window could not be read (Accessibility error \(result.rawValue)).")
        }
    }
    func resolveWindow(in application: AXUIElement) throws -> AXUIElement {
        if let window = try windowAttribute(application, kAXFocusedWindowAttribute) { return try validated(window) }
        // Some apps expose focus only through the focused control's containing window.
        if let focused = try windowAttribute(application, kAXFocusedUIElementAttribute),
           let window = try windowAttribute(focused, kAXWindowAttribute) { return try validated(window) }
        if let window = try windowAttribute(application, kAXMainWindowAttribute) { return try validated(window) }
        // Never assume AXWindows is ordered by focus, particularly with multiple project/chat windows.
        let (result, value) = readAttribute(application, kAXWindowsAttribute)
        guard result == .success else {
            throw UtilityError("The application did not expose a usable window list (Accessibility error \(result.rawValue)).")
        }
        guard let windows = value as? [AXUIElement], windows.count == 1, let window = windows.first else {
            throw UtilityError("The application did not identify its active window. Click the target window and try again.")
        }
        return try validated(window)
    }
    private func validated(_ window: AXUIElement) throws -> AXUIElement {
        if (attribute(window, kAXMinimizedAttribute) as? Bool) == true || (attribute(window, "AXFullScreen") as? Bool) == true {
            throw UtilityError("Minimized and native full-screen windows are not moved.")
        }
        guard (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole else {
            throw UtilityError("Dialogs, sheets and nonstandard windows are left untouched.")
        }
        return window
    }

    func focusedWindow(pid: pid_t? = nil) throws -> AXUIElement {
        guard trusted else { throw UtilityError("Allow Accessibility in Settings → Permissions to control windows.") }
        guard let pid = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier else { throw UtilityError("No active application.") }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        return try resolveWindow(in: application)
    }

    func frame(_ window: AXUIElement) throws -> CGRect {
        guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { throw UtilityError("The window does not expose a frame.") }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { throw UtilityError("The window frame could not be read.") }
        return CGRect(origin: point, size: dimensions)
    }
    func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
        let original = try self.frame(window)
        var movable: DarwinBoolean = false
        var resizable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
        guard movable.boolValue else { throw UtilityError("This window cannot be moved.") }
        guard resizable.boolValue || original.size == frame.size else { throw UtilityError("This window cannot be resized.") }
        var point = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else { throw UtilityError("Invalid window geometry.") }
        try WindowFrameWriter.apply(resizable: resizable.boolValue,
            setSize: { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) },
            setPosition: { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) })
    }
}

// AX success means the app accepted the request. Apps may enforce size constraints or
// report geometry asynchronously; an immediate exact-frame comparison is not a failure test.
enum WindowFrameWriter {
    static func apply(resizable: Bool, setSize: () -> AXError, setPosition: () -> AXError) throws {
        if resizable {
            guard setSize() == .success else { throw UtilityError("The application refused the requested size.") }
        }
        guard setPosition() == .success else {
            throw UtilityError("The application refused the requested position; size may have changed. SnapBack can restore it.")
        }
        // Retry sizing after moving because the destination display may have different bounds.
        if resizable {
            guard setSize() == .success else {
                throw UtilityError("The application refused the size after moving. SnapBack can restore it.")
            }
        }
    }
}

struct DisplayService {
    var usableFrames: [CGRect] {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { LayoutEngine.quartzFrame($0.visibleFrame, primaryHeight: height) }
    }
    func index(for window: CGRect, in screens: [CGRect]) -> Int {
        screens.indices.max { a, b in
            let first = screens[a].intersection(window), second = screens[b].intersection(window)
            return (first.isNull ? 0 : first.width * first.height) < (second.isNull ? 0 : second.width * second.height)
        } ?? 0
    }
}

final class WindowManager {
    let accessibility: WindowAccessibility
    let settings: SettingsStore
    private let screenFrames: () -> [CGRect]
    private var history: [(window: AXUIElement, frame: CGRect)] = []
    init(accessibility: WindowAccessibility, settings: SettingsStore, screenFrames: @escaping () -> [CGRect] = { DisplayService().usableFrames }) {
        self.accessibility = accessibility; self.settings = settings; self.screenFrames = screenFrames
    }
    func perform(_ action: WindowAction, pid: pid_t? = nil) throws {
        let window = try accessibility.focusedWindow(pid: pid)
        let before = try accessibility.frame(window)
        let displays = DisplayService()
        let screens = screenFrames()
        guard !screens.isEmpty else { throw UtilityError("No display is available.") }
        let index = displays.index(for: before, in: screens)
        let destination: CGRect
        if let fraction = action.fraction { destination = LayoutEngine.frame(fraction: fraction, screen: screens[index], settings: settings.value.layout) }
        else {
            switch action {
            case .center: destination = LayoutEngine.centered(before, on: LayoutEngine.frame(fraction: WindowAction.maximize.fraction!, screen: screens[index], settings: settings.value.layout))
            case .snapBack:
                guard let previous = history.first(where: { CFEqual($0.window, window) }) else { throw UtilityError("No previous frame is stored for this window.") }
                destination = previous.frame
            case .nextDisplay, .previousDisplay, .nextDisplayMaximize:
                guard screens.count > 1 else { throw UtilityError("Only one display is connected.") }
                let next = (index + (action == .previousDisplay ? screens.count - 1 : 1)) % screens.count
                destination = action == .nextDisplayMaximize
                    ? LayoutEngine.frame(fraction: WindowAction.maximize.fraction!, screen: screens[next], settings: settings.value.layout)
                    : LayoutEngine.transfer(before, from: screens[index], to: screens[next])
            default: return
            }
        }
        guard destination != before else { return }
        do {
            try accessibility.setFrame(destination, of: window)
            remember(window, before: before)
        } catch {
            // A rejected/no-op action must not destroy the last useful SnapBack frame.
            if let actual = try? accessibility.frame(window), actual != before { remember(window, before: before) }
            throw error
        }
    }
    private func remember(_ window: AXUIElement, before: CGRect) {
        history.removeAll { CFEqual($0.window, window) }
        history.insert((window, before), at: 0)
        if history.count > 100 { history.removeLast() }
    }
}
