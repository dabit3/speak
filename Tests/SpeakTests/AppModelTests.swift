import AppKit
import XCTest
import SpeakCore
@testable import Speak

final class AppModelTests: XCTestCase {
    @MainActor func testNoSpeechErrorDismissesItselfAfterAMoment() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.phase = .listening
        model.finish()
        await model.processTranscript("Um.")
        XCTAssertEqual(model.phase, .failure)
        XCTAssertEqual(model.message, DictationError.noSpeech.message)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.message, "")
    }

    @MainActor func testEmptyServerTranscriptAndShortRecordingDismissThemselves() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        for error in [DictationError.noSpeech, .tooShort] {
            fixture.model.fail(error)
            XCTAssertEqual(fixture.model.phase, .failure)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(fixture.model.phase, .idle, error.message)
        }
    }

    @MainActor func testErrorsThatNeedAttentionStayUntilDismissed() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        let sticky = DictationError("Your API key was not accepted. Update it in Preferences.")
        model.fail(DictationError.noSpeech)
        model.fail(sticky)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.phase, .failure)
        XCTAssertEqual(model.message, sticky.message)
        model.fail(DictationError.silentMicrophone("ZoomAudioDevice"))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.phase, .failure)
        XCTAssertTrue(model.message.contains("“ZoomAudioDevice”"))
        model.dismiss()
        XCTAssertEqual(model.phase, .idle)
    }

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

    @MainActor private func makeFixture() -> (model: AppModel, cleanUp: () -> Void) {
        let suite = "SpeakAppModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let pasteboard = NSPasteboard.withUniqueName()
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }, sendPaste: { _ in true })
        let model = AppModel(preferences: Preferences(defaults: defaults, checkKeychain: false), insertion: insertion, captureTarget: { target }, transientErrorDuration: .milliseconds(50))
        return (model, {
            model.shutdown()
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
        })
    }
}
