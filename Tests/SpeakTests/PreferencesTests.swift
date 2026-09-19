import XCTest
@testable import Speak

final class PreferencesTests: XCTestCase {
    @MainActor func testNewPreferencesDefaultToCorrectionAndVisibleLiveText() async {
        let suite = "SpeakPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults, checkKeychain: false)
        XCTAssertTrue(preferences.smartCorrectionEnabled)
        XCTAssertTrue(preferences.showLiveTranscript)
        XCTAssertTrue(preferences.showPill)
    }

    @MainActor func testPreferencesPersistIndependentlyAcrossLaunches() async {
        let suite = "SpeakPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults, checkKeychain: false)
        preferences.showLiveTranscript = false
        preferences.smartCorrectionEnabled = false
        let restored = Preferences(defaults: defaults, checkKeychain: false)
        XCTAssertFalse(restored.showLiveTranscript)
        XCTAssertFalse(restored.smartCorrectionEnabled)
        XCTAssertTrue(restored.showPill)
    }

    @MainActor func testHiddenLiveTextDoesNotHideThePillOrErrors() async {
        let suite = "SpeakPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults, checkKeychain: false)
        let model = AppModel(preferences: preferences)
        model.phase = .listening
        model.partial = "This is a live transcript."
        XCTAssertTrue(model.showsLiveTranscript)
        XCTAssertEqual(model.pillHeight, 190)
        preferences.showLiveTranscript = false
        XCTAssertFalse(model.showsLiveTranscript)
        XCTAssertTrue(preferences.showPill)
        XCTAssertEqual(model.pillHeight, 70)
        model.phase = .finishing
        XCTAssertFalse(model.showsLiveTranscript)
        XCTAssertEqual(model.pillHeight, 70)
        model.phase = .failure
        XCTAssertEqual(model.pillHeight, 190)
        preferences.showLiveTranscript = true
        model.phase = .idle
        XCTAssertFalse(model.showsLiveTranscript)
    }
}
