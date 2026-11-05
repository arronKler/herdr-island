import Foundation
import IslandCore

struct WireAgent: Decodable {
    let pane_id: String?
    let workspace_id: String?
    let tab_id: String?
    let agent: String?
    let display_agent: String?
    let agent_status: String?
    let terminal_title_stripped: String?
    let terminal_title: String?
    let cwd: String?
    let foreground_cwd: String?
    let completion_seq: UInt64?
    let state_change_seq: UInt64?
    let state_labels: [String: String]?
    let name: String?
    let focused: Bool?
    let revision: UInt64?
}

struct WireAgentList: Decodable {
    struct Result: Decodable {
        let agents: [WireAgent]
    }

    let result: Result
}

/// Parses the JSON emitted by `herdr agent list` into domain agents.
public func parseAgents(_ data: Data) throws -> [Agent] {
    let decoded: WireAgentList
    do {
        decoded = try JSONDecoder().decode(WireAgentList.self, from: data)
    } catch {
        throw BackendFailure(
            .decode,
            "Could not decode the herdr agent list: \(error.localizedDescription)"
        )
    }
    return decoded.result.agents.compactMap { $0.domainAgent() }
}

extension WireAgent {
    func domainAgent() -> Agent? {
        guard let paneID = trimmed(pane_id) else { return nil }

        let workspace = trimmed(workspace_id) ?? ""
        let directory = trimmed(foreground_cwd) ?? trimmed(cwd) ?? ""
        let cwdBasename = directory.isEmpty
            ? nil
            : URL(fileURLWithPath: directory).lastPathComponent
        let project = cwdBasename ?? (workspace.isEmpty ? "unknown" : workspace)

        let title = [terminal_title_stripped, terminal_title, cwdBasename]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? paneID

        let status = AgentStatus(rawValue: (agent_status ?? "").lowercased()) ?? .unknown
        let kind = trimmed(agent) ?? trimmed(display_agent)

        return Agent(
            pane: PaneID(paneID),
            workspace: workspace,
            tab: tab_id,
            kind: kind ?? "terminal",
            title: title,
            project: project,
            status: status,
            completionSeq: completion_seq,
            stateChangeSeq: state_change_seq ?? 0,
            labels: normalizedLabels(state_labels),
            name: trimmed(name)
        )
    }
}

public enum HerdrSocketPayload: Equatable, Sendable {
    case facts(AgentFacts)
    case rebuild
}

public enum HerdrWire {
    public static func decodeSocketEvent(_ data: Data, at: Date) -> HerdrSocketPayload? {
        guard let envelope = try? JSONDecoder().decode(WireSocketEnvelope.self, from: data) else {
            return nil
        }
        guard envelope.event == "pane_agent_status_changed"
                || envelope.event == "pane.agent_status_changed" else {
            return .rebuild
        }
        guard let payload = try? JSONDecoder().decode(WireAgentStatusEvent.self, from: data),
              let paneID = trimmed(payload.data.pane_id) else {
            return nil
        }
        let status = payload.data.agent_status.map {
            AgentStatus(rawValue: $0.lowercased()) ?? .unknown
        }
        return .facts(AgentFacts(
            pane: PaneID(paneID),
            status: status,
            title: trimmed(payload.data.title),
            kind: trimmed(payload.data.agent) ?? trimmed(payload.data.display_agent),
            labels: normalizedLabels(payload.data.state_labels),
            at: at
        ))
    }
}

private struct WireSocketEnvelope: Decodable {
    let event: String
}

private struct WireAgentStatusEvent: Decodable {
    struct Payload: Decodable {
        let pane_id: String?
        let agent_status: String?
        let agent: String?
        let display_agent: String?
        let title: String?
        let state_labels: [String: String]?
    }

    let data: Payload
}

private func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedLabels(_ labels: [String: String]?) -> [String: String] {
    guard let labels else { return [:] }
    var normalized: [String: String] = [:]
    for (key, value) in labels {
        guard let key = trimmed(key) else { continue }
        normalized[key] = value
    }
    return normalized
}
