import Foundation
import XCTest
@testable import SpeakCore

final class CorrectionURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class TranscriptCorrectorTests: XCTestCase {
    func testRequestUsesFastPinnedModelAndPredictedOutputWithoutStorage() async throws {
        let original = "Please merge this pool request into main."
        let expected = "Please merge this pull request into main."
        CorrectionURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try self.body(of: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "gpt-4.1-nano-2025-04-14")
            XCTAssertEqual(json["store"] as? Bool, false)
            XCTAssertEqual((json["prediction"] as? [String: String])?["content"], original)
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages.first?["role"], "developer")
            let input = try XCTUnwrap(messages.last?["content"]?.data(using: .utf8))
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
            XCTAssertEqual(fields["transcript"] as? String, original)
            XCTAssertEqual(fields["application"] as? String, "Editor")
            XCTAssertEqual(fields["vocabulary"] as? [String], ["Supabase"])
            return (200, try self.response(text: expected))
        }
        let corrector = makeCorrector()
        let result = try await corrector.correct(original, context: CorrectionContext(language: "en", keywords: ["Supabase"], application: "Editor"))
        XCTAssertEqual(result, expected)
    }

    func testIncompleteResponseIsRejected() async {
        CorrectionURLProtocol.handler = { _ in (200, try self.response(text: "Partial", reason: "length")) }
        do {
            _ = try await makeCorrector().correct("Please merge this pool request.", context: CorrectionContext())
            XCTFail("Truncated corrections must not be used")
        } catch { XCTAssertTrue(error is DictationError) }
    }

    func testAPIErrorDoesNotExposeItsResponseBody() async {
        CorrectionURLProtocol.handler = { _ in (401, Data("private error details".utf8)) }
        do {
            _ = try await makeCorrector().correct("Please merge this pool request.", context: CorrectionContext())
            XCTFail("API failures must be reported to the fallback path")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Smart correction is unavailable.")
        }
    }

    private func body(of request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private func makeCorrector() -> OpenAITranscriptCorrector {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CorrectionURLProtocol.self]
        return OpenAITranscriptCorrector(apiKey: "test-key", session: URLSession(configuration: configuration))
    }

    private func response(text: String, reason: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text], "finish_reason": reason]]])
    }
}
