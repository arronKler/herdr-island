import Darwin
import XCTest
import IslandCore
@testable import HerdrKit

final class HerdrReadRPCTests: XCTestCase {
    func testPreviewUsesTypedSocketParametersAndPreservesHistory() async throws {
        let socket = try serve { request in
            XCTAssertEqual(request["method"] as? String, "agent.read")
            let params = request["params"] as? [String: Any]
            XCTAssertEqual(params?["target"] as? String, "w1:p1")
            XCTAssertEqual(params?["source"] as? String, "recent_unwrapped")
            XCTAssertEqual(params?["lines"] as? Int, 60)
            XCTAssertEqual(params?["strip_ansi"] as? Bool, true)
            return [self.response(request, result: ["read": ["pane_id": "w1:p1", "text": "history\nvisible\n"]])]
        }
        let cli = HerdrCLI(binary: URL(fileURLWithPath: "/missing-herdr"), socketURL: socket)
        let text = try await cli.readPreview(pane: PaneID("w1:p1"), lines: 60)
        XCTAssertEqual(text, "history\nvisible")
    }

    func testBusyPreviewFallsBackToVisibleWithoutDisablingSocket() async throws {
        let socket = try serve(requestCount: 3) { request in
            if request["method"] as? String == "agent.list" {
                return [self.response(request, result: ["agents": []])]
            }
            let params = request["params"] as? [String: Any]
            if params?["source"] as? String == "recent_unwrapped" {
                var data = try! JSONSerialization.data(withJSONObject: [
                    "id": request["id"]!, "error": ["code": "agent_not_idle", "message": "Cannot scroll working agent"],
                ])
                data.append(0x0A)
                return [data]
            }
            XCTAssertEqual(params?["source"] as? String, "visible")
            return [self.response(request, result: ["read": ["pane_id": "w1:p1", "text": "live output"]])]
        }
        let cli = HerdrCLI(binary: URL(fileURLWithPath: "/missing-herdr"), socketURL: socket)
        let text = try await cli.readPreview(pane: PaneID("w1:p1"), lines: 60)
        XCTAssertEqual(text, "live output")
        let agents = try await cli.listAgents()
        XCTAssertTrue(agents.isEmpty)
    }

    func testPreviewNeverAcceptsTextFromADifferentPane() async throws {
        let socket = try serve { request in
            [self.response(request, result: ["read": ["pane_id": "w9:p9", "text": "other task"]])]
        }
        let cli = HerdrCLI(binary: URL(fileURLWithPath: "/missing-herdr"), socketURL: socket)
        do {
            _ = try await cli.readPreview(pane: PaneID("w1:p1"), lines: 60)
            XCTFail("must not show another pane's output")
        } catch { }
    }

    func testReadsFragmentedResponseWithoutSpawningCLI() async throws {
        let socket = try serve { request in
            XCTAssertEqual(request["method"] as? String, "agent.list")
            let response = self.response(request, result: ["agents": [[
                "pane_id": "w1:p1", "agent": "claude", "agent_status": "working", "revision": 42,
            ]]])
            return [Data(response.prefix(13)), Data(response.dropFirst(13))]
        }
        let cli = HerdrCLI(binary: URL(fileURLWithPath: "/missing-herdr"), socketURL: socket)
        let agents = try await cli.listAgents()
        XCTAssertEqual(agents.map(\.pane), [PaneID("w1:p1")])
        XCTAssertEqual(agents.first?.status, .working)
        XCTAssertEqual(agents.first?.terminalRevision, 42)
    }

    func testPaneDirectoriesUseTheSocket() async throws {
        let socket = try serve { request in
            XCTAssertEqual(request["method"] as? String, "pane.list")
            return [self.response(request, result: ["panes": [["cwd": "/tmp/project", "focused": true]]])]
        }
        let cli = HerdrCLI(binary: URL(fileURLWithPath: "/missing-herdr"), socketURL: socket)
        let directory = try await cli.focusedPaneCwd()
        XCTAssertEqual(directory, "/tmp/project")
    }

    func testMalformedOrMismatchedResponseIsRejected() async throws {
        for payload in ["not-json\n", "{\"id\":\"wrong-id\",\"result\":{}}\n"] {
            let socket = try serve { _ in [Data(payload.utf8)] }
            do {
                _ = try await HerdrRPC(socketURL: socket).request(method: "agent.list", timeout: 1)
                XCTFail("must reject invalid or uncorrelated data")
            } catch { XCTAssertFalse(error is CancellationError) }
        }
    }

    func testUnavailableSocketFallsBackToCLI() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("herdr")
        try "#!/bin/sh\necho '{\"result\":{\"agents\":[]}}'\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let cli = HerdrCLI(binary: binary, socketURL: directory.appendingPathComponent("missing.sock"))
        let agents = try await cli.listAgents()
        XCTAssertTrue(agents.isEmpty)
    }

    func testSilentServerTimesOut() async throws {
        let socket = try serve { _ in Thread.sleep(forTimeInterval: 0.4); return [] }
        do {
            _ = try await HerdrRPC(socketURL: socket).request(method: "agent.list", timeout: 0.1)
            XCTFail("expected deadline")
        } catch let failure as BackendFailure {
            XCTAssertEqual(failure.kind, .timeout)
        }
    }

    func testCancellationDoesNotWaitForReadDeadlineOrFallBackToCLI() async throws {
        let received = expectation(description: "server received read")
        let socket = try serve { _ in received.fulfill(); Thread.sleep(forTimeInterval: 0.5); return [] }
        let cli = HerdrCLI(binary: URL(fileURLWithPath: "/missing-herdr"), socketURL: socket)
        let task = Task { try await cli.listAgents() }
        await fulfillment(of: [received], timeout: 2)
        let start = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(400))
    }

    private func response(_ request: [String: Any], result: [String: Any]) -> Data {
        var data = try! JSONSerialization.data(withJSONObject: ["id": request["id"]!, "result": result])
        data.append(0x0A)
        return data
    }

    /// A bounded Unix server exercises actual framing and IO.
    private func serve(requestCount: Int = 1, reply: @escaping ([String: Any]) -> [Data]) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/island-rpc-\(UUID().uuidString.prefix(12)).sock")
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(url.path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 1) == 0 else {
            Darwin.close(listener)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        DispatchQueue.global().async {
            defer { Darwin.close(listener); unlink(url.path) }
            for _ in 0..<requestCount {
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 3000) > 0 else { return }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { Darwin.close(client) }
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while !data.contains(0x0A), data.count < 8192 {
                let count = Darwin.read(client, &buffer, buffer.count)
                guard count > 0 else { return }
                data.append(contentsOf: buffer.prefix(count))
            }
            guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            for chunk in reply(request) {
                _ = chunk.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
            }
            }
        }
        return url
    }
}
