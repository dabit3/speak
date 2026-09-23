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
        func frame(_ position: PillPosition, idle: Bool, height: CGFloat = 70) -> NSRect {
            PillController.frame(for: position, in: visible, size: PillController.size(for: position, idle: idle, height: height))
        }
        XCTAssertEqual(frame(.bottom, idle: false), NSRect(x: 385, y: 55, width: 430, height: 70))
        XCTAssertEqual(frame(.bottom, idle: true), NSRect(x: 525, y: 55, width: 150, height: 70))
        XCTAssertEqual(frame(.bottom, idle: false, height: 190).height, 190)
        XCTAssertEqual(frame(.left, idle: false), NSRect(x: 105, y: 320, width: 430, height: 260))
        XCTAssertEqual(frame(.right, idle: true), NSRect(x: 1005, y: 390, width: 90, height: 120))
        for position in [PillPosition.left, .right] {
            let idle = frame(position, idle: true), active = frame(position, idle: false, height: 190)
            XCTAssertEqual(idle.midY, visible.midY)
            XCTAssertEqual(active.midY, visible.midY)
            XCTAssertEqual(position == .left ? idle.minX : idle.maxX, position == .left ? active.minX : active.maxX)
        }
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
