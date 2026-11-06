import XCTest
import IslandCore
@testable import HerdrKit

/// Opt-in live benchmarks, excluded from ordinary unit test runs. No tokens,
/// prompts or terminal output are written to the performance report.
final class TaskCreationPerformanceTests: XCTestCase {
    func testLiveReadTransport() async throws {
        guard ProcessInfo.processInfo.environment["ISLAND_BENCHMARK_READS"] == "1" else {
            throw XCTSkip("Set ISLAND_BENCHMARK_READS=1 for a live, read-only benchmark")
        }
        let environment = try HerdrLocator.resolve()
        let cli = HerdrCLI(binary: environment.binary)
        let direct = HerdrCLI(binary: environment.binary, socketURL: environment.socket)
        var legacy: [Double] = []
        var optimized: [Double] = []
        for index in 0..<30 {
            // Alternate order to reduce warm-cache/order bias.
            for isDirect in index.isMultiple(of: 2) ? [false, true] : [true, false] {
                let start = ContinuousClock.now
                _ = try await (isDirect ? direct : cli).listAgents()
                let duration = Self.seconds(start.duration(to: .now)) * 1_000
                if isDirect { optimized.append(duration) } else { legacy.append(duration) }
            }
        }
        let oldMedian = Self.median(legacy)
        let newMedian = Self.median(optimized)
        print("ISLAND_PERF_READS n=30 cli_median_ms=\(oldMedian) socket_median_ms=\(newMedian) speedup=\(oldMedian / newMedian)")
        print("ISLAND_PERF_READS cli_p95_ms=\(legacy.sorted()[28]) socket_p95_ms=\(optimized.sorted()[28])")
    }

    func testLiveTaskCreation() async throws {
        guard ProcessInfo.processInfo.environment["ISLAND_BENCHMARK_CREATE"] == "1" else {
            throw XCTSkip("Set ISLAND_BENCHMARK_CREATE=1 to create and clean up one real Claude task")
        }
        let environment = try HerdrLocator.resolve()
        let logStart = ContinuousClock.now
        let service = HerdrService(
            cli: HerdrCLI(binary: environment.binary, socketURL: environment.socket),
            socketURL: environment.socket,
            log: { print("ISLAND_PERF_EVENT t=\(Self.seconds(logStart.duration(to: .now))) \($0)") }
        )
        _ = await service.start()
        let recorder = PerformancePaneRecorder()
        let start = ContinuousClock.now
        let result = await service.createTask(QuickTaskRequest(
            name: "island-perf-\(UUID().uuidString.prefix(6).lowercased())",
            text: "Reply exactly ISLAND_PERF_OK. Do not use tools, edit files, or run commands.",
            kind: .claude, cwd: FileManager.default.currentDirectoryPath, label: "Island creation performance probe"
        )) { await recorder.record($0) }
        let elapsed = Self.seconds(start.duration(to: .now))
        await service.stop()
        // Resolve the authoritative workspace ID rather than parsing a pane ID.
        if let pane = await recorder.pane {
            let lookup = try command(environment.binary, ["pane", "get", pane.rawValue])
            let object = try JSONSerialization.jsonObject(with: lookup) as? [String: Any]
            let payload = object?["result"] as? [String: Any]
            let pane = payload?["pane"] as? [String: Any]
            let workspace = try XCTUnwrap(pane?["workspace_id"] as? String)
            _ = try command(environment.binary, ["workspace", "close", workspace])
        }
        guard case .success(let launch) = result else { return XCTFail("real launch failed: \(result)") }
        print("ISLAND_PERF_CREATE cold_total_seconds=\(elapsed) confirmed_status=\(launch.agent?.status.rawValue ?? "missing")")
    }

    private func command(_ binary: URL, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return data
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

private actor PerformancePaneRecorder {
    var pane: PaneID?
    func record(_ progress: TaskCreationProgress) { if let pane = progress.pane { self.pane = pane } }
}
