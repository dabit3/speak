import XCTest
@testable import SpeakCore

final class DictationFormatterTests: XCTestCase {
    private func assertFormats(_ cases: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in cases {
            XCTAssertEqual(DictationFormatter.format(input), expected, "Input: \(input)", file: file, line: line)
        }
    }

    func testWritesLargerAndCompoundNumbersAsDigits() {
        assertFormats([
            ("We have twenty five users.", "We have 25 users."),
            ("I need twelve apples", "I need 12 apples"),
            ("It has one hundred and twenty three stars.", "It has 123 stars."),
            ("About five hundred people signed up.", "About 500 people signed up."),
            ("We raised fifty thousand this year.", "We raised 50,000 this year."),
            ("The city has two million residents.", "The city has 2 million residents."),
            ("Invite forty-two guests.", "Invite 42 guests."),
            ("We need a hundred and fifty chairs.", "We need 150 chairs."),
            ("Ten minutes later it worked.", "10 minutes later it worked.")
        ])
    }

    func testKeepsSmallCountsAndIdiomsAsWords() {
        assertFormats([
            ("I have two options.", "I have two options."),
            ("One day we will ship it.", "One day we will ship it."),
            ("No one knows the answer.", "No one knows the answer."),
            ("At one point we tried that.", "At one point we tried that."),
            ("Give me one minute.", "Give me one minute."),
            ("Wait a second.", "Wait a second."),
            ("First, open the file.", "First, open the file."),
            ("I'm a hundred times better.", "I'm a hundred times better."),
            ("Hundreds of people came.", "Hundreds of people came."),
            ("It was the nineteen nineties.", "It was the nineteen nineties."),
            ("We love Fifty Shades.", "We love Fifty Shades.")
        ])
    }

    func testUsesDigitsForMeasuresLabelsAndRanges() {
        assertFormats([
            ("It takes five minutes.", "It takes 5 minutes."),
            ("Wait two or three days.", "Wait 2 or 3 days."),
            ("Go to step three.", "Go to step 3."),
            ("Use version two point one.", "Use version 2.1."),
            ("Pi is about three point one four.", "Pi is about 3.14."),
            ("It weighs negative five degrees.", "It weighs -5 degrees.")
        ])
    }

    func testFormatsMoneyAndPercentages() {
        assertFormats([
            ("It costs five dollars.", "It costs $5."),
            ("It costs twenty five dollars and fifty cents.", "It costs $25.50."),
            ("The budget is two thousand dollars.", "The budget is $2,000."),
            ("They raised two point five million dollars.", "They raised $2.5 million."),
            ("I'm a hundred percent sure.", "I'm 100% sure."),
            ("Growth was fifty percent.", "Growth was 50%."),
            ("Growth was 12 percent.", "Growth was 12%."),
            ("Tip fifty cents.", "Tip 50 cents.")
        ])
    }

    func testFormatsTimesDatesYearsAndCodes() {
        assertFormats([
            ("Let's meet at three thirty pm.", "Let's meet at 3:30 PM."),
            ("Call me at nine am tomorrow.", "Call me at 9 AM tomorrow."),
            ("The train leaves at six oh five p.m.", "The train leaves at 6:05 p.m."),
            ("Let's meet at three thirty.", "Let's meet at 3:30."),
            ("It's ten o'clock.", "It's 10 o'clock."),
            ("Eleven thirty works for me.", "11:30 works for me."),
            ("I have two thirty minute meetings.", "I have two 30 minute meetings."),
            ("It returns a four oh four error.", "It returns a 404 error."),
            ("Which one am I?", "Which one am I?"),
            ("The launch is March fifteenth.", "The launch is March 15."),
            ("The launch is March fifteenth, twenty twenty six.", "The launch is March 15, 2026."),
            ("Due on the twenty first of May.", "Due on the 21st of May."),
            ("See you on the first of June.", "See you on the 1st of June."),
            ("It was built in nineteen eighty four.", "It was built in 1984."),
            ("It shipped in two thousand and five.", "It shipped in 2005."),
            ("The twenty first century", "The 21st century"),
            ("May five people join?", "May five people join?"),
            ("My code is four five six seven.", "My code is 4567.")
        ])
    }

