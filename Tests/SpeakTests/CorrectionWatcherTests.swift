import XCTest
@testable import Speak

@MainActor
final class FakeField: EditableField {
    var text: String?
    var caret: Int?
    var isFocused = true

    init(_ text: String, caretAtEnd: Bool = true) {
        self.text = text
        caret = caretAtEnd ? (text as NSString).length : nil
    }
}

final class CorrectionWatcherTests: XCTestCase {
    private let pasted = "Superbase handles authentication."

    @MainActor func testReportsTheFixOnceTheUserMovesOn() {
        let field = FakeField("Notes: " + pasted)
        var edits: [String] = []
        let watcher = EditWatcher(pasted: pasted, field: field, at: 0) { edits.append($0) }
        watcher.tick(at: 0.5)
        field.text = "Notes: Supab handles authentication."
        watcher.tick(at: 1)
        field.text = "Notes: Supabase handles authentication."
        watcher.tick(at: 1.5)
        XCTAssertEqual(edits, [], "Changes are only reported once the edit is finished")
        field.isFocused = false
        watcher.tick(at: 2)
        XCTAssertEqual(edits, ["Supabase handles authentication."])
        XCTAssertTrue(watcher.isFinished)
    }

    @MainActor func testUsesTheLastVersionBeforeAMessageIsSent() {
        let field = FakeField(pasted)
        var edits: [String] = []
        let watcher = EditWatcher(pasted: pasted, field: field, at: 0) { edits.append($0) }
        watcher.tick(at: 0.5)
        field.text = "Supabase handles authentication. Thanks!"
        watcher.tick(at: 1)
        field.text = ""
        watcher.tick(at: 1.5)
        XCTAssertEqual(edits, ["Supabase handles authentication. Thanks!"])
    }

    @MainActor func testStopsWatchingWhenTextOutsideThePasteChanges() {
        let field = FakeField("Notes: " + pasted + " More text.", caretAtEnd: false)
        var edits: [String] = []
        let watcher = EditWatcher(pasted: pasted, field: field, at: 0) { edits.append($0) }
        watcher.tick(at: 0.5)
        field.text = "Changed notes: " + pasted + " More text."
        watcher.tick(at: 1)
        XCTAssertTrue(watcher.isFinished)
        XCTAssertEqual(edits, [])
    }

    @MainActor func testGivesUpWhenThePasteNeverAppears() {
        let field = FakeField("Something else")
        var edits: [String] = []
        let watcher = EditWatcher(pasted: pasted, field: field, at: 0) { edits.append($0) }
        watcher.tick(at: 1)
        XCTAssertFalse(watcher.isFinished)
        watcher.tick(at: EditWatcher.locateTimeout)
        XCTAssertTrue(watcher.isFinished)
        XCTAssertEqual(edits, [])
    }

    @MainActor func testStopsAfterAMinute() {
        let field = FakeField(pasted)
        var edits: [String] = []
        let watcher = EditWatcher(pasted: pasted, field: field, at: 0) { edits.append($0) }
        watcher.tick(at: 0.5)
        field.text = "Supabase handles authentication."
        watcher.tick(at: 30)
        watcher.tick(at: EditWatcher.duration)
        XCTAssertTrue(watcher.isFinished)
        XCTAssertEqual(edits, ["Supabase handles authentication."])
    }

    @MainActor func testIgnoresTextThatWasNeverChanged() {
        let field = FakeField(pasted)
        var edits: [String] = []
        let watcher = EditWatcher(pasted: pasted, field: field, at: 0) { edits.append($0) }
        watcher.tick(at: 0.5)
        field.isFocused = false
        watcher.tick(at: 1)
        XCTAssertEqual(edits, [])
    }

    @MainActor func testSpellingCheckerKnowsCommonWords() {
        XCTAssertTrue(Spelling.isKnown("the", language: "en"))
        XCTAssertFalse(Spelling.isKnown("qzxvbnmq", language: "en"))
        XCTAssertTrue(Spelling.isKnown("qzxvbnmq", language: "xx"), "Without a dictionary, Speak never treats a word as misspelled")
    }
}
