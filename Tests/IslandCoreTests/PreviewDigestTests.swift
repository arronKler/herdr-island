import XCTest
@testable import IslandCore

final class PreviewDigestTests: XCTestCase {
    func testQuestionComesFromTheApprovalPromptNotEarlierOutput() {
        let text = """
        Earlier the agent asked: should we retry?
        Some output that is unrelated to the prompt.

        Do you want to proceed?
        ❯ 1. Yes
          2. No
        """
        XCTAssertEqual(PreviewDigest.question(text), "Do you want to proceed?")
    }

    func testQuestionSkipsBoxBordersAroundTheApprovalChoices() {
        let text = """
        old output

        Command to approve · low risk
        ╭──────────────────────────────╮
        │  Yes, allow                  │
        │  No, cancel                  │
        ╰──────────────────────────────╯
          ↑↓ navigate   Enter select   Esc cancel
        """
        XCTAssertEqual(PreviewDigest.question(text), "Command to approve · low risk")
    }

    func testQuestionFallsBackToTheFirstContentRow() {
        let text = """
        previous output

        ╭──────────────────────────────╮
        │  Yes, allow                  │
        ╰──────────────────────────────╯
        """
        XCTAssertEqual(PreviewDigest.question(text), "Yes, allow")
    }

    func testQuestionIsNilWhenTheWindowHasNoPrompt() {
        let text = """
        ✻ Cogitated for 1m 35s · done 11:22 AM

        ※ recap: The work is finished.
        """
        XCTAssertNil(PreviewDigest.question(text))
    }

    func testQuestionPrefersTheLineEndingWithAQuestionMark() {
        let text = """
        Allow this command?
        ❯ 1. Yes
        const retry = options?.retry
        """
        XCTAssertEqual(PreviewDigest.question(text), "Allow this command?")
    }

    func testQuestionIsNilForABarePromptBetweenRules() {
        let text = """
        ✻ Cogitated for 1m 35s · done 11:22 AM

        ────────────────────────────────────────
        ❯
        ────────────────────────────────────────
          ⏵⏵ auto mode on (shift+tab to cycle)
        """
        XCTAssertNil(PreviewDigest.question(text))
    }

    func testFixtureQuestionIsTheApprovalLine() {
        XCTAssertEqual(
            PreviewDigest.question(Fixtures.blockedPreview),
            "Allow Codex to run this command?"
        )
    }

    func testQuestionStripsTheBoxBeforePreferringQuestionMarks() {
        let text = """
        old output
        ╭──────────────────────────────╮
        │  Do you want to proceed?     │
        ╰──────────────────────────────╯
          ? for shortcuts
        """
        XCTAssertEqual(PreviewDigest.question(text), "Do you want to proceed?")
    }

    func testCommandUsesTheMostRecentMatch() {
        let text = """
        $ npm run lint
        tests passed

        $ npm test -- --runInBand
        """
        XCTAssertEqual(PreviewDigest.command(text), "npm test -- --runInBand")
    }

    func testCommandLooksBeyondThePromptWindow() {
        let filler = (1...14).map { "output \($0)" }
        let text = (["$ swift build"] + filler).joined(separator: "\n")
        XCTAssertEqual(PreviewDigest.command(text), "swift build")
    }

    func testCommandStripsBoxBorders() {
        let text = """
        ╭──────────────────────────────╮
        │ $ npm test                  │
        ╰──────────────────────────────╯
        """
        XCTAssertEqual(PreviewDigest.command(text), "npm test")
    }

    func testReasonIgnoresOldOutputOutsideThePromptWindow() {
        let filler = (1...12).map { "recent output \($0)" }
        let text = (["permission output"] + filler + ["", "Please log in to continue."])
            .joined(separator: "\n")
        XCTAssertEqual(PreviewDigest.reason(text), .auth)
    }

    func testLastLineSkipsTrailingBlankRows() {
        XCTAssertEqual(PreviewDigest.lastLine("first\r\nsecond\r\n\r\n"), "second")
    }
}
