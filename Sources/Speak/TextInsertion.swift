import AppKit
import SpeakCore

@MainActor
struct InsertionTarget {
    let processID: pid_t
    let name: String
    let element: AXUIElement?
    let isSecure: Bool

    static func capture() -> InsertionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let element = focusedElement(in: application)
        var subrole: CFTypeRef?
        if let element { AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) }
        return InsertionTarget(processID: app.processIdentifier, name: app.localizedName ?? "your app", element: element, isSecure: subrole as? String == "AXSecureTextField")
    }

    static func focusedElement(in application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func canPaste(into current: InsertionTarget?) -> Bool {
        guard let current else { return false }
        return current.processID == processID && !isSecure && !current.isSecure
    }
}

@MainActor
final class TextInsertion {
    enum Result { case pasted, copied }
    private let pasteboard: NSPasteboard
    private let captureTarget: () -> InsertionTarget?
    private let hasPermission: () -> Bool
    private let sendPaste: (pid_t) -> Bool
    private var restoreTask: Task<Void, Never>?
    private var pendingSnapshot: [[NSPasteboard.PasteboardType: Data]]?
    private var pendingChangeCount: Int?

    init(
        pasteboard: NSPasteboard = .general,
        captureTarget: (() -> InsertionTarget?)? = nil,
        hasPermission: (() -> Bool)? = nil,
        sendPaste: ((pid_t) -> Bool)? = nil
    ) {
        self.pasteboard = pasteboard
        self.captureTarget = captureTarget ?? InsertionTarget.capture
        self.hasPermission = hasPermission ?? AXIsProcessTrusted
        self.sendPaste = sendPaste ?? Self.pasteToApplication
    }

    func insert(_ text: String, into target: InsertionTarget?) -> Result {
        restoreClipboard()
        guard hasPermission(), let target, target.canPaste(into: captureTarget()) else {
            copy(text)
            return .copied
        }
        let snapshot = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pendingSnapshot = snapshot
        pendingChangeCount = pasteboard.changeCount
        guard sendPaste(target.processID) else {
            pendingSnapshot = nil
            pendingChangeCount = nil
            return .copied
        }
        restoreTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            self?.restoreClipboard()
        }
        return .pasted
    }

    private static func pasteToApplication(_ processID: pid_t) -> Bool {
        if processID == ProcessInfo.processInfo.processIdentifier {
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(processID)
        up.postToPid(processID)
        return true
    }

    func copy(_ text: String) {
        restoreClipboard()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func restoreClipboard() {
        restoreTask?.cancel()
        restoreTask = nil
        defer { pendingSnapshot = nil; pendingChangeCount = nil }
        guard let pendingSnapshot, pasteboard.changeCount == pendingChangeCount else { return }
        pasteboard.clearContents()
        let items = pendingSnapshot.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
