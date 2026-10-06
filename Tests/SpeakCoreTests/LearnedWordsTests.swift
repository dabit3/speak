import XCTest
@testable import SpeakCore

final class LearnedWordsTests: XCTestCase {
    func testFixesTheSameMistakeInNewText() {
        let learned = LearnedWords([LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        XCTAssertEqual(learned.apply(to: "superbase and Superbase's dashboard"), "Supabase and Supabase's dashboard")
    }

    func testReplacesOnlyWholeWords() {
        let learned = LearnedWords([LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        XCTAssertEqual(learned.apply(to: "Superbases and MySuperbase stay."), "Superbases and MySuperbase stay.")
    }

    func testKeepsSentenceCapitalizationAndMatchesPhrases() {
        let learned = LearnedWords([
            LearnedWord(term: "users", replaces: ["reviewsers"], isHint: false),
            LearnedWord(term: "Postgres", replaces: ["post gres"])
        ])
        XCTAssertEqual(learned.apply(to: "Reviewsers moved to post  gres."), "Users moved to Postgres.")
    }

    func testNeverRewritesAddressesCodeOrExactQuotations() {
        let learned = LearnedWords([LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        for literal in [
            "https://superbase.com/docs", "superbase@example.com", "superbase.dev", "src/superbase.swift",
            "my_superbase_key", "`Superbase`", "\"Superbase\"", "“Superbase”", "```\nSuperbase\n```",
            #""say \"Superbase\"""#
        ] {
            XCTAssertEqual(learned.apply(to: "Superbase mentions \(literal)."), "Supabase mentions \(literal).", literal)
        }
    }

    func testLearnedPhrasesDoNotCrossLinesOrParagraphs() {
        let learned = LearnedWords([LearnedWord(term: "Postgres", replaces: ["post gres"])])
        XCTAssertEqual(learned.apply(to: "post\ngres and post\n\ngres"), "post\ngres and post\n\ngres")
        XCTAssertEqual(learned.apply(to: "post\tgres and post  gres"), "Postgres and Postgres")
    }

    func testMergesEveryWayAWordWasMisheard() {
        var learned = LearnedWords()
        learned.learn([LearnedWord(term: "Vercel", replaces: ["Versel"])])
        learned.learn([LearnedWord(term: "Nader")])
        learned.learn([LearnedWord(term: "Vercel", replaces: ["Versal"])])
        XCTAssertEqual(learned.words, [LearnedWord(term: "Vercel", replaces: ["Versel", "Versal"]), LearnedWord(term: "Nader")])
        XCTAssertEqual(learned.apply(to: "Versel, Versal, and Vercel"), "Vercel, Vercel, and Vercel")
    }

    func testChangingAWordBackNeverCreatesALoop() {
        var learned = LearnedWords()
        learned.learn([LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        learned.learn([LearnedWord(term: "Superbase", replaces: ["Supabase"])])
        XCTAssertEqual(learned.words, [LearnedWord(term: "Superbase", replaces: ["Supabase"])])
        XCTAssertEqual(learned.apply(to: "Supabase and Superbase"), "Superbase and Superbase")
    }

    func testHintsListNewestFirstAndSkipReplacementOnlyWords() {
        var learned = LearnedWords()
        learned.learn([LearnedWord(term: "Supabase", replaces: ["Superbase"])])
        learned.learn([LearnedWord(term: "users", replaces: ["reviewsers"], isHint: false)])
        learned.learn([LearnedWord(term: "OAuth")])
        XCTAssertEqual(learned.hints, ["OAuth", "Supabase"])
        learned.remove(LearnedWord(term: "OAuth"))
        XCTAssertEqual(learned.hints, ["Supabase"])
    }

    func testKeepsTheNewestWordsWhenFull() {
        var learned = LearnedWords()
        for index in 0..<(LearnedWords.capacity + 50) { learned.learn([LearnedWord(term: "Term\(index)")]) }
        XCTAssertEqual(learned.words.count, LearnedWords.capacity)
        XCTAssertEqual(learned.words.first?.term, "Term\(LearnedWords.capacity + 49)")
        XCTAssertFalse(learned.hints.contains("Term0"))
    }

    func testSurvivesARoundTripThroughJSON() throws {
        let learned = LearnedWords([LearnedWord(term: "Supabase", replaces: ["Superbase"]), LearnedWord(term: "users", replaces: ["reviewsers"], isHint: false)])
        let restored = try JSONDecoder().decode(LearnedWords.self, from: JSONEncoder().encode(learned))
        XCTAssertEqual(restored, learned)
    }
}
