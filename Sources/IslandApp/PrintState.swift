import Foundation
import HerdrKit
import IslandCore

enum PrintState {
    static func run(options: LaunchOptions) async -> Int32 {
        var rules = IslandSettings.rules()
        if options.noAutoExpand {
            rules.autoExpandOnBlocked = false
            rules.autoExpandOnCompletion = false
        }

        let environment: HerdrEnvironment
        do {
            environment = try HerdrLocator.resolve()
        } catch {
            return emitError(error)
        }
        appLog("print-state binary=\(environment.binary.path) socket=\(environment.socket.path)")

        let cli = HerdrCLI(binary: environment.binary)
        do {
            let agents = try await cli.listAgents()
            var state = IslandState(rules: rules)
            let snapshot = AgentSnapshot(generation: 1, sampledAt: Date(), agents: agents)
            _ = IslandReducer.reduce(&state, .snapshot(snapshot), now: Date())
            let presentation = IslandPresenter.present(state, now: Date())
            emit(presentation)
            return 0
        } catch {
            return emitError(error)
        }
    }

    private static func emit(_ presentation: IslandPresentation) {
        let payload: [String: Any] = [
            "health": healthName(presentation.health),
            "headline": headlinePayload(presentation.headline),
            "summary": [
                "working": presentation.summary.working,
                "blocked": presentation.summary.blocked,
                "completed": presentation.summary.completed,
                "idle": presentation.summary.idle,
                "total": presentation.summary.total,
            ],
            "selected": presentation.selected.map(rowPayload) ?? NSNull(),
            "rows": presentation.rows.map(rowPayload),
            "banner": presentation.banner.map(bannerPayload) ?? NSNull(),
        ]
        write(payload)
    }

    private static func emitError(_ error: Error) -> Int32 {
        let failure = (error as? BackendFailure)
            ?? BackendFailure(.other, error.localizedDescription)
        appLog("print-state failed: \(failure.message)")
        write(["kind": failure.kind.rawValue, "error": failure.message])
        return 1
    }

    private static func write(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func rowPayload(_ row: AgentRow) -> [String: Any] {
        var payload: [String: Any] = [
            "id": row.id.rawValue,
            "title": row.title,
            "project": row.project,
            "kind": row.kind,
            "status": row.status.rawValue,
            "isSelected": row.isSelected,
            "isPendingCompletion": row.isPendingCompletion,
            "acceptsPrompt": row.acceptsPrompt,
        ]
        payload["promptRefusal"] = row.promptRefusal ?? NSNull()
        return payload
    }

    private static func bannerPayload(_ banner: Banner) -> [String: Any] {
        var payload: [String: Any] = [
            "text": banner.text,
            "isError": banner.isError,
            "source": bannerSourceName(banner.source),
        ]
        switch banner.action {
        case .openAutomationSettings: payload["action"] = "openAutomationSettings"
        case .openScreenRecordingSettings: payload["action"] = "openScreenRecordingSettings"
        case .openSettings: payload["action"] = "openSettings"
        case nil: payload["action"] = NSNull()
        }
        return payload
    }

    private static func headlinePayload(_ headline: IslandHeadline) -> [String: Any] {
        switch headline {
        case .starting: ["kind": "starting"]
        case .stale: ["kind": "stale"]
        case .blocked(let count): ["kind": "blocked", "count": count]
        case .completed(let count): ["kind": "completed", "count": count]
        case .working(let count): ["kind": "working", "count": count]
        case .empty: ["kind": "empty"]
        }
    }

    private static func healthName(_ health: BackendHealth) -> String {
        switch health {
        case .starting: "starting"
        case .ok: "ok"
        case .stale: "stale"
        case .failed: "failed"
        }
    }

    private static func bannerSourceName(_ source: Banner.Source) -> String {
        switch source {
        case .health: "health"
        case .jump: "jump"
        case .send: "send"
        case .preview: "preview"
        case .info: "info"
        }
    }
}