    func testConvertsSpokenPunctuation() {
        assertFormats([
            ("Hey Sam comma can you check the logs question mark", "Hey Sam, can you check the logs?"),
            ("I'm done period See you soon", "I'm done. See you soon"),
            ("That's amazing exclamation point", "That's amazing!"),
            ("What time question mark", "What time?"),
            ("The deadline is Friday comma March twenty first", "The deadline is Friday, March 21"),
            ("Note colon bring snacks", "Note: bring snacks"),
            ("Hello, comma, how are you? Question mark.", "Hello, how are you?"),
            ("First item semicolon second item", "First item; second item"),
            ("He said open quote hello close quote.", "He said \"hello\"."),
            ("Add the tests open paren later close paren", "Add the tests (later)"),
            ("Dear Sarah, new line thanks for the update.", "Dear Sarah,\nThanks for the update."),
            ("First point new paragraph second point", "First point\n\nSecond point"),
            ("End with a new line", "End with a new line")
        ])
    }

    func testKeepsPunctuationWordsThatArePartOfTheSentence() {
        assertFormats([
            ("The trial period ends Friday.", "The trial period ends Friday."),
            ("A period of growth followed.", "A period of growth followed."),
            ("I love the Oxford comma.", "I love the Oxford comma."),
            ("Use a comma separated list.", "Use a comma separated list."),
            ("It was the Jurassic period.", "It was the Jurassic period."),
            ("Put a question mark there.", "Put a question mark there."),
            ("We added a new line of products.", "We added a new line of products.")
        ])
    }

    func testRemovesFillersAndStutters() {
        assertFormats([
            ("Um, so I think we should, uh, ship it.", "So I think we should ship it."),
            ("So, um, I think it works.", "So, I think it works."),
            ("I I think the the build passed.", "I think the build passed."),
            ("It works, um.", "It works."),
            ("Um.", ""),
            ("Take the ER exit.", "Take the ER exit."),
            ("That that is fine.", "That that is fine.")
        ])
    }

    func testFormatsSpokenEmailAddressesAndDomains() {
        assertFormats([
            ("Email me at nader at example dot com.", "Email me at nader@example.com."),
            ("Reach John dot Smith at mail dot example dot co dot uk", "Reach john.smith@mail.example.co.uk"),
            ("I work at google dot com", "I work at google.com"),
            ("Visit speak dot app for details.", "Visit speak.app for details."),
            ("My email is nadir@example dot com, so reach out.", "My email is nadir@example.com, so reach out."),
            ("My email is nadir@ example.com, so reach out.", "My email is nadir@example.com, so reach out."),
            ("Write to sales@ the team.", "Write to sales@ the team.")
        ])
    }

    func testLeavesOtherLanguagesAndAlreadyFormattedTextAlone() {
        XCTAssertEqual(DictationFormatter.format("Tengo veinte años, coma.", language: "es"), "Tengo veinte años, coma.")
        let formatted = "Meet me at 3:30 PM on March 15, 2026. It costs $25.50, or 50% off."
        XCTAssertEqual(DictationFormatter.format(formatted), formatted)
        XCTAssertEqual(DictationFormatter.format("Please visit https://example.com/a, then email a@b.co."), "Please visit https://example.com/a, then email a@b.co.")
        XCTAssertEqual(DictationFormatter.format("  Hello there.  "), "Hello there.")
    }

    func testCanonicalNumbersIgnoreStyle() {
        XCTAssertEqual(DictationFormatter.canonicalNumbers("Send two items"), "Send 2 items")
        XCTAssertEqual(DictationFormatter.canonicalNumbers("twenty five dollars"), "$25")
    }
}
