import AppKit
import UtilityCore

final class HotkeyManager {
    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    var shortcuts: [String: Shortcut] = [:]
    var onAction: ((String) -> Void)?
    var suspended = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var running: Bool { tap != nil }
    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                guard !owner.suspended, type == .keyDown else { return Unmanaged.passUnretained(event) }
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let modifiers = event.flags.intersection(HotkeyManager.modifierMask).rawValue
                if let action = owner.shortcuts.first(where: { $0.value.keyCode == code && $0.value.modifiers == modifiers })?.key {
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        DispatchQueue.main.async { owner.onAction?(action) }
                    }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    func stop() {
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}
