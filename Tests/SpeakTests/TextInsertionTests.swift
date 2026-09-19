import AppKit
import XCTest
@testable import Speak

final class InsertionTargetTests: XCTestCase {
    @MainActor func testMissingAccessibilityMetadataDoesNotPreventPaste() async {
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        XCTAssertTrue(target.canPaste(into: target))
    }

    @MainActor func testChangedAccessibilityElementInTheSameAppDoesNotPreventPaste() async {
        let target = InsertionTarget(processID: 100, name: "Editor", element: AXUIElementCreateApplication(100), isSecure: false)
        let current = InsertionTarget(processID: 100, name: "Editor", element: AXUIElementCreateSystemWide(), isSecure: false)
        XCTAssertTrue(target.canPaste(into: current))
    }

    @MainActor func testChangingAppsDoesNotPasteIntoAnUnintendedApp() async {
        let element = AXUIElementCreateSystemWide()
        let target = InsertionTarget(processID: 100, name: "Editor", element: element, isSecure: false)
        let current = InsertionTarget(processID: 200, name: "Other", element: element, isSecure: false)
        XCTAssertFalse(target.canPaste(into: current))
    }

    @MainActor func testPasswordFieldNeverReceivesPaste() async {
        let element = AXUIElementCreateSystemWide()
        let target = InsertionTarget(processID: 100, name: "Editor", element: element, isSecure: false)
        let current = InsertionTarget(processID: 100, name: "Editor", element: element, isSecure: true)
        XCTAssertFalse(target.canPaste(into: current))
    }

    @MainActor func testMissingForegroundAppDoesNotPaste() async {
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        XCTAssertFalse(target.canPaste(into: nil))
    }
}

final class TextInsertionTests: XCTestCase {
    @MainActor func testAutomaticPasteWithoutAccessibilityElementAndClipboardRestoration() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Original clipboard", forType: .string)
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        var pasteCount = 0
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }) { pid in
            XCTAssertEqual(pid, 100)
            XCTAssertEqual(pasteboard.string(forType: .string), "Dictated text")
            pasteCount += 1
            return true
        }
        XCTAssertEqual(insertion.insert("Dictated text", into: target), .pasted)
        XCTAssertEqual(pasteCount, 1)
        insertion.restoreClipboard()
        XCTAssertEqual(pasteboard.string(forType: .string), "Original clipboard")
    }

    @MainActor func testRestorationDoesNotOverwriteANewerClipboard() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }, sendPaste: { _ in true })
        XCTAssertEqual(insertion.insert("Dictated text", into: target), .pasted)
        pasteboard.clearContents()
        pasteboard.setString("Copied while pasting", forType: .string)
        insertion.restoreClipboard()
        XCTAssertEqual(pasteboard.string(forType: .string), "Copied while pasting")
    }

    @MainActor func testChangedAppOnlyCopiesInsteadOfSendingPaste() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let other = InsertionTarget(processID: 200, name: "Other", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { other }, hasPermission: { true }) { _ in
            XCTFail("Do not paste into a different app")
            return true
        }
        XCTAssertEqual(insertion.insert("Dictated text", into: target), .copied)
        XCTAssertEqual(pasteboard.string(forType: .string), "Dictated text")
    }

    @MainActor func testFailedPasteKeepsTheTranscriptAvailable() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Original clipboard", forType: .string)
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }, sendPaste: { _ in false })
        XCTAssertEqual(insertion.insert("Dictated text", into: target), .copied)
        insertion.restoreClipboard()
        XCTAssertEqual(pasteboard.string(forType: .string), "Dictated text")
    }

    @MainActor func testPermissionFailureDoesNotSendPaste() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { false }) { _ in
            XCTFail("Do not send paste without permission")
            return true
        }
        XCTAssertEqual(insertion.insert("Dictated text", into: target), .copied)
    }
}
