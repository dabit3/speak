import AppKit

enum Spelling {
    @MainActor static func isKnown(_ word: String, language: String) -> Bool {
        let checker = NSSpellChecker.shared
        var code: String?
        if !language.isEmpty {
            code = checker.availableLanguages.first { $0 == language || $0.hasPrefix(language + "_") }
            guard code != nil else { return true }
        }
        return checker.checkSpelling(of: word, startingAt: 0, language: code, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
}

@MainActor
protocol EditableField: AnyObject {
    var text: String? { get }
    var caret: Int? { get }
    var isFocused: Bool { get }
}

@MainActor
final class AccessibilityField: EditableField {
    static let maximumLength = 20_000
    private let element: AXUIElement
    private let processID: pid_t

    init(element: AXUIElement, processID: pid_t) {
        self.element = element
        self.processID = processID
        AXUIElementSetMessagingTimeout(element, 0.25)
    }

    var text: String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf16.count <= Self.maximumLength else { return nil }
        return text
    }

    var caret: Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.location + range.length
    }

    var isFocused: Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return false }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let focused = InsertionTarget.focusedElement(in: application) else { return false }
        return CFEqual(focused, element)
    }
}

@MainActor
final class EditWatcher {
    static let duration: TimeInterval = 60
    static let locateTimeout: TimeInterval = 3
    private let pasted: String
    private let field: any EditableField
    private let started: TimeInterval
    private let onEdit: (String) -> Void
    private var anchor: (prefix: String, suffix: String)?
    private var lastText: String?
    private var edited: String?
    private var task: Task<Void, Never>?
    private(set) var isFinished = false

    init(pasted: String, field: any EditableField, at time: TimeInterval, onEdit: @escaping (String) -> Void) {
        self.pasted = pasted
        self.field = field
        started = time
        self.onEdit = onEdit
    }

    func start(every interval: Duration = .milliseconds(500)) {
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, !self.isFinished else { return }
                self.tick(at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func tick(at time: TimeInterval) {
        guard !isFinished else { return }
        guard time - started < Self.duration, field.isFocused, let text = field.text else { return finish() }
        guard let anchor else {
            if !locate(in: text), time - started >= Self.locateTimeout { cancel() }
            return
        }
        guard text != lastText else { return }
        lastText = text
        guard text.count >= anchor.prefix.count + anchor.suffix.count, text.hasPrefix(anchor.prefix), text.hasSuffix(anchor.suffix) else { return finish() }
        let region = String(text.dropFirst(anchor.prefix.count).dropLast(anchor.suffix.count))
        guard !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return finish() }
        edited = region
    }

    func finish() {
        guard !isFinished else { return }
        cancel()
        if let edited, edited != pasted { onEdit(edited) }
    }

    func cancel() {
        isFinished = true
        task?.cancel()
        task = nil
    }

    private func locate(in text: String) -> Bool {
        let string = text as NSString, length = (pasted as NSString).length
        var start: Int?
        if let caret = field.caret, caret >= length, caret <= string.length,
           string.substring(with: NSRange(location: caret - length, length: length)) == pasted {
            start = caret - length
        } else {
            let first = string.range(of: pasted), last = string.range(of: pasted, options: .backwards)
            if first.location != NSNotFound, first.location == last.location { start = first.location }
        }
        guard let start else { return false }
        anchor = (string.substring(to: start), string.substring(from: start + length))
        lastText = text
        return true
    }
}
