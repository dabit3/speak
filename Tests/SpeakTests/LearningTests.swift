import AppKit
import XCTest
import SpeakCore
@testable import Speak

final class LearningTests: XCTestCase {
    private let dictionary: Set<String> = ["handles", "authentication", "check", "the", "path", "pod"]

    @MainActor func testLearnedSpellingFixesLiveAndFinalText() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.preferences.smartCorrectionEnabled = false
        model.preferences.learned = LearnedWords([LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        model.phase = .listening
        model.receivePartial("Superbase handles")
        XCTAssertEqual(model.partial, "Supabase handles")
        model.finish()
        await model.processTranscript("Superbase handles authentication.")
        XCTAssertEqual(model.lastTranscript, "Supabase handles authentication.")
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), "Supabase handles authentication.")
        XCTAssertEqual(model.lastOriginalTranscript, "Superbase handles authentication.")
    }

    @MainActor func testVocabularyNamesSurviveFormattingInLiveAndFinalText() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.preferences.smartCorrectionEnabled = false
        model.preferences.vocabulary = "New Line, Twenty Four"
        model.preferences.learned = LearnedWords([LearnedWord(term: "Comma")])
        model.phase = .listening
        model.receivePartial("New Line shipped twenty five updates")
        XCTAssertEqual(model.partial, "New Line shipped 25 updates")
        model.finish()
        let raw = "New Line shipped twenty five updates. Twenty Four sent it to Comma."
        let expected = "New Line shipped 25 updates. Twenty Four sent it to Comma."
        await model.processTranscript(raw)
        XCTAssertEqual(model.lastTranscript, expected)
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), expected)
        XCTAssertEqual(model.lastOriginalTranscript, raw)
    }

    @MainActor func testFixingTheLastDictationTeachesSpeak() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.preferences.vocabulary = "Nader"
        model.lastTranscript = "Superbase handles authentication."
        model.beginFixingLastDictation()
        XCTAssertEqual(model.fixingText, "Superbase handles authentication.")
        model.fixingText = "Supabase handles authentication."
        model.saveFix()
        XCTAssertNil(model.fixingText)
        XCTAssertEqual(model.lastTranscript, "Supabase handles authentication.")
        XCTAssertEqual(model.preferences.learned.words, [LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        XCTAssertEqual(model.fixNote, "Learned “Supabase”")
        XCTAssertTrue(model.canUndoLearning)
        XCTAssertEqual(model.preferences.configuration.keywords, ["Nader", "Supabase"])
        model.undoLearning()
        XCTAssertTrue(model.preferences.learned.isEmpty)
        XCTAssertEqual(model.fixNote, "")
        XCTAssertFalse(model.canUndoLearning)
    }

    @MainActor func testFixWithoutNewTermsIsSavedButNotLearned() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.lastTranscript = "Check the path."
        model.beginFixingLastDictation()
        model.fixingText = "Check the pod."
        model.saveFix()
        XCTAssertEqual(model.lastTranscript, "Check the pod.")
        XCTAssertTrue(model.preferences.learned.isEmpty)
        XCTAssertEqual(model.fixNote, "Saved. There were no new names or terms to learn.")
        XCTAssertFalse(model.canUndoLearning)
    }

    @MainActor func testFixAppliesToTheDictationItStartedFrom() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.lastTranscript = "Superbase handles authentication."
        model.beginFixingLastDictation()
        model.fixingText = "Supabase handles authentication."
        model.lastTranscript = "A newer dictation."
        model.saveFix()
        XCTAssertEqual(model.lastTranscript, "A newer dictation.")
        XCTAssertEqual(model.preferences.learned.words, [LearnedWord(term: "Supabase", replaces: ["Superbase"])])
    }

    @MainActor func testCorrectionsInOtherAppsAreLearnedOnlyWhenTurnedOn() throws {
        let field = FakeField("Superbase handles authentication.")
        let fixture = makeFixture(field: field)
        defer { fixture.cleanUp() }
        let model = fixture.model
        XCTAssertFalse(model.preferences.learnFromCorrections)
        model.phase = .listening
        model.finish()
        model.complete("Superbase handles authentication.")
        XCTAssertNil(model.watcher)

        model.preferences.learnFromCorrections = true
        model.phase = .listening
        model.finish()
        model.complete("Superbase handles authentication.")
        let watcher = try XCTUnwrap(model.watcher)
        let now = ProcessInfo.processInfo.systemUptime
        watcher.tick(at: now)
        field.text = "Supabase handles authentication."
        watcher.tick(at: now + 1)
        field.isFocused = false
        watcher.tick(at: now + 2)
        XCTAssertEqual(model.preferences.learned.words, [LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(model.message, "Learned “Supabase”")
        XCTAssertTrue(model.showsLearningUndo)
        model.undoLearning()
        XCTAssertTrue(model.preferences.learned.isEmpty)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor func testTurningLearningOffStopsWatching() {
        let fixture = makeFixture(field: FakeField("Superbase handles authentication."))
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.preferences.learnFromCorrections = true
        model.phase = .listening
        model.finish()
        model.complete("Superbase handles authentication.")
        XCTAssertNotNil(model.watcher)
        model.preferences.learnFromCorrections = false
        XCTAssertNil(model.watcher)
    }

    @MainActor private func makeFixture(field: FakeField? = nil) -> (model: AppModel, pasteboard: NSPasteboard, cleanUp: () -> Void) {
        let suite = "SpeakLearningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let pasteboard = NSPasteboard.withUniqueName()
        let target = InsertionTarget(processID: 100, name: "Editor", element: AXUIElementCreateApplication(100), isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }, sendPaste: { _ in true })
        let dictionary = self.dictionary
        let model = AppModel(
            preferences: Preferences(defaults: defaults, checkKeychain: false),
            insertion: insertion,
            captureTarget: { target },
            isKnownWord: { dictionary.contains($0) },
            editableField: { _ in field }
        )
        return (model, pasteboard, {
            model.shutdown()
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
        })
    }
}
