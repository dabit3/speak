import XCTest
@testable import SpeakCore

final class CorrectionLearnerTests: XCTestCase {
    private let dictionary: Set<String> = [
        "the", "to", "and", "it", "we", "for", "go", "so", "then", "send", "check", "path", "pod", "big", "large", "one",
        "users", "nadir", "john", "apple", "other", "fallback", "callback", "super", "base", "post", "update", "ship",
        "Nader", "Nadia", "Vercel", "Paris", "OAuth", "GitHub"
    ]

    private func learn(_ original: String, _ edited: String) -> [LearnedWord] {
        CorrectionLearner.fixes(from: original, to: edited) { self.dictionary.contains($0) }
    }

    func testLearnsAProductNameAndTheWayItWasMisheard() {
        XCTAssertEqual(
            learn("Superbase handles authentication, storage, and the database.", "Supabase handles authentication, storage, and the database."),
            [LearnedWord(term: "Supabase", replaces: ["Superbase"])]
        )
        XCTAssertEqual(learn("The deploy to Versel failed.", "The deploy to Vercel failed."), [LearnedWord(term: "Vercel", replaces: ["Versel"])])
        XCTAssertEqual(learn("The deploy to Versal failed.", "The deploy to Vercel failed."), [LearnedWord(term: "Vercel", replaces: ["Versal"])])
    }

    func testNeverReplacesARealWordOrName() {
        XCTAssertEqual(learn("Nadir wrote a blog post.", "Nader wrote a blog post."), [LearnedWord(term: "Nader")])
        XCTAssertEqual(learn("Thanks, Nadia.", "Thanks, Nader."), [LearnedWord(term: "Nader")])
    }

    func testLearnsATechnicalTermEvenWhenItSoundsDifferent() {
        XCTAssertEqual(learn("The other fallback returns a 401 error.", "The OAuth callback returns a 401 error."), [LearnedWord(term: "OAuth")])
    }

    func testLearnsCapitalization() {
        XCTAssertEqual(learn("I pushed it to github today.", "I pushed it to GitHub today."), [LearnedWord(term: "GitHub", replaces: ["github"])])
        XCTAssertEqual(learn("I talked to nader today.", "I talked to Nader today."), [LearnedWord(term: "Nader")])
    }

    func testLearnsAPhraseThatWasHeardAsSeveralWords() {
        XCTAssertEqual(learn("We use super base for auth.", "We use Supabase for auth."), [LearnedWord(term: "Supabase")])
        XCTAssertEqual(learn("We moved to post gres.", "We moved to Postgres."), [LearnedWord(term: "Postgres", replaces: ["post gres"])])
    }

    func testIgnoresRewordingAndOrdinaryWordFixes() {
        XCTAssertEqual(learn("Send it to John.", "Send it to Sarah."), [])
        XCTAssertEqual(learn("We should ship it.", "Ship it Friday."), [])
        XCTAssertEqual(learn("Check the path.", "Check the pod."), [])
        XCTAssertEqual(learn("The big one.", "The large one."), [])
        XCTAssertEqual(learn("so we go", "So we go"), [])
        XCTAssertEqual(learn("then we go", "THEN we go"), [])
    }

    func testIgnoresInsertionsDeletionsAndRewrites() {
        XCTAssertEqual(learn("Thanks for the update.", "Thanks Sarah for the update."), [])
        XCTAssertEqual(learn("Thanks for the update.", "Thanks."), [])
        XCTAssertEqual(learn("Superbase handles our login and storage.", "Our new Supabase project stores everything."), [])
    }

    func testIgnoresEmailsNumbersAndUnspacedScripts() {
        XCTAssertEqual(learn("My email is nadir@example.com.", "My email is nader@example.com."), [])
        XCTAssertEqual(learn("Meet at 3.", "Meet at 4."), [])
        XCTAssertEqual(learn("今日はスーパーベースを使う", "今日はスパベースを使う"), [])
    }

    func testKeepsOnlyOneCopyOfARepeatedFix() {
        XCTAssertEqual(learn("Superbase and Superbase again.", "Supabase and Supabase again."), [LearnedWord(term: "Supabase", replaces: ["Superbase"])])
    }
}
