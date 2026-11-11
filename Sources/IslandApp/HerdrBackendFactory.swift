import HerdrKit
import IslandCore

struct BackendAttachment: Sendable {
    let source: any AgentSource
    let actions: any AgentActions
}

enum InitialBackend: Sendable {
    case live(HerdrEnvironment)
    case unavailable(BackendFailure)
    case demo
}

protocol BackendFactory: Sendable {
    func makeInitialBackend(_ initial: InitialBackend, rules: IslandRules) -> BackendAttachment
    func makeBackend(for environment: HerdrEnvironment, rules: IslandRules) -> BackendAttachment
}

struct HerdrBackendFactory: BackendFactory {
    func makeInitialBackend(_ initial: InitialBackend, rules: IslandRules) -> BackendAttachment {
        switch initial {
        case .live(let environment):
            return makeBackend(for: environment, rules: rules)
        case .unavailable(let failure):
            let unavailable = UnavailableSource(failure: failure)
            return BackendAttachment(source: unavailable, actions: unavailable)
        case .demo:
            let demo = DemoSource()
            return BackendAttachment(source: demo, actions: demo)
        }
    }

    func makeBackend(for environment: HerdrEnvironment, rules: IslandRules) -> BackendAttachment {
        let cli = HerdrCLI(binary: environment.binary, socketURL: environment.socket)
        let service = HerdrService(
            cli: cli,
            socketURL: environment.socket,
            rules: rules
        ) { message in
            appLog("herdr: \(message)")
        }
        return BackendAttachment(source: service, actions: service)
    }
}
