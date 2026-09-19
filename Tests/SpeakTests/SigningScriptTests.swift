import Foundation
import XCTest

final class SigningScriptTests: XCTestCase {
    private let first = String(repeating: "A", count: 40)
    private let second = String(repeating: "B", count: 40)
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testSelectsTheOnlyDeveloperIDCertificate() throws {
        let output = "  1) \(first) \"Apple Development: Example\"\n  2) \(second) \"Developer ID Application: Example\"\n     2 valid identities found"
        let result = try resolve(output)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, second + "\n")
    }

    func testMissingCertificateDoesNotSilentlyUseTemporarySigning() throws {
        let result = try resolve("     0 valid identities found")
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.isEmpty)
        XCTAssertTrue(result.error.contains("No valid Developer ID"))
    }

    func testMultipleCertificatesRequireAnExplicitSelection() throws {
        let output = "  1) \(first) \"Developer ID Application: First\"\n  2) \(second) \"Developer ID Application: Second\""
        let result = try resolve(output)
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.isEmpty)
        XCTAssertTrue(result.error.contains("Multiple Developer ID"))
    }

    func testExplicitCertificateIsRespected() throws {
        let result = try resolve("", override: "Developer ID Application: Chosen", securityStatus: 7)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "Developer ID Application: Chosen\n")
    }

    func testTemporarySigningRequiresExplicitOptInAndWarns() throws {
        let result = try resolve("", override: "-", securityStatus: 7)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "-\n")
        XCTAssertTrue(result.error.contains("Accessibility approval"))
    }

    func testKeychainLookupFailureDoesNotFallBack() throws {
        let result = try resolve("", securityStatus: 7)
        XCTAssertEqual(result.status, 7)
        XCTAssertTrue(result.output.isEmpty)
    }

    private func resolve(_ identities: String, override: String? = nil, securityStatus: Int = 0) throws -> (status: Int32, output: String, error: String) {
        let directory = root.appendingPathComponent(".build/signing-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let command = directory.appendingPathComponent("security")
        try "#!/bin/bash\nprintf '%s\\n' \"$TEST_IDENTITIES\"\nexit \(securityStatus)\n".write(to: command, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/signing-identity.sh").path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directory.path + ":/usr/bin:/bin"
        environment["TEST_IDENTITIES"] = identities
        environment["CODE_SIGN_IDENTITY"] = override
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
    }
}
