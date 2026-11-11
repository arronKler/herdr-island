import Foundation

public struct HerdrEnvironment: Sendable, Equatable {
    public let binary: URL
    public let socket: URL

    public init(binary: URL, socket: URL) {
        self.binary = binary
        self.socket = socket
    }
}

public enum HerdrSetup: Sendable, Equatable {
    /// A usable backend. `.ready(nil)` means a source with no
    /// terminal-capable environment, which is the demo source.
    case ready(HerdrEnvironment?)
    case missing(SetupFailure)
    case working(SetupStage)
    case failed(SetupFailure)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var environment: HerdrEnvironment? {
        if case .ready(let environment) = self { return environment }
        return nil
    }
}

public enum SetupStage: Sendable, Equatable {
    case resolving
    case downloading(version: String, fraction: Double?)
    case verifying(version: String)
    case installing(version: String)
    case connecting
    case redetecting
}

public struct SetupFailure: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case binaryMissing
        case binaryStillMissing
        case manifestUnavailable
        case manifestInvalid
        case platformUnsupported
        case assetMissing
        case downloadFailed
        case checksumMismatch
        case installDirectoryUnavailable
        case permissionDenied
        case placementFailed
        case verificationFailed
        case cancelled
        case other
    }

    public let kind: Kind
    /// Technical text for the log. Not shown as primary UI copy.
    public let detail: String

    public init(_ kind: Kind, detail: String = "") {
        self.kind = kind
        self.detail = detail
    }

    public init(_ failure: BackendFailure) {
        self.init(
            failure.kind == .binaryNotFound ? .binaryMissing : .other,
            detail: failure.message
        )
    }

    /// Chinese, one sentence, written for the card.
    public var userMessage: String {
        switch kind {
        case .binaryMissing: "没有找到 Herdr。"
        case .binaryStillMissing: "仍然没有找到 Herdr。请确认安装命令已经完成。"
        case .manifestUnavailable: "无法获取 Herdr 的版本信息。请检查网络后重试。"
        case .manifestInvalid: "Herdr 的版本信息不完整，暂时无法自动安装。请手动安装。"
        case .platformUnsupported: "这台 Mac 的架构暂不受支持。请查看安装文档。"
        case .assetMissing: "安装清单里没有适合这台 Mac 的版本。请手动安装。"
        case .downloadFailed: "下载安装包失败。请检查网络后重试。"
        case .checksumMismatch: "安装包校验失败，已丢弃这次下载。请重试。"
        case .installDirectoryUnavailable: "无法创建安装目录 ~/.local/bin。请手动安装。"
        case .permissionDenied: "没有权限写入安装目录。请在终端手动安装，或检查 ~/.local/bin 的权限。"
        case .placementFailed: "无法写入 Herdr 可执行文件。请手动安装。"
        case .verificationFailed: "安装完成，但没有找到可用的 Herdr。请手动安装后重新检测。"
        case .cancelled: "安装已取消。"
        case .other: "自动安装没有完成。请手动安装后重新检测。"
        }
    }
}

public enum SetupEvent: Sendable, Equatable {
    case installRequested
    case redetectRequested
    case progress(SetupStage)
    case failed(SetupFailure)
    case installed(HerdrEnvironment)
}
