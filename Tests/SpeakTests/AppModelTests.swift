import AppKit
import XCTest
@testable import Speak

final class AppModelTests: XCTestCase {
    @MainActor func testReleaseAutomaticallyPastesBeforeUpdatingTheTranscriptView() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        var model: AppModel!
        var pasteCount = 0
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }) { pid in
            XCTAssertEqual(pid, target.processID)
            XCTAssertEqual(pasteboard.string(forType: .string), "Hello from dictation.")
            XCTAssertEqual(model.lastTranscript, "")
            pasteCount += 1
            return true
        }
        model = AppModel(insertion: insertion, captureTarget: { target })
        model.phase = .listening
        model.finish()
        XCTAssertEqual(model.phase, .finishing)
        model.complete("Hello from dictation.")
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(model.lastTranscript, "Hello from dictation.")
        XCTAssertEqual(model.message, "Sent to Editor")
        model.shutdown()
        model = nil
    }

    @MainActor func testChangingAppsAfterReleaseDoesNotPasteIntoTheNewApp() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var focused = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { focused }, hasPermission: { true }) { _ in
            XCTFail("Do not paste into an app selected after releasing the shortcut")
            return true
        }
        let model = AppModel(insertion: insertion, captureTarget: { focused })
        model.phase = .listening
        model.finish()
        focused = InsertionTarget(processID: 200, name: "Other", element: nil, isSecure: false)
        model.complete("Dictated text")
        XCTAssertEqual(pasteboard.string(forType: .string), "Dictated text")
        XCTAssertEqual(model.message, "Copied · press ⌘V to paste")
        model.shutdown()
    }

    @MainActor func testCancelledRecordingDoesNotPasteALateTranscript() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }) { _ in
            XCTFail("Do not paste a cancelled recording")
            return true
        }
        let model = AppModel(insertion: insertion, captureTarget: { target })
        model.phase = .listening
        model.finish()
        model.cancel()
        model.complete("Late transcript")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.lastTranscript.isEmpty)
        XCTAssertNil(pasteboard.string(forType: .string))
        model.shutdown()
    }
}
