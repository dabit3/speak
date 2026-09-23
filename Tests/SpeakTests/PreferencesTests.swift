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

    @MainActor func testPillPositionDefaultsToBottomAndPersists() async {
        let suite = "SpeakPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults, checkKeychain: false)
        XCTAssertEqual(preferences.pillPosition, .bottom)
        preferences.pillPosition = .right
        XCTAssertEqual(Preferences(defaults: defaults, checkKeychain: false).pillPosition, .right)
        defaults.set("top", forKey: "pillPosition")
        XCTAssertEqual(Preferences(defaults: defaults, checkKeychain: false).pillPosition, .bottom)
    }

    @MainActor func testPillFrameFollowsTheChosenEdge() async {
        let visible = NSRect(x: 100, y: 50, width: 1000, height: 800)
        XCTAssertEqual(PillController.frame(for: .bottom, in: visible, width: 430, height: 70), NSRect(x: 385, y: 55, width: 430, height: 70))
        XCTAssertEqual(PillController.frame(for: .left, in: visible, width: 430, height: 70), NSRect(x: 105, y: 415, width: 430, height: 70))
        XCTAssertEqual(PillController.frame(for: .right, in: visible, width: 430, height: 70), NSRect(x: 665, y: 415, width: 430, height: 70))
        let idle = PillController.frame(for: .right, in: visible, width: 150, height: 70)
        let expanded = PillController.frame(for: .right, in: visible, width: 430, height: 190)
        XCTAssertEqual(idle.maxX, expanded.maxX)
        XCTAssertEqual(idle.minY, expanded.minY)
        XCTAssertEqual(PillController.frame(for: .left, in: visible, width: 150, height: 70).minX, 105)
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
