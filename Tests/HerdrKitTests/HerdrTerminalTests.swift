import Foundation
import IslandCore
import XCTest
@testable import HerdrKit

final class HerdrTerminalTests: XCTestCase {
    private func frame(_ sequence: Int, full: Bool, text: String = "\u{1b}[2J你好") -> Data {
        var data = try! JSONSerialization.data(withJSONObject: [
            "type": "terminal.frame", "seq": sequence, "encoding": "ansi", "width": 80,
            "height": 24, "full": full, "bytes": Data(text.utf8).base64EncodedString(),
        ])
        data.append(10)
        return data
    }

    func testArbitraryChunkBoundariesPreserveEveryANSIDelta() throws {
        var decoder = HerdrTerminalDecoder()
        let wire = frame(1, full: true) + frame(2, full: false, text: "\u{1b}[3;2H完成")
            + Data("{\"type\":\"terminal.closed\",\"reason\":\"done\"}\n".utf8)
        var events: [HerdrTerminalEvent] = []
        for byte in wire { events += try decoder.append(Data([byte])) }
        XCTAssertEqual(events.count, 3)
        guard case .frame(let first) = events[0], case .frame(let second) = events[1] else { return XCTFail() }
        XCTAssertEqual(String(decoding: first.bytes, as: UTF8.self), "\u{1b}[2J你好")
        XCTAssertEqual(String(decoding: second.bytes, as: UTF8.self), "\u{1b}[3;2H完成")
        XCTAssertEqual(events[2], .closed("done"))
    }

    func testMissingBaselineAndLostDeltaFailInsteadOfDisplayingCorruptScreen() throws {
        var decoder = HerdrTerminalDecoder()
        XCTAssertThrowsError(try decoder.append(frame(1, full: false)))
        decoder = HerdrTerminalDecoder()
        _ = try decoder.append(frame(1, full: true))
        XCTAssertThrowsError(try decoder.append(frame(3, full: false)))
    }

    func testLargeValidFrameIsNotRejectedByBase64Expansion() throws {
        let text = String(repeating: "x", count: 8 * 1_024 * 1_024)
        var decoder = HerdrTerminalDecoder()
        let events = try decoder.append(frame(1, full: true, text: text))
        guard case .frame(let result) = events.first else { return XCTFail("missing large frame") }
        XCTAssertEqual(result.bytes.count, text.utf8.count)
    }

    func testKeysAreEncodedByTheLivePTYRatherThanPresentationModes() {
        for (bytes, key) in [("\u{1b}[A", "up"), ("\u{1b}OD", "left"), ("\u{1b}[1;5C", "ctrl+right"),
                             ("\u{1b}[Z", "shift+tab"), ("\u{03}", "ctrl+c"), ("\r", "enter"), ("\u{7f}", "backspace")] {
            XCTAssertEqual(HerdrTerminalInput.decode(Data(bytes.utf8)), .key(key))
        }
        XCTAssertEqual(HerdrTerminalInput.decode(Data("中文 + emoji 🐈".utf8)), .text("中文 + emoji 🐈"))
    }

    func testInvalidBase64AndOversizedGridAreRejected() throws {
        for values: [String: Any] in [["bytes": "!"], ["width": 999_999]] {
            var object = try JSONSerialization.jsonObject(with: frame(1, full: true)) as! [String: Any]
            object.merge(values, uniquingKeysWith: { _, new in new })
            var wire = try JSONSerialization.data(withJSONObject: object)
            wire.append(10)
            var decoder = HerdrTerminalDecoder()
            XCTAssertThrowsError(try decoder.append(wire))
        }
    }

    @MainActor
    func testProcessInputOrderingSocketSelectionAndRelease() async throws {
        let directory = URL(fileURLWithPath: "/tmp/it-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("herdr")
        let log = directory.appendingPathComponent("commands")
        let script = """
        #!/usr/bin/python3
        import json,os,sys,socket,threading
        with open(os.path.join(os.path.dirname(__file__),'commands'),'w',buffering=1) as f:
            f.write(json.dumps({'args':sys.argv[1:],'socket':os.environ['HERDR_SOCKET_PATH']})+'\\n')
            listener=socket.socket(socket.AF_UNIX)
            listener.bind(os.environ['HERDR_SOCKET_PATH'])
            listener.listen(8)
            def requests():
                while True:
                    conn,_=listener.accept()
                    with conn:
                        request=json.loads(conn.makefile('rb').readline())
                        f.write(json.dumps({'type':request['method'],'params':request['params']})+'\\n')
                        conn.sendall((json.dumps({'id':request['id'],'result':{'type':'ok'}})+'\\n').encode())
            threading.Thread(target=requests,daemon=True).start()
            print('{"type":"terminal.frame","seq":1,"encoding":"ansi","width":80,"height":24,"full":true,"bytes":"aGk="}',flush=True)
            for line in sys.stdin:
                f.write(line)
                if json.loads(line)['type']=='terminal.release': break
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let session = HerdrTerminalSession()
        defer { session.stop() }
        let ready = expectation(description: "first real process frame")
        session.onEvent = {
            switch $0 {
            case .frame: ready.fulfill()
            case .closed(let reason): XCTFail("Process connection failed: \(reason ?? "EOF")")
            }
        }
        session.start(environment: HerdrEnvironment(binary: binary, socket: directory.appendingPathComponent("custom.sock")),
                      pane: PaneID("w9:p2"), columns: 80, rows: 24)
        await fulfillment(of: [ready], timeout: 5)
        session.send(Data("中文".utf8))
        session.send(Data([3]))
        session.resize(columns: 99, rows: 31)
        // Let admitted writes drain, then detach the client.
        try await Task.sleep(for: .milliseconds(100))
        session.stop()
        for _ in 0..<50 {
            if (try? String(contentsOf: log, encoding: .utf8).contains("terminal.release")) == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let records = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        XCTAssertEqual(records.first?["socket"] as? String, directory.appendingPathComponent("custom.sock").path)
        XCTAssertEqual(records.first?["args"] as? [String], ["terminal", "session", "control", "w9:p2", "--cols", "80", "--rows", "24"])
        let inputs = records.filter { ($0["type"] as? String)?.hasPrefix("pane.send_") == true }
        XCTAssertEqual(inputs.compactMap { $0["type"] as? String }, ["pane.send_text", "pane.send_keys"])
        XCTAssertEqual(records.last?["type"] as? String, "terminal.release")
        XCTAssertTrue(records.contains { $0["type"] as? String == "terminal.resize" })
        guard inputs.count == 2 else { return }
        XCTAssertEqual((inputs[0]["params"] as? [String: Any])?["text"] as? String, "中文")
        XCTAssertEqual((inputs[1]["params"] as? [String: Any])?["keys"] as? [String], ["ctrl+c"])
    }
}
