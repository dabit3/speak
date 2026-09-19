import AppKit
import SpeakCore

@MainActor
final class GlobalShortcut {
    var onAction: ((ShortcutMachine.Action) -> Void)?
    var onCancel: (() -> Void)?
    var onPaste: (() -> Void)?
    var onCopy: (() -> Void)?
    var isActive: () -> Bool = { false }
    var usesFunctionKey = true
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var machine = ShortcutMachine()
    private var pressed = false

    func install() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(info).takeUnretainedValue()
            return MainActor.assumeIsolated { owner.handle(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func enterHandsFree() { machine.enterHandsFree() }

    func reset() {
        machine.reset()
        pressed = false
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            onCancel?()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let held = usesFunctionKey
            ? flags.contains(.maskSecondaryFn)
            : flags.contains([.maskControl, .maskAlternate]) && !flags.contains(.maskCommand)
        if type == .flagsChanged {
            if held && !pressed {
                pressed = true
                if let action = machine.press(at: ProcessInfo.processInfo.systemUptime) { onAction?(action) }
            } else if !held && pressed {
                pressed = false
                if let action = machine.release(at: ProcessInfo.processInfo.systemUptime) { onAction?(action) }
            }
            if usesFunctionKey && key == 63 { return nil }
        }
        if type == .keyDown {
            if key == 53 && isActive() {
                reset()
                onCancel?()
                return nil
            }
            if key == 49 && held {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                   let action = machine.space() { onAction?(action) }
                return nil
            }
            if flags.contains([.maskControl, .maskCommand]), !flags.contains(.maskAlternate), !flags.contains(.maskShift) {
                if key == 9 { onPaste?(); return nil }
                if key == 8 { onCopy?(); return nil }
            }
        }
        if type == .keyUp && key == 49 && held { return nil }
        return Unmanaged.passUnretained(event)
    }
}
