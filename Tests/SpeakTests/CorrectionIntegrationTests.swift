import AppKit
import XCTest
import SpeakCore
@testable import Speak

actor AppCorrectionStub: TranscriptCorrecting {
    private(set) var calls = 0
    let corrected: String
    let delay: Duration
    let started: (@Sendable () -> Void)?

    init(corrected: String = "Please merge this pull request into main.", delay: Duration = .zero, started: (@Sendable () -> Void)? = nil) {
        self.corrected = corrected
        self.delay = delay
        self.started = started
    }

    func correct(_ text: String, context: CorrectionContext) async throws -> String {
        calls += 1
        started?()
        if delay > .zero { try await Task.sleep(for: delay) }
        return corrected
    }
}

final class CorrectionIntegrationTests: XCTestCase {
    private let raw = "Please merge this pool request into main."
    private let fixed = "Please merge this pull request into main."

    @MainActor func testFinalCorrectionIsPastedOnceAndOriginalCanBeRecovered() async {
        let fixture = makeFixture()
        defer { fixture.model.shutdown(); fixture.pasteboard.releaseGlobally(); fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.model.phase = .listening
        fixture.model.finish()
        await fixture.model.processTranscript(raw)
        XCTAssertEqual(fixture.model.lastTranscript, fixed)
        XCTAssertEqual(fixture.model.lastOriginalTranscript, raw)
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), fixed)
        XCTAssertEqual(fixture.model.phase, .success)
        fixture.model.copyOriginal()
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), raw)
    }

    @MainActor func testDisabledCorrectionMakesNoRequest() async {
        let fixture = makeFixture()
        defer { fixture.model.shutdown(); fixture.pasteboard.releaseGlobally(); fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.model.preferences.smartCorrectionEnabled = false
        fixture.model.phase = .listening
        fixture.model.receivePartial(raw)
        fixture.model.finish()
        await fixture.model.processTranscript(raw)
        let calls = await fixture.service.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(fixture.model.lastTranscript, raw)
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), raw)
    }

    @MainActor func testCancellationDuringCorrectionNeverPastes() async {
        let started = expectation(description: "Correction started")
        let service = AppCorrectionStub(delay: .seconds(1), started: { started.fulfill() })
        let fixture = makeFixture(service: service)
        defer { fixture.model.shutdown(); fixture.pasteboard.releaseGlobally(); fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.model.phase = .listening
        fixture.model.finish()
        let request = Task { await fixture.model.processTranscript(raw) }
        await fulfillment(of: [started], timeout: 1)
        fixture.model.cancel()
        await request.value
        XCTAssertEqual(fixture.model.phase, .idle)
        XCTAssertTrue(fixture.model.lastTranscript.isEmpty)
        XCTAssertTrue(fixture.model.lastOriginalTranscript.isEmpty)
        XCTAssertNil(fixture.pasteboard.string(forType: .string))
    }

    @MainActor func testHiddenPreviewStillFeedsCorrectionAndPastes() async {
        let fixture = makeFixture()
        defer { fixture.model.shutdown(); fixture.pasteboard.releaseGlobally(); fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.model.preferences.showLiveTranscript = false
        fixture.model.phase = .listening
        fixture.model.receivePartial(raw)
        XCTAssertFalse(fixture.model.showsLiveTranscript)
        XCTAssertEqual(fixture.model.pillHeight, 70)
        fixture.model.finish()
        await fixture.model.processTranscript(raw)
        XCTAssertEqual(fixture.model.lastTranscript, fixed)
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), fixed)
    }

    @MainActor private func makeFixture(service: AppCorrectionStub = AppCorrectionStub()) -> (model: AppModel, service: AppCorrectionStub, pasteboard: NSPasteboard, defaults: UserDefaults, suite: String) {
        let suite = "SpeakCorrectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = Preferences(defaults: defaults, checkKeychain: false)
        let pasteboard = NSPasteboard.withUniqueName()
        let target = InsertionTarget(processID: 100, name: "Editor", element: nil, isSecure: false)
        let insertion = TextInsertion(pasteboard: pasteboard, captureTarget: { target }, hasPermission: { true }, sendPaste: { _ in true })
        let correction = SmartCorrection(service: service)
        let model = AppModel(preferences: preferences, insertion: insertion, captureTarget: { target }, correction: correction)
        return (model, service, pasteboard, defaults, suite)
    }
}
