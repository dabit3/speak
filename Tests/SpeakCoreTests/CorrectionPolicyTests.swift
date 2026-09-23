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

    func testAcceptsNumberAndPunctuationFormatting() {
        XCTAssertEqual(CorrectionPolicy.accept("We have twenty five users and two options.", candidate: "We have 25 users and 2 options."), "We have 25 users and 2 options.")
        XCTAssertEqual(CorrectionPolicy.accept("Hey Sam comma can you check the logs question mark", candidate: "Hey Sam, can you check the logs?"), "Hey Sam, can you check the logs?")
        XCTAssertEqual(CorrectionPolicy.accept("Meet me at 3 30 PM on Friday.", candidate: "Meet me at 3:30 PM on Friday."), "Meet me at 3:30 PM on Friday.")
        XCTAssertEqual(CorrectionPolicy.accept("I do not think we can ship today.", candidate: "I don't think we can ship today."), "I don't think we can ship today.")
    }

    func testAcceptsSpokenSelfCorrections() {
        XCTAssertEqual(CorrectionPolicy.accept("Let's meet at 3, no wait, 4:30 PM on Tuesday.", candidate: "Let's meet at 4:30 PM on Tuesday."), "Let's meet at 4:30 PM on Tuesday.")
        XCTAssertEqual(CorrectionPolicy.accept("Send the invoice to John, I mean Sarah.", candidate: "Send the invoice to Sarah."), "Send the invoice to Sarah.")
        XCTAssertEqual(CorrectionPolicy.accept("The deploy failed. Scratch that. The deploy is still running.", candidate: "The deploy is still running."), "The deploy is still running.")
        XCTAssertEqual(CorrectionPolicy.accept("Ship it Monday, actually Tuesday.", candidate: "Ship it Tuesday."), "Ship it Tuesday.")
    }

    func testSelfCorrectionsCannotIntroduceNewValues() {
        XCTAssertNil(CorrectionPolicy.accept("Let's meet at 3, no wait, 4 PM.", candidate: "Let's meet at 5 PM."))
        XCTAssertNil(CorrectionPolicy.accept("Send the invoice to John, I mean Sarah.", candidate: "Send the invoice to Nathan."))
        XCTAssertNil(CorrectionPolicy.accept("Ship it today, no wait, tomorrow.", candidate: "Don't ship it tomorrow."))
        XCTAssertNil(CorrectionPolicy.accept("Ship it today, no wait, tomorrow.", candidate: "Ship it tomorrow and write a summary of the release notes for everyone."))
    }

    func testRemovalWithoutACueIsStillRejected() {
        XCTAssertNil(CorrectionPolicy.accept("Deploy 3 services and 4 workers today.", candidate: "Deploy 4 workers today."))
        XCTAssertNil(CorrectionPolicy.accept("Send it to John and Sarah today.", candidate: "Send it to Sarah today."))
        XCTAssertNil(CorrectionPolicy.accept("Please review the pull request and merge it into main after the tests pass.", candidate: "Please merge it."))
    }

    func testDetectsSelfCorrectionCues() {
        for text in ["Let's meet at 3, no wait, 4.", "Send it to John, I mean Sarah.", "Use Postgres, actually SQLite.", "Delete the file. Scratch that.", "Book the 9 AM flight, sorry, the 10 AM flight.", "Tuesday or rather Wednesday."] {
            XCTAssertTrue(CorrectionPolicy.revisesItself(text), text)
        }
        for text in ["I mean, it's fine.", "There is no way this works.", "Sorry for the delay.", "Hi, sorry for the delay.", "Actually I agree.", "Wait for the build."] {
            XCTAssertFalse(CorrectionPolicy.revisesItself(text), text)
        }
    }

    func testAllowsUnicodeTextAndUnchangedOutput() {
        let text = "Bonjour, pouvez-vous relire ce message ?"
        XCTAssertEqual(CorrectionPolicy.accept(text, candidate: text), text)
        XCTAssertTrue(CorrectionPolicy.isEligible("明天上午我们一起去公园散步。"))
    }
}
