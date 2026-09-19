import XCTest
@testable import SpeakCore

final class ShortcutTests: XCTestCase {
    func testHoldAndRelease() {
        var shortcut = ShortcutMachine()
        XCTAssertEqual(shortcut.press(at: 1), .startHold)
        XCTAssertNil(shortcut.press(at: 1.1))
        XCTAssertEqual(shortcut.release(at: 2), .finish)
    }

    func testQuickTapDoesNotPaste() {
        var shortcut = ShortcutMachine()
        XCTAssertEqual(shortcut.press(at: 1), .startHold)
        XCTAssertEqual(shortcut.release(at: 1.1), .cancel)
    }

    func testDoubleTapLocksRecording() {
        var shortcut = ShortcutMachine()
        _ = shortcut.press(at: 1)
        _ = shortcut.release(at: 1.1)
        XCTAssertEqual(shortcut.press(at: 1.2), .startHandsFree)
        XCTAssertNil(shortcut.release(at: 1.3))
        XCTAssertNil(shortcut.press(at: 3))
        XCTAssertEqual(shortcut.release(at: 3.1), .finish)
    }

    func testSpaceLocksAndThenStopsWithoutRestarting() {
        var shortcut = ShortcutMachine()
        _ = shortcut.press(at: 1)
        XCTAssertEqual(shortcut.space(), .lock)
        XCTAssertNil(shortcut.release(at: 2))
        XCTAssertNil(shortcut.press(at: 3))
        XCTAssertEqual(shortcut.space(), .finish)
        XCTAssertNil(shortcut.release(at: 4))
    }

    func testClickStartedHandsFreeFinishesOnShortcutTap() {
        var shortcut = ShortcutMachine()
        shortcut.enterHandsFree()
        XCTAssertNil(shortcut.press(at: 1))
        XCTAssertEqual(shortcut.release(at: 1.1), .finish)
    }

    func testResetPreventsReleaseFromFinishingCancelledTake() {
        var shortcut = ShortcutMachine()
        _ = shortcut.press(at: 1)
        shortcut.reset()
        XCTAssertNil(shortcut.release(at: 2))
    }
}

final class TranscriptionTests: XCTestCase {
    func testConfigurationUsesNewModelAndManualCommit() throws {
        let config = TranscriptionConfiguration(language: "en", delay: .low, vocabulary: "Speak, PostgreSQL\nNader")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: config.sessionMessage()) as? [String: Any])
        XCTAssertEqual(root["type"] as? String, "session.update")
        let session = try XCTUnwrap(root["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        XCTAssertTrue(input["turn_detection"] is NSNull)
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
        XCTAssertEqual(transcription["delay"] as? String, "low")
        XCTAssertEqual(transcription["languages"] as? [String], ["en"])
        XCTAssertNil(transcription["language"])
        XCTAssertEqual(transcription["keywords"] as? [String], ["Speak", "PostgreSQL", "Nader"])
    }

    func testAutoLanguageDoesNotSendAnEmptyHint() throws {
        let config = TranscriptionConfiguration(language: "", delay: .medium, vocabulary: "")
        let string = String(decoding: try config.sessionMessage(), as: UTF8.self)
        XCTAssertFalse(string.contains("languages"))
        XCTAssertFalse(string.contains("keywords"))
    }

    func testVocabularyStripsInvalidCharactersAndDuplicates() {
        let config = TranscriptionConfiguration(language: "en", delay: .low, vocabulary: "<Swift>, Swift, \n API >,  , API")
        XCTAssertEqual(config.keywords, ["Swift", "API"])
    }

    func testFinalReplacesPartialAndMatchesCommittedItem() throws {
        var accumulator = TranscriptAccumulator()
        _ = try accumulator.consume(event("conversation.item.input_audio_transcription.delta", ["item_id": "a", "delta": "helo"]))
        XCTAssertEqual(accumulator.partial, "helo")
        _ = try accumulator.consume(event("input_audio_buffer.committed", ["item_id": "a"]))
        XCTAssertNil(try accumulator.consume(event("conversation.item.input_audio_transcription.completed", ["item_id": "b", "transcript": "Wrong turn"])))
        XCTAssertEqual(try accumulator.consume(event("conversation.item.input_audio_transcription.completed", ["item_id": "a", "transcript": "Hello."])), "Hello.")
    }

    func testCompletionBeforeCommitIsReconciled() throws {
        var accumulator = TranscriptAccumulator()
        XCTAssertNil(try accumulator.consume(event("conversation.item.input_audio_transcription.completed", ["item_id": "a", "transcript": "Hello."])))
        XCTAssertEqual(try accumulator.consume(event("input_audio_buffer.committed", ["item_id": "a"])), "Hello.")
    }

    func testEmptyFinalIsAnError() throws {
        var accumulator = TranscriptAccumulator()
        _ = try accumulator.consume(event("input_audio_buffer.committed", ["item_id": "a"]))
        XCTAssertThrowsError(try accumulator.consume(event("conversation.item.input_audio_transcription.completed", ["item_id": "a", "transcript": " "])))
    }

    func testFailureNeverBecomesAPartialSuccess() {
        var accumulator = TranscriptAccumulator()
        XCTAssertThrowsError(try accumulator.consume(event("conversation.item.input_audio_transcription.failed", ["error": ["message": "Transcription failed."]])))
    }

    private func event(_ type: String, _ fields: [String: Any]) -> [String: Any] {
        fields.merging(["type": type]) { _, new in new }
    }
}
