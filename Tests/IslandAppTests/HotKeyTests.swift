import Carbon.HIToolbox
import XCTest
@testable import HerdrIsland

@MainActor
final class HotKeyTests: XCTestCase {
    func testBothHotkeysReceiveTheirEventsWhenRegisteredTogether() async throws {
        let first = GlobalHotKey(keyCode: UInt32(kVK_F18), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), id: 90)
        let second = GlobalHotKey(keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), id: 91)
        defer { first.unregister(); second.unregister() }
        let firstPress = expectation(description: "first hotkey")
        let secondPress = expectation(description: "second hotkey")
        XCTAssertTrue(first.register { firstPress.fulfill() })
        XCTAssertTrue(second.register { secondPress.fulfill() })
        for id: UInt32 in [90, 91] {
            var createdEvent: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &createdEvent), noErr)
            let event = try XCTUnwrap(createdEvent)
            defer { ReleaseEvent(event) }
            var pressed = EventHotKeyID(signature: OSType(0x48494B59), id: id)
            XCTAssertEqual(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &pressed), noErr)
            XCTAssertEqual(SendEventToEventTarget(event, GetApplicationEventTarget()), noErr)
        }
        await fulfillment(of: [firstPress, secondPress], timeout: 2)
    }
}
