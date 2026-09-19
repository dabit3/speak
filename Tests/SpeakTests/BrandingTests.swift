import Foundation
import XCTest
import SpeakCore
@testable import Speak

final class BrandingTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testAppBundleUsesSpeakIdentity() throws {
        let info = try bundleInfo()
        XCTAssertEqual(info["CFBundleName"] as? String, "Speak")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Speak")
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "Speak")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "local.speak.dictation")
        XCTAssertTrue((info["NSMicrophoneUsageDescription"] as? String)?.hasPrefix("Speak ") == true)
    }

    func testInterfaceUsesOnlySansSerifFontDesigns() throws {
        let directory = root.appendingPathComponent("Sources/Speak")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("design: .serif"), file.lastPathComponent)
            XCTAssertFalse(source.contains("design: .monospaced"), file.lastPathComponent)
        }
    }

    func testDashboardOmitsTheEyebrowTagline() throws {
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Speak/MainView.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("A LITTLE LESS TYPING"))
        XCTAssertFalse(source.contains("YOUR VOICE, WITHOUT THE FRICTION"))
    }

    func testKeychainNamespaceMatchesAppIdentity() throws {
        let identifier = try XCTUnwrap(bundleInfo()["CFBundleIdentifier"] as? String)
        let preferences = try String(contentsOf: root.appendingPathComponent("Sources/Speak/Preferences.swift"), encoding: .utf8)
        XCTAssertTrue(preferences.contains("kSecAttrService as String: \"\(identifier)\""))
    }

    func testBuildAndInstallerUseUnindexedAppArtifacts() throws {
        let build = try String(contentsOf: root.appendingPathComponent("scripts/build.sh"), encoding: .utf8)
        let packaging = try String(contentsOf: root.appendingPathComponent("scripts/package-dmg.sh"), encoding: .utf8)
        XCTAssertTrue(build.contains("build/artifacts.noindex/Speak.app"))
        XCTAssertTrue(packaging.contains("build/artifacts.noindex/Speak.app"))
        XCTAssertTrue(build.contains("Resources/Speak.entitlements"))
        XCTAssertTrue(packaging.contains("$ROOT/.build/dmg.XXXXXX"))
        XCTAssertTrue(packaging.contains("-volname Speak"))
        XCTAssertTrue(packaging.contains("-nospotlight"))
        XCTAssertTrue(packaging.contains("Speak-$VERSION-$ARCH.dmg"))
    }

    func testDictationMarkUsesClosedShapes() {
        let path = SpeakLogo.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        var contours = 0
        var closed = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { contours += 1 }
            if element.pointee.type == .closeSubpath { closed += 1 }
        }
        XCTAssertGreaterThan(contours, 1)
        XCTAssertEqual(closed, contours)
        XCTAssertFalse(path.isEmpty)
    }

    func testDictationMarkContainsMicrophoneAndTextCursor() {
        let path = SpeakLogo.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(path.contains(CGPoint(x: 32, y: 28)))
        XCTAssertTrue(path.contains(CGPoint(x: 32, y: 75)))
        XCTAssertTrue(path.contains(CGPoint(x: 81, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 65, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 32, y: 65)))
    }

    func testDictationMarkFitsSmallAndLargeSizes() {
        for size: CGFloat in [16, 18, 25, 512, 1024] {
            let rect = CGRect(x: 7, y: 11, width: size, height: size)
            let bounds = SpeakLogo.path(in: rect).boundingBoxOfPath
            XCTAssertTrue(rect.contains(bounds))
            XCTAssertGreaterThan(bounds.width, size * 0.6)
            XCTAssertGreaterThan(bounds.height, size * 0.8)
        }
        XCTAssertTrue(SpeakLogo.path(in: .zero).isEmpty)
    }

    func testDictationMarkKeepsItsShapeInAWideFrame() {
        let square = SpeakLogo.path(in: CGRect(x: 0, y: 0, width: 20, height: 20)).boundingBoxOfPath
        let wide = SpeakLogo.path(in: CGRect(x: 0, y: 0, width: 40, height: 20)).boundingBoxOfPath
        XCTAssertEqual(square.size, wide.size)
        XCTAssertEqual(wide.minX - square.minX, 10, accuracy: 0.001)
    }

    @MainActor func testMenuBarUsesATemplateOfTheDictationMark() async {
        let image = BrandMark.menuBarImage()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, CGSize(width: 18, height: 18))
        XCTAssertEqual(image.accessibilityDescription, "Speak dictation")
        XCTAssertNotNil(image.tiffRepresentation)
    }

    private func bundleInfo() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
