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

    func testProtectsNumericValuesNotJustTheirDigits() {
        let cases = [
            ("The cost is $1.50 per item.", "The cost is $150 per item."),
            ("The temperature is -5 degrees today.", "The temperature is 5 degrees today."),
            ("The rate is 1.5% per year.", "The rate is 15% per year."),
            ("Send 1 box and 23 labels.", "Send 12 boxes and 3 labels."),
            ("The meeting starts at 9 AM tomorrow.", "The meeting starts at 9 PM tomorrow."),
            ("The budget is 5 million dollars.", "The budget is 5 billion dollars."),
            ("The price is €50 per item.", "The price is $50 per item."),
            ("The rate is .5 percent per year.", "The rate is 5 percent per year."),
            ("The ratio is .5 today.", "The ratio is 5 today."),
            ("The package weighs 5 kilograms today.", "The package weighs 5 grams today."),
            ("The delivery takes 5 days total.", "The delivery takes 5 weeks total."),
            ("The package weighs 5kg today.", "The package weighs 5g today."),
            ("The delay is 5ms today.", "The delay is 5s today.")
        ]
        for (original, candidate) in cases {
            XCTAssertNil(CorrectionPolicy.accept(original, candidate: candidate), "\(original) -> \(candidate)")
        }
    }

    func testSelfCorrectionsCannotAssembleANewNumberFromOldDigits() {
        XCTAssertNil(CorrectionPolicy.accept("Use 15, no wait, 20 units.", candidate: "Use 12 units."))
        XCTAssertNil(CorrectionPolicy.accept("Use 25, no wait, 15 units.", candidate: "Use 5 units."))
        XCTAssertEqual(CorrectionPolicy.accept("Use 15, no wait, 20 units.", candidate: "Use 20 units."), "Use 20 units.")
    }

    func testSelfCorrectionsCannotSwapQuantitiesBetweenSubjects() {
        let original = "The shipment should contain exactly 15, no wait, 20 units for the first box and 3 units for the second box."
        let swapped = "The shipment should contain exactly 3 units for the first box and 20 units for the second box."
        let corrected = "The shipment should contain exactly 20 units for the first box and 3 units for the second box."
        XCTAssertNil(CorrectionPolicy.accept(original, candidate: swapped))
        XCTAssertEqual(CorrectionPolicy.accept(original, candidate: corrected), corrected)
    }

    func testStillAcceptsEquivalentMoneyPercentAndSignFormatting() {
        let cases = [
            ("The cost is $1,500 per item.", "The cost is 1500 dollars per item."),
            ("The discount is fifty percent today.", "The discount is 50% today."),
            ("The temperature is −5 degrees today.", "The temperature is -5 degrees today."),
            ("The package weighs 5 kilograms today.", "The package weighs 5 kg today."),
            ("The delivery takes five minutes today.", "The delivery takes 5 min today."),
            ("The ratio is .5 today.", "The ratio is 0.5 today."),
            ("The price is €50 per item.", "The price is 50 euros per item.")
        ]
        for (original, candidate) in cases {
            XCTAssertEqual(CorrectionPolicy.accept(original, candidate: candidate), candidate)
        }
    }

    func testQuotedRevisionCommandsDoNotRelaxCorrectionSafety() {
        let original = "Keep 15 items and write \"scratch that\" below."
        XCTAssertFalse(CorrectionPolicy.revisesItself(original))
        XCTAssertFalse(CorrectionPolicy.revisesItself("The example says “no wait” in the notes."))
        XCTAssertNil(CorrectionPolicy.accept(original, candidate: "Keep 5 items and write \"scratch that\" below."))
        XCTAssertTrue(CorrectionPolicy.revisesItself("Keep 15, no wait, 20 items and write \"scratch that\" below."))
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

    func testAcceptsTimeSuffixStyle() {
        XCTAssertEqual(CorrectionPolicy.accept("Let's meet at three, no wait, 4:30 p.m. on Tuesday.", candidate: "Let's meet at 4:30 PM on Tuesday."), "Let's meet at 4:30 PM on Tuesday.")
        XCTAssertEqual(CorrectionPolicy.accept("The demo starts at 3:30 p.m. on Thursday.", candidate: "The demo starts at 3:30 PM on Thursday."), "The demo starts at 3:30 PM on Thursday.")
        XCTAssertNil(CorrectionPolicy.accept("The demo starts at 3:30 p.m. on Thursday.", candidate: "The demo starts at 4:30 PM on Thursday."))
    }

    func testFixesMisheardSentenceStartsButKeepsLeadingNames() {
        let original = "Ease add tailwind and GraphQL to the project, then restart the dev server."
        let fixed = "Please add Tailwind and GraphQL to the project, then restart the dev server."
        XCTAssertEqual(CorrectionPolicy.accept(original, candidate: fixed), fixed)
        XCTAssertNil(CorrectionPolicy.accept("Sarah said the build is green today.", candidate: "Share said the build is green today."))
        XCTAssertNil(CorrectionPolicy.accept("Microsoft announced the new model today.", candidate: "My soft announced the new model today."))
    }

    func testAllowsRespelledProductNamesButNotReplacedNames() {
        let original = "The deploy to Versel failed because the variable wasn't set."
        let fixed = "The deploy to Vercel failed because the variable wasn't set."
        XCTAssertEqual(CorrectionPolicy.accept(original, candidate: fixed), fixed)
        XCTAssertEqual(CorrectionPolicy.accept("We store files in Superbase for now.", candidate: "We store files in Supabase for now."), "We store files in Supabase for now.")
        XCTAssertNil(CorrectionPolicy.accept("Please ask Sarah about the release.", candidate: "Please ask Sara about the release."))
        XCTAssertNil(CorrectionPolicy.accept("Please ask Jon about the release.", candidate: "Please ask John about the release."))
        XCTAssertNil(CorrectionPolicy.accept("Please send it to Priya today.", candidate: "Please send it to Maria today."))
        XCTAssertNil(CorrectionPolicy.accept("Please ask Martin to review the release.", candidate: "Please ask Martina to review the release."))
        XCTAssertNil(CorrectionPolicy.accept("Please send this to Nader today.", candidate: "Please send this to Nadir today."))
        XCTAssertEqual(CorrectionPolicy.accept("Please send this to Nadir today.", candidate: "Please send this to Nader today.", keywords: ["Nader"]), "Please send this to Nader today.")
    }

    func testVocabularySpellingCanReplaceALiteral() {
        XCTAssertNil(CorrectionPolicy.accept("Please build it for IOS today.", candidate: "Please build it for iOS today."))
        XCTAssertEqual(CorrectionPolicy.accept("Please build it for IOS today.", candidate: "Please build it for iOS today.", keywords: ["iOS"]), "Please build it for iOS today.")
        XCTAssertEqual(CorrectionPolicy.accept("The deploy to Versel failed again today.", candidate: "The deploy to Vercel failed again today.", keywords: ["Vercel"]), "The deploy to Vercel failed again today.")
    }

    func testExplicitLineBreaksSurviveCorrection() {
        let original = "Hello there,\n\nPlease merge this pool request."
        let fixed = "Hello there,\n\nPlease merge this pull request."
        XCTAssertEqual(CorrectionPolicy.accept(original, candidate: fixed), fixed)
        XCTAssertNil(CorrectionPolicy.accept(original, candidate: "Hello there, please merge this pull request."))
        XCTAssertNil(CorrectionPolicy.accept(original, candidate: "Hello there,\nPlease merge this pull request."))
    }

    func testVocabularyTermsAreNotMistakenForRevisionCues() {
        let original = "We use Scratch That every day."
        XCTAssertFalse(CorrectionPolicy.revisesItself(original, keywords: ["Scratch That"]))
        XCTAssertNil(CorrectionPolicy.accept(original, candidate: "We use it every day.", keywords: ["Scratch That"]))
    }

    func testDoesNotConfuseWeightOrAnimalsWithMoney() {
        XCTAssertNil(CorrectionPolicy.accept("The package weighs 5 pounds today.", candidate: "The package weighs £5 today."))
        XCTAssertNil(CorrectionPolicy.accept("We saw 5 bucks in the field.", candidate: "We saw $5 in the field."))
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
