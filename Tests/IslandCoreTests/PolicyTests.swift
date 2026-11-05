import XCTest
@testable import IslandCore

final class PolicyTests: XCTestCase {
    func testMessagePolicyAllowsIdleAndDoneOnly() {
        for status in AgentStatus.allCases {
            let agent = makeAgent("w1:p1", status)
            switch status {
            case .idle, .done:
                XCTAssertNil(MessagePolicy.refusal(for: agent), "\(status) should accept a prompt")
                XCTAssertTrue(agent.acceptsPrompt)
            case .working, .blocked, .unknown:
                XCTAssertNotNil(MessagePolicy.refusal(for: agent), "\(status) should refuse a prompt")
                XCTAssertFalse(agent.acceptsPrompt)
            }
        }

        XCTAssertTrue(MessagePolicy.canSend(to: makeAgent("w1:p1", .idle), draft: " hi "))
        XCTAssertTrue(MessagePolicy.canSend(to: makeAgent("w1:p1", .done), draft: "hi"))
        XCTAssertFalse(MessagePolicy.canSend(to: makeAgent("w1:p1", .idle), draft: "   \n"))
        XCTAssertFalse(MessagePolicy.canSend(to: makeAgent("w1:p1", .blocked), draft: "hi"))
        XCTAssertFalse(MessagePolicy.canSend(to: makeAgent("w1:p1", .working), draft: "hi"))
        XCTAssertFalse(MessagePolicy.canSend(to: makeAgent("w1:p1", .unknown), draft: "hi"))
        XCTAssertFalse(MessagePolicy.canSend(to: nil, draft: "hi"))
        XCTAssertEqual(MessagePolicy.normalizedDraft("  hi\n"), "hi")
    }

    func testKeyboardRouterPassesTextEditingKeysThrough() {
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .return), composerFocused: true), .passThrough)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .other), composerFocused: true), .passThrough)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .upArrow), composerFocused: true), .passThrough)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .downArrow), composerFocused: true), .passThrough)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .tab), composerFocused: true), .passThrough)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .return, modifiers: .shift), composerFocused: true), .passThrough)

        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .escape), composerFocused: true), .dismiss)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .return, modifiers: .command), composerFocused: true), .send)

        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .return), composerFocused: false), .jump)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .upArrow), composerFocused: false), .moveSelection(-1))
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .downArrow), composerFocused: false), .moveSelection(1))
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .tab), composerFocused: false), .focusComposer)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .other), composerFocused: false), .passThrough)
        XCTAssertEqual(KeyboardRouter.route(KeyStroke(key: .escape), composerFocused: false), .dismiss)
        XCTAssertEqual(
            KeyboardRouter.route(KeyStroke(key: .return, modifiers: [.command, .shift]), composerFocused: false),
            .send
        )
    }
}
