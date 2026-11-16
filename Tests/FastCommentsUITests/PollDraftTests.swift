import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

final class PollDraftTests: XCTestCase {

    func testNewDraftHasTwoEmptyOptions() {
        let draft = PollDraft()
        XCTAssertEqual(draft.options.map(\.text), ["", ""])
        XCTAssertFalse(draft.canRemoveOption)
        XCTAssertTrue(draft.canAddOption)
    }

    func testValidateRequiresQuestion() {
        XCTAssertEqual(PollDraft(question: "   ", options: ["A", "B"]).validate(), .questionRequired)
    }

    func testValidateRequiresTwoFilledOptions() {
        XCTAssertEqual(PollDraft(question: "Q", options: ["A", "  "]).validate(), .tooFewOptions)
        XCTAssertNil(PollDraft(question: "Q", options: ["A", "B"]).validate())
    }

    func testOptionLimits() {
        let full = PollDraft(question: "Q", options: (1...PollDraft.maxOptions).map(String.init))
        XCTAssertFalse(full.canAddOption)
        XCTAssertTrue(full.canRemoveOption)
    }

    func testToInputTrimsAndDropsBlankOptions() {
        let input = PollDraft(question: "  Lunch?  ", options: [" Tacos ", "", "Ramen"]).toInput()
        XCTAssertEqual(input.question, "Lunch?")
        XCTAssertEqual(input.options, ["Tacos", "Ramen"])
    }

    func testToInputLeavesDefaultsOut() {
        let input = PollDraft(question: "Q", options: ["A", "B"]).toInput()
        XCTAssertNil(input.closesAt)
        XCTAssertNil(input.privacy)
        XCTAssertNil(input.requireVoteToSeeResults)
    }

    func testToInputCarriesChoices() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let input = PollDraft(
            question: "Q", options: ["A", "B"], closesDays: 3, privacy: ._2, requireVoteToSeeResults: true
        ).toInput(now: now)

        let closesAt = try XCTUnwrap(input.closesAt.flatMap(ISO8601DateFormatter().date(from:)))
        XCTAssertEqual(closesAt.timeIntervalSince(now), 3 * 86_400)
        XCTAssertEqual(input.privacy, 2)
        XCTAssertEqual(input.requireVoteToSeeResults, true)
    }

    func testSanitizeFlattensPastedLines() {
        XCTAssertEqual(PollDraft.sanitize("one\n\ntwo\tthree", maxLength: 100), "one two three")
    }

    func testSanitizeKeepsSpacesWhileTyping() {
        XCTAssertEqual(PollDraft.sanitize("two  words ", maxLength: 100), "two  words ")
    }

    func testSanitizeLimitsLengthWithoutSplittingAnEmoji() {
        XCTAssertEqual(PollDraft.sanitize("abcdef", maxLength: 3), "abc")
        // Each flag is 4 UTF-16 units, and the server counts those.
        XCTAssertEqual(PollDraft.sanitize("🇨🇦🇨🇦", maxLength: 6), "🇨🇦")
    }
}
