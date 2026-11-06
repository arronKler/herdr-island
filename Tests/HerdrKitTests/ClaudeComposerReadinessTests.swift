import XCTest
import IslandCore
@testable import HerdrKit

final class ClaudeComposerReadinessTests: XCTestCase {
    private let pane = PaneID("w2:p1")

    func testRecognizesOnlyAnEmptyBoundedClaudeComposer() {
        XCTAssertTrue(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ ")))
        XCTAssertTrue(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ ").replacingOccurrences(of: "\n", with: "\r\n")))
        XCTAssertTrue(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ \u{1b}[0m\u{1b}[2mTry \"fix a bug\"\u{1b}[0m")))
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ Try \"fix a bug\"")), "Typed text can resemble the placeholder")
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ \u{1b}[2mTry \"fix \u{1b}[22ma bug\"")), "Every placeholder character must remain dim")
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ \u{1b}[38;2;2;22;0mTry \"fix a bug\"\u{1b}[0m")), "RGB color components are not SGR dim/reset commands")
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ real task\n  second line")))
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ \u{1b}[2m[Pasted text +2 lines]\u{1b}[0m")))
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer("Claude Code\n❯ "), "A shell glyph alone is insufficient")
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ ").replacingOccurrences(of: "Claude Code", with: "Trust this folder?")))
        XCTAssertFalse(ClaudeComposerReadiness.hasEmptyComposer(screen("❯ \u{1b}[2J")), "Unknown control sequences fail closed")
    }

    func testWaitsForTwoConsecutiveReadyScreens() async throws {
        let samples = Samples(identity: identity(), screens: [screen("❯ "), "Starting", screen("❯ "), screen("❯ ")])
        try await ClaudeComposerReadiness.wait(
            pane: pane, name: "new-task", timeout: .seconds(1), interval: .milliseconds(1),
            readIdentity: { await samples.agent() }, readScreen: { await samples.screen() }
        )
        let reads = await samples.screenReads
        XCTAssertEqual(reads, 4)
    }

    func testStateChangeAfterReadingReadyScreenFailsBeforeSubmission() async throws {
        let samples = Samples(identity: identity(), screens: [screen("❯ ")], changedIdentity: identity(terminal: "another-terminal"), changeAfterScreens: 2)
        do {
            try await ClaudeComposerReadiness.wait(
                pane: pane, name: "new-task", timeout: .seconds(1), interval: .milliseconds(1),
                readIdentity: { await samples.agent() }, readScreen: { await samples.screen() }
            )
            XCTFail("A replacement terminal must never receive the prompt")
        } catch let failure as BackendFailure { XCTAssertEqual(failure.kind, .commandFailed) }
    }

    func testNonemptyComposerTimesOutWithoutBecomingReady() async throws {
        let samples = Samples(identity: identity(), screens: [screen("❯ already typed")])
        do {
            try await ClaudeComposerReadiness.wait(
                pane: pane, name: "new-task", timeout: .milliseconds(30), interval: .milliseconds(5),
                readIdentity: { await samples.agent() }, readScreen: { await samples.screen() }
            )
            XCTFail("Existing input must not be overwritten")
        } catch let failure as BackendFailure { XCTAssertEqual(failure.kind, .timeout) }
    }

    func testCancellationStopsReadinessPolling() async throws {
        let samples = Samples(identity: identity(), screens: ["Starting"])
        let pane = pane
        let operation = Task {
            try await ClaudeComposerReadiness.wait(
                pane: pane, name: "new-task", interval: .milliseconds(5),
                readIdentity: { await samples.agent() }, readScreen: { await samples.screen() }
            )
        }
        while await samples.screenReads == 0 { await Task.yield() }
        operation.cancel()
        do { try await operation.value; XCTFail("Cancelled creation must stop") }
        catch { XCTAssertTrue(error is CancellationError) }
        let reads = await samples.screenReads
        try await Task.sleep(for: .milliseconds(15))
        let laterReads = await samples.screenReads
        XCTAssertEqual(reads, laterReads)
    }

    private func identity(terminal: String = "term_test") -> ClaudeComposerReadiness.Identity {
        .init(pane_id: pane.rawValue, terminal_id: terminal, name: "new-task", agent: "claude",
              agent_status: "idle", interactive_ready: true, completion_seq: nil, state_change_seq: 1)
    }

    private func screen(_ row: String) -> String {
        "Claude Code\n────────────────────\n\(row)\n────────────────────\n? for shortcuts"
    }

    private actor Samples {
        let identity: ClaudeComposerReadiness.Identity
        let screens: [String]
        let changedIdentity: ClaudeComposerReadiness.Identity?
        let changeAfterScreens: Int
        private(set) var screenReads = 0

        init(identity: ClaudeComposerReadiness.Identity, screens: [String], changedIdentity: ClaudeComposerReadiness.Identity? = nil, changeAfterScreens: Int = .max) {
            self.identity = identity; self.screens = screens
            self.changedIdentity = changedIdentity; self.changeAfterScreens = changeAfterScreens
        }

        func agent() -> ClaudeComposerReadiness.Identity {
            screenReads >= changeAfterScreens ? changedIdentity ?? identity : identity
        }

        func screen() -> String {
            defer { screenReads += 1 }
            return screens[min(screenReads, screens.count - 1)]
        }
    }
}
