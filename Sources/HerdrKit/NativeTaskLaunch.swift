import Foundation
import IslandCore

/// A native initial prompt may begin before `agent start` reports interactive
/// readiness. Observe this fresh pane while startup runs so a long first turn
/// does not keep the creation UI waiting for that turn to finish.
enum NativeTaskLaunch {
    /// Herdr rejects control characters in native argv. Multiline tasks must
    /// retain their text and use the normal ready-then-prompt path instead.
    static func supportsNativePrompt(_ text: String) -> Bool {
        !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    enum Observation: Sendable {
        case snapshot(Agent)
        case facts(AgentFacts)
    }

    private enum Event: Sendable {
        case started
        case confirmed(Agent)
    }

    static func confirm(
        cli: HerdrCLI,
        request: QuickTaskRequest,
        pane: PaneID,
        startedAt: Date,
        observations: AsyncStream<Observation>? = nil,
        onProgress: @escaping TaskCreationObserver
    ) async throws -> Agent {
        try await withThrowingTaskGroup(of: Event.self) { group in
            group.addTask {
                do {
                    try await cli.startAgent(
                        name: request.name, kind: request.kind.rawValue, pane: pane,
                        initialPrompt: request.text, timeout: 50
                    )
                    return .started
                } catch {
                    // A readiness error can race with the first turn starting.
                    if !Task.isCancelled, let agent = try? await observedAgent(cli, pane, request.kind),
                       hasStarted(agent) { return .confirmed(agent) }
                    throw error
                }
            }
            group.addTask {
                if let observations {
                    var latest: Agent?
                    var reportedSubmission = false
                    for await observation in observations {
                        try Task.checkCancellation()
                        switch observation {
                        case .snapshot(let agent):
                            guard agent.pane == pane, agent.kind == request.kind.rawValue else { continue }
                            latest = agent
                        case .facts(let facts):
                            guard facts.pane == pane,
                                  facts.kind == nil || facts.kind == request.kind.rawValue else { continue }
                            if latest == nil {
                                latest = try? await observedAgent(cli, pane, request.kind)
                            }
                            latest = latest?.applying(facts)
                        }
                        guard let agent = latest else { continue }
                        try await checkStartupRefusal(cli, pane, request.kind)
                        if !reportedSubmission {
                            reportedSubmission = true
                            await onProgress(TaskCreationProgress(stage: .submission, startedAt: startedAt, pane: pane))
                        }
                        if hasStarted(agent) { return .confirmed(agent) }
                    }
                    throw CancellationError()
                }
                // Standalone callers without a running service still observe
                // startup. The app reuses its existing socket and sample loop.
                let deadline = ContinuousClock.now.advanced(by: .seconds(50))
                var reportedSubmission = false
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation()
                    if let agent = try await observedAgent(cli, pane, request.kind) {
                        try await checkStartupRefusal(cli, pane, request.kind)
                        if !reportedSubmission {
                            reportedSubmission = true
                            await onProgress(TaskCreationProgress(stage: .submission, startedAt: startedAt, pane: pane))
                        }
                        if hasStarted(agent) { return .confirmed(agent) }
                    }
                    try await Task.sleep(for: .milliseconds(400))
                }
                throw BackendFailure(.timeout, "尚未观察到首条任务开始，请在终端检查。")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(50))
                throw BackendFailure(.timeout, "尚未观察到首条任务开始，请在终端检查。")
            }
            defer { group.cancelAll() }
            for try await event in group {
                if case .confirmed(let agent) = event { return agent }
            }
            throw BackendFailure(.commandFailed, "未能确认首条任务开始。")
        }
    }

    private static func observedAgent(_ cli: HerdrCLI, _ pane: PaneID, _ kind: AgentKindOption) async throws -> Agent? {
        try await cli.listAgents(timeout: 2).first { $0.pane == pane && $0.kind == kind.rawValue }
    }

    private static func checkStartupRefusal(_ cli: HerdrCLI, _ pane: PaneID, _ kind: AgentKindOption) async throws {
        guard kind == .cursor, let screen = try? await cli.startupVisibleANSI(pane: pane) else { return }
        if let refusal = AgentComposerReadiness.startupRefusal(screen, kind: kind) { throw refusal }
    }

    private static func hasStarted(_ agent: Agent) -> Bool {
        // Only used for a new pane whose sole input is the native initial prompt.
        agent.status == .working || agent.status == .blocked || agent.status == .done
            || agent.completionSeq.map { $0 > 0 } == true
    }
}
