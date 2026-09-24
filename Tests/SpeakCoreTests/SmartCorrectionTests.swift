import XCTest
@testable import SpeakCore

actor CorrectionStub: TranscriptCorrecting {
    private(set) var requests: [String] = []
    let responses: [String: String]
    let delay: Duration
    let fail: Bool
    let ignoresCancellation: Bool
    let onRequest: (@Sendable () -> Void)?

    init(responses: [String: String] = [:], delay: Duration = .zero, fail: Bool = false, ignoresCancellation: Bool = false, onRequest: (@Sendable () -> Void)? = nil) {
        self.responses = responses
        self.delay = delay
        self.fail = fail
        self.ignoresCancellation = ignoresCancellation
        self.onRequest = onRequest
    }

    func correct(_ text: String, context: CorrectionContext) async throws -> String {
        requests.append(text)
        onRequest?()
        if ignoresCancellation {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { continuation.resume() }
            }
        } else if delay > .zero { try await Task.sleep(for: delay) }
        if fail { throw URLError(.notConnectedToInternet) }
        return responses[text] ?? text
    }
}

final class SmartCorrectionTests: XCTestCase {
    private let raw = "Please merge this pool request into main."
    private let corrected = "Please merge this pull request into main."

    @MainActor func testFinalTranscriptIsCorrected() async {
        let service = CorrectionStub(responses: [raw: corrected])
        let correction = SmartCorrection(service: service)
        let result = await correction.finish(raw)
        XCTAssertEqual(result, corrected)
    }

    @MainActor func testReusesMatchingSpeculativeRequest() async {
        let started = expectation(description: "Speculative request started")
        let service = CorrectionStub(responses: [raw: corrected], delay: .milliseconds(20), onRequest: { started.fulfill() })
        let correction = SmartCorrection(service: service, debounce: .zero)
        correction.preview(raw)
        await fulfillment(of: [started], timeout: 1)
        let result = await correction.finish(raw)
        let requests = await service.requests
        XCTAssertEqual(result, corrected)
        XCTAssertEqual(requests, [raw])
    }

    @MainActor func testNeverReusesCorrectionForAnOlderTranscript() async {
        let started = expectation(description: "Preview request started")
        let final = "Please merge this pool request into the release branch."
        let fixed = "Please merge this pull request into the release branch."
        let service = CorrectionStub(responses: [raw: corrected, final: fixed], delay: .milliseconds(10), onRequest: { started.fulfill() })
        started.assertForOverFulfill = false
        let correction = SmartCorrection(service: service, debounce: .zero)
        correction.preview(raw)
        await fulfillment(of: [started], timeout: 1)
        let result = await correction.finish(final)
        let requests = await service.requests
        XCTAssertEqual(result, fixed)
        XCTAssertEqual(requests, [raw, final])
    }

    @MainActor func testTimeoutDoesNotWaitForANonCooperativeService() async {
        let service = CorrectionStub(responses: [raw: corrected], ignoresCancellation: true)
        let correction = SmartCorrection(service: service, finalWait: .milliseconds(20))
        let clock = ContinuousClock()
        let start = clock.now
        let result = await correction.finish(raw)
        XCTAssertEqual(result, raw)
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(250))
    }

    @MainActor func testSelfCorrectionWaitsLongerForTheCorrection() async {
        let revised = "Send the invoice to John, I mean Sarah."
        let fixed = "Send the invoice to Sarah."
        let service = CorrectionStub(responses: [raw: corrected, revised: fixed], delay: .milliseconds(150))
        let revisedResult = await SmartCorrection(service: service, finalWait: .milliseconds(20), revisionWait: .seconds(2)).finish(revised)
        XCTAssertEqual(revisedResult, fixed)
        let plainResult = await SmartCorrection(service: service, finalWait: .milliseconds(20), revisionWait: .seconds(2)).finish(raw)
        XCTAssertEqual(plainResult, raw)
    }

    @MainActor func testFailureAndUnsafeOutputFallBackToOriginal() async {
        let failed = SmartCorrection(service: CorrectionStub(fail: true))
        let failedResult = await failed.finish(raw)
        XCTAssertEqual(failedResult, raw)
        let service = CorrectionStub(responses: [raw: "Please merge 20 pull requests into main."])
        let unsafe = SmartCorrection(service: service)
        let unsafeResult = await unsafe.finish(raw)
        XCTAssertEqual(unsafeResult, raw)
    }

    @MainActor func testCancelEndsPendingCorrectionWithoutWaitingForDeadline() async {
        let started = expectation(description: "Correction started")
        let service = CorrectionStub(delay: .seconds(1), onRequest: { started.fulfill() })
        let correction = SmartCorrection(service: service, finalWait: .seconds(2))
        let request = Task { await correction.finish(raw) }
        await fulfillment(of: [started], timeout: 1)
        correction.cancel()
        let result = await request.value
        XCTAssertEqual(result, raw)
    }

    @MainActor func testTypingShortTextMakesNoAPIRequest() async {
        let service = CorrectionStub()
        let correction = SmartCorrection(service: service)
        let result = await correction.finish("Hello")
        let requests = await service.requests
        XCTAssertEqual(result, "Hello")
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor func testPreviewsAreDebouncedAndBounded() async {
        let started = expectation(description: "Preview request started")
        let service = CorrectionStub(onRequest: { started.fulfill() })
        let correction = SmartCorrection(service: service, debounce: .milliseconds(50), maximumPreviews: 1)
        correction.preview("Please merge the first request.")
        correction.preview(raw)
        await fulfillment(of: [started], timeout: 1)
        correction.preview("Please merge a different request.")
        try? await Task.sleep(for: .milliseconds(150))
        let result = await correction.finish(raw)
        let requests = await service.requests
        XCTAssertEqual(result, raw)
        XCTAssertEqual(requests, [raw])
    }

    @MainActor func testPartialsAfterReleaseAreCorrectedBeforeTheFinalArrives() async {
        let partial = "Please merge this pool request"
        let service = CorrectionStub(responses: [raw: corrected], delay: .milliseconds(300))
        let correction = SmartCorrection(service: service, debounce: .seconds(5), releasedDebounce: .zero, finalWait: .milliseconds(150))
        correction.preview(partial)
        correction.prepareFinal()
        correction.preview(raw)
        try? await Task.sleep(for: .milliseconds(250))
        let result = await correction.finish(raw)
        let requests = await service.requests
        XCTAssertEqual(result, corrected)
        XCTAssertEqual(requests, [partial, raw])
    }

    @MainActor func testRequestsAfterReleaseAreBounded() async {
        let service = CorrectionStub()
        let correction = SmartCorrection(service: service, debounce: .seconds(5), releasedDebounce: .zero, maximumReleasedRequests: 2)
        correction.preview("Please merge this")
        correction.prepareFinal()
        for text in ["Please merge this pool", "Please merge this pool request", raw] {
            correction.preview(text)
            try? await Task.sleep(for: .milliseconds(30))
        }
        let requests = await service.requests
        XCTAssertEqual(requests, ["Please merge this", "Please merge this pool"])
        correction.cancel()
    }
}
