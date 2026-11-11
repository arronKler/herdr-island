import Foundation
import IslandCore
import XCTest
@testable import HerdrKit

final class HerdrTerminalTests: XCTestCase {
    private var welcome: Data { HerdrTerminalWire.framed(Data([0, 22, 1, 0])) }
    private func frame(_ sequence: Int, full: Bool, text: String = "\u{1b}[2J你好", columns: Int = 80) -> Data {
        HerdrTerminalWire.framed(HerdrTerminalWire.message(1, [.number(UInt64(sequence)), .number(UInt64(columns)),
            .number(24), .number(full ? 1 : 0), .bytes(Data(text.utf8))]))
    }

    func testArbitraryChunkBoundariesPreserveEveryANSIDelta() throws {
        var decoder = HerdrTerminalDecoder()
        let wire = welcome + frame(1, full: true) + frame(2, full: false, text: "\u{1b}[3;2H完成")
            + HerdrTerminalWire.framed(HerdrTerminalWire.message(3, [.number(1), .bytes(Data("done".utf8))]))
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
        XCTAssertThrowsError(try decoder.append(welcome + frame(1, full: false)))
        decoder = HerdrTerminalDecoder()
        _ = try decoder.append(welcome + frame(1, full: true))
        XCTAssertThrowsError(try decoder.append(frame(3, full: false)))
    }

