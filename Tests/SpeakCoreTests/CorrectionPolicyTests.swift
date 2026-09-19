import XCTest
@testable import SpeakCore

final class CorrectionPolicyTests: XCTestCase {
    func testAcceptsSmallContextualCorrection() {
        XCTAssertEqual(CorrectionPolicy.accept("Please merge this pool request into main.", candidate: "Please merge this pull request into main."), "Please merge this pull request into main.")
    }

    func testRejectsEmptyAndExplanatoryResponses() {
        XCTAssertNil(CorrectionPolicy.accept("Please merge this pool request.", candidate: ""))
        XCTAssertNil(CorrectionPolicy.accept("Please merge this pool request.", candidate: "Here is the corrected transcript: Please merge this pull request."))
    }

    func testRejectsChangedAndAddedNumbers() {
        XCTAssertNil(CorrectionPolicy.accept("Send 12 items to the office.", candidate: "Send 20 items to the office."))
        XCTAssertNil(CorrectionPolicy.accept("Send the items to the office.", candidate: "Send 20 items to the office."))
        XCTAssertNil(CorrectionPolicy.accept("Send two items to the office.", candidate: "Send three items to the office."))
    }

    func testRejectsChangedNegation() {
        XCTAssertNil(CorrectionPolicy.accept("Please do not merge this request.", candidate: "Please do merge this request."))
        XCTAssertNil(CorrectionPolicy.accept("We can’t deploy the service today.", candidate: "We can deploy the service today."))
    }

    func testPreservesNamesAndVocabulary() {
        XCTAssertNil(CorrectionPolicy.accept("Please send this to Nader today.", candidate: "Please send this to Nathan today."))
        XCTAssertNil(CorrectionPolicy.accept("Please use supabase for this project.", candidate: "Please use firebase for this project.", keywords: ["supabase"]))
    }

    func testRejectsChangedLeadingNamesAndDates() {
        XCTAssertNil(CorrectionPolicy.accept("Nader will review this tomorrow.", candidate: "Nathan will review this tomorrow."))
        XCTAssertNil(CorrectionPolicy.accept("Please meet me tomorrow morning.", candidate: "Please meet me today morning."))
        XCTAssertNil(CorrectionPolicy.accept("Please use the SQL database.", candidate: "Please use the sql database."))
    }

    func testRejectsAnAssistantPreface() {
        XCTAssertNil(CorrectionPolicy.accept("Please merge this pool request.", candidate: "Sure, please merge this pull request."))
    }

    func testVocabularyDoesNotMatchInsideAnotherWord() {
        XCTAssertEqual(CorrectionPolicy.accept("Please said hello to everyone.", candidate: "Please say hello to everyone.", keywords: ["AI"]), "Please say hello to everyone.")
    }

    func testPreservesURLsCodeAndQuotes() {
        XCTAssertNil(CorrectionPolicy.accept("Please visit https://example.com/a today.", candidate: "Please visit https://example.com/b today."))
        XCTAssertFalse(CorrectionPolicy.isEligible("Please run `git push` after this."))
        XCTAssertNil(CorrectionPolicy.accept("She said \"pool request\" to me.", candidate: "She said \"pull request\" to me."))
    }

    func testRejectsBroadRewriteAndTranslation() {
        XCTAssertNil(CorrectionPolicy.accept("Please merge this pool request into main.", candidate: "You need to create a new branch and send it for review."))
        XCTAssertNil(CorrectionPolicy.accept("Please merge this pool request into main.", candidate: "Veuillez fusionner cette demande dans la branche principale."))
    }

    func testLimitsInputAndLeavesVeryShortSpeechAlone() {
        XCTAssertFalse(CorrectionPolicy.isEligible("Hello"))
        XCTAssertFalse(CorrectionPolicy.isEligible(String(repeating: "word ", count: 1000)))
        XCTAssertTrue(CorrectionPolicy.isEligible("Please merge this pool request."))
    }

    func testAllowsUnicodeTextAndUnchangedOutput() {
        let text = "Bonjour, pouvez-vous relire ce message ?"
        XCTAssertEqual(CorrectionPolicy.accept(text, candidate: text), text)
        XCTAssertTrue(CorrectionPolicy.isEligible("明天上午我们一起去公园散步。"))
    }
}