    func testLargeValidFrameIsNotRejectedByBase64Expansion() throws {
        let text = String(repeating: "x", count: 8 * 1_024 * 1_024)
        var decoder = HerdrTerminalDecoder()
        let events = try decoder.append(welcome + frame(1, full: true, text: text))
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

    func testIncompatibleProtocolOversizedFramesAndInvalidGridAreRejected() throws {
        for wire in [Data([255, 255, 255, 127]), HerdrTerminalWire.framed(Data([0, 23, 1, 0])),
                     welcome + frame(1, full: true, columns: 1_001)] {
            var decoder = HerdrTerminalDecoder()
            XCTAssertThrowsError(try decoder.append(wire))
        }
        var decoder = HerdrTerminalDecoder()
        XCTAssertEqual(try decoder.append(welcome + HerdrTerminalWire.framed(Data([8, 1, 0]))), [.mouseCapture(true)])
        XCTAssertEqual(try decoder.append(HerdrTerminalWire.framed(Data([8, 0, 0]))), [.mouseCapture(false)])
    }

    func testMouseWireUsesSemanticCellCoordinatesAndCorrectButtons() {
        XCTAssertEqual(HerdrTerminalWire.mouse(.init(action: .down, button: .right, column: 4, row: 3, modifiers: 2)),
                       Data([16, 0, 1, 0, 4, 3, 0, 2, 1]))
        XCTAssertEqual(HerdrTerminalWire.mouse(.init(action: .move, column: 4, row: 3)),
                       Data([16, 3, 0, 4, 3, 0, 0, 1]))
    }

    @MainActor
    func testProcessInputOrderingSocketSelectionAndRelease() async throws {
        let directory = URL(fileURLWithPath: "/tmp/it-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("unused-herdr")
        let log = directory.appendingPathComponent("commands")
        let script = directory.appendingPathComponent("server.py")
        try """
        import json,os,sys,socket,threading,struct
        root=sys.argv[1]
        with open(os.path.join(root,'commands'),'w',buffering=1) as f:
            api=socket.socket(socket.AF_UNIX); api.bind(root+'/custom.sock'); api.listen(8)
            stream=socket.socket(socket.AF_UNIX); stream.bind(root+'/custom-client.sock'); stream.listen(1)
            def log(value): f.write(json.dumps(value)+'\\n')
            def requests():
                while True:
                    conn,_=api.accept()
                    with conn:
                        request=json.loads(conn.makefile('rb').readline())
                        log({'type':request['method'],'params':request['params']})
                        conn.sendall((json.dumps({'id':request['id'],'result':{'type':'ok'}})+'\\n').encode())
            threading.Thread(target=requests,daemon=True).start()
            conn,_=stream.accept()
            reader=conn.makefile('rb')
            def read():
                size=reader.read(4)
                if len(size)!=4: return b''
                return reader.read(struct.unpack('<I',size)[0])
            def write(data): conn.sendall(struct.pack('<I',len(data))+data)
            log({'type':'hello','bytes':list(read())})
            write(bytes([0,22,1,0]))
            log({'type':'control','bytes':list(read())})
            write(bytes([8,1,0]))
            write(bytes([1,1,80,24,1,2])+b'hi')
            while True:
                data=read()
                if not data: break
                log({'type':'wire','bytes':list(data)})
            log({'type':'closed'})
        """.write(to: script, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path, directory.path]
        try server.run()
        defer { if server.isRunning { server.terminate() } }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("custom-client.sock").path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let session = HerdrTerminalSession()
        defer { session.stop() }
        let ready = expectation(description: "first real process frame")
        session.onEvent = {
            switch $0 {
            case .frame: ready.fulfill()
            case .mouseCapture, .historyPosition: break
            case .closed(let reason): XCTFail("Process connection failed: \(reason ?? "EOF")")
            }
        }
        session.start(environment: HerdrEnvironment(binary: binary, socket: directory.appendingPathComponent("custom.sock")),
                      pane: PaneID("w9:p2"), columns: 80, rows: 24)
        await fulfillment(of: [ready], timeout: 5)
        session.send(Data("中文".utf8))
        session.paste("image path")
        session.scroll(up: true, lines: 3)
        session.scroll(up: false, lines: 2)
        for _ in 0..<1_200 { session.scroll(up: true, lines: 1) }
        session.scroll(up: true, lines: 23, page: true)
        session.scroll(up: true, lines: 23, page: true)
        session.resumeLiveOutput()
        session.send(Data([3]))
        session.mouse(.init(action: .down, column: 4, row: 3))
        session.mouse(.init(action: .up, column: 4, row: 3))
        session.resize(columns: 99, rows: 31)
        // Let admitted writes drain, then detach the client.
        for _ in 0..<100 {
            if (try? String(contentsOf: log, encoding: .utf8).contains("[3, 99, 31")) == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        session.stop()
        for _ in 0..<50 {
            if (try? String(contentsOf: log, encoding: .utf8).contains("closed")) == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let records = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        XCTAssertEqual(records.first?["bytes"] as? [Int], [0, 22, 80, 24, 0, 0, 0])
        XCTAssertEqual(records[1]["bytes"] as? [Int], [8, 5, 119, 57, 58, 112, 50, 0])
        let inputs = records.filter { ($0["type"] as? String)?.hasPrefix("pane.send_") == true }
        XCTAssertEqual(inputs.compactMap { $0["type"] as? String }, ["pane.send_text", "pane.send_input", "pane.send_keys"])
        XCTAssertEqual(records.last?["type"] as? String, "closed")
        let wire = records.compactMap { $0["type"] as? String == "wire" ? $0["bytes"] as? [UInt8] : nil }.map { Data($0) }
        XCTAssertTrue(wire.contains(HerdrTerminalWire.resize(columns: 99, rows: 31)))
        let scrolls = wire.filter { $0.first == 6 }
        XCTAssertEqual(scrolls, [
            HerdrTerminalWire.scroll(up: true, lines: 3, page: false, column: nil, row: nil, modifiers: 0),
            HerdrTerminalWire.scroll(up: false, lines: 2, page: false, column: nil, row: nil, modifiers: 0),
            HerdrTerminalWire.scroll(up: true, lines: 1_200, page: false, column: nil, row: nil, modifiers: 0),
            HerdrTerminalWire.scroll(up: true, lines: 23, page: true, column: nil, row: nil, modifiers: 0),
            HerdrTerminalWire.scroll(up: true, lines: 23, page: true, column: nil, row: nil, modifiers: 0),
        ])
        XCTAssertEqual(wire.filter { $0.first == 16 }, [
            HerdrTerminalWire.mouse(.init(action: .down, column: 4, row: 3)),
            HerdrTerminalWire.mouse(.init(action: .up, column: 4, row: 3)),
        ])
        XCTAssertEqual(wire.filter { $0.first == 1 }.count, 2)
        guard inputs.count == 3 else { return }
        XCTAssertEqual((inputs[0]["params"] as? [String: Any])?["text"] as? String, "中文")
        XCTAssertEqual((inputs[1]["params"] as? [String: Any])?["text"] as? String, "image path")
        XCTAssertEqual((inputs[2]["params"] as? [String: Any])?["keys"] as? [String], ["ctrl+c"])
    }
}
