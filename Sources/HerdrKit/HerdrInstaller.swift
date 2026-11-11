import CryptoKit
import Darwin
import Foundation
import IslandCore

public enum HerdrPlatform: String, Sendable {
    case macosAArch64 = "macos-aarch64"
    case macosX86_64 = "macos-x86_64"

    public static func current() -> HerdrPlatform? {
        current(machine: HerdrMachine.name)
    }

    static func current(machine: String) -> HerdrPlatform? {
        switch machine.lowercased() {
        case "arm64", "aarch64": .macosAArch64
        case "x86_64", "amd64": .macosX86_64
        default: nil
        }
    }
}

enum HerdrMachine {
    static var name: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

public struct HerdrInstallation: Sendable, Equatable {
    public let version: String
    public let binary: URL

    public init(version: String, binary: URL) {
        self.version = version
        self.binary = binary
    }
}

public enum HerdrInstallProgress: Sendable, Equatable {
    case resolving
    case downloading(version: String, fraction: Double?)
    case verifying(version: String)
    case installing(version: String)
    case finished(version: String)
}

public protocol HerdrInstalling: Sendable {
    func install(
        progress: @escaping @Sendable (HerdrInstallProgress) async -> Void
    ) async throws -> HerdrInstallation
}

public protocol HerdrInstallTransport: Sendable {
    func data(from url: URL) async throws -> Data
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws
}

public enum HerdrInstallError: Error, Sendable, Equatable {
    case manifestUnavailable(String)
    case manifestInvalid(String)
    case platformUnsupported(String)
    case assetMissing(String)
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case installDirectoryUnavailable(String)
    case permissionDenied(String)
    case placementFailed(String)
    case verificationFailed(String)
    case cancelled
}

public extension HerdrInstallError {
    var setupFailure: SetupFailure {
        switch self {
        case .manifestUnavailable(let detail): SetupFailure(.manifestUnavailable, detail: detail)
        case .manifestInvalid(let detail): SetupFailure(.manifestInvalid, detail: detail)
        case .platformUnsupported(let detail): SetupFailure(.platformUnsupported, detail: detail)
        case .assetMissing(let detail): SetupFailure(.assetMissing, detail: detail)
        case .downloadFailed(let detail): SetupFailure(.downloadFailed, detail: detail)
        case .checksumMismatch(let expected, let actual):
            SetupFailure(.checksumMismatch, detail: "expected \(expected), got \(actual)")
        case .installDirectoryUnavailable(let detail):
            SetupFailure(.installDirectoryUnavailable, detail: detail)
        case .permissionDenied(let detail): SetupFailure(.permissionDenied, detail: detail)
        case .placementFailed(let detail): SetupFailure(.placementFailed, detail: detail)
        case .verificationFailed(let detail): SetupFailure(.verificationFailed, detail: detail)
        case .cancelled: SetupFailure(.cancelled)
        }
    }
}

public extension HerdrInstallProgress {
    var setupStage: SetupStage {
        switch self {
        case .resolving: .resolving
        case .downloading(let version, let fraction): .downloading(version: version, fraction: fraction)
        case .verifying(let version): .verifying(version: version)
        case .installing(let version): .installing(version: version)
        case .finished: .connecting
        }
    }
}

public struct HerdrInstaller: HerdrInstalling {
    public struct Configuration: Sendable {
        public var manifestURL: URL
        public var installDirectory: URL
        public var platform: HerdrPlatform?
        public var transport: any HerdrInstallTransport
        public var verify: @Sendable (URL) async throws -> Void

        public init(
            manifestURL: URL,
            installDirectory: URL,
            platform: HerdrPlatform?,
            transport: any HerdrInstallTransport,
            verify: @escaping @Sendable (URL) async throws -> Void = { try await HerdrInstaller.runVersionCheck(at: $0) }
        ) {
            self.manifestURL = manifestURL
            self.installDirectory = installDirectory
            self.platform = platform
            self.transport = transport
            self.verify = verify
        }

        public static func live(
            home: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> Configuration {
            Configuration(
                manifestURL: URL(string: "https://herdr.dev/latest.json")!,
                installDirectory: HerdrLocator.defaultInstallDirectory(home: home),
                platform: HerdrPlatform.current(),
                transport: URLSessionInstallTransport()
            )
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .live()) {
        self.configuration = configuration
    }

    public func install(
        progress: @escaping @Sendable (HerdrInstallProgress) async -> Void
    ) async throws -> HerdrInstallation {
        await progress(.resolving)
        try checkpoint()

        let manifestData: Data
        do {
            manifestData = try await configuration.transport.data(from: configuration.manifestURL)
        } catch is CancellationError {
            throw HerdrInstallError.cancelled
        } catch let error as HerdrInstallError {
            throw error
        } catch {
            throw HerdrInstallError.manifestUnavailable(error.localizedDescription)
        }
        let manifest = try HerdrInstallManifest.decode(manifestData)

        guard let platform = configuration.platform else {
            throw HerdrInstallError.platformUnsupported(HerdrMachine.name)
        }
        let asset = try manifest.asset(for: platform)

        let directory = configuration.installDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw HerdrInstallError.installDirectoryUnavailable(error.localizedDescription)
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw HerdrInstallError.permissionDenied(directory.path)
        }

        let destination = directory.appendingPathComponent("herdr")
        if try await reuseVerifiedBinary(at: destination, expectedSHA256: asset.sha256) {
            await progress(.finished(version: manifest.version))
            return HerdrInstallation(version: manifest.version, binary: destination)
        }

        let temporary = directory.appendingPathComponent("herdr-download-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try checkpoint()
        do {
            try await configuration.transport.download(
                from: asset.url,
                to: temporary
            ) { fraction in
                await progress(.downloading(version: manifest.version, fraction: fraction))
            }
        } catch is CancellationError {
            throw HerdrInstallError.cancelled
        } catch let error as HerdrInstallError {
            throw error
        } catch {
            throw HerdrInstallError.downloadFailed(error.localizedDescription)
        }

        try checkpoint()
        await progress(.verifying(version: manifest.version))
        let actual: String
        do {
            actual = try HerdrDigest.hex(ofFileAt: temporary)
        } catch {
            throw HerdrInstallError.downloadFailed(error.localizedDescription)
        }
        guard actual == asset.sha256 else {
            throw HerdrInstallError.checksumMismatch(expected: asset.sha256, actual: actual)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: temporary.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw HerdrInstallError.placementFailed("downloaded file is not a regular file")
        }

        try checkpoint()
        await progress(.installing(version: manifest.version))
        guard chmod(temporary.path, 0o755) == 0 else {
            throw HerdrInstallError.placementFailed(Self.errnoText("chmod"))
        }
        guard rename(temporary.path, destination.path) == 0 else {
            throw HerdrInstallError.placementFailed(Self.errnoText("rename"))
        }
        guard FileManager.default.isExecutableFile(atPath: destination.path) else {
            throw HerdrInstallError.placementFailed("installed file is not executable")
        }

        try await verifyInstalled(at: destination)
        await progress(.finished(version: manifest.version))
        return HerdrInstallation(version: manifest.version, binary: destination)
    }

    public static func runVersionCheck(at binary: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            VersionCheckRunner().run(binary: binary, continuation: continuation)
        }
    }

    private func reuseVerifiedBinary(
        at destination: URL,
        expectedSHA256: String
    ) async throws -> Bool {
        guard FileManager.default.isExecutableFile(atPath: destination.path),
              (try? HerdrDigest.hex(ofFileAt: destination)) == expectedSHA256 else {
            return false
        }
        do {
            try await verifyInstalled(at: destination)
            return true
        } catch {
            if !Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error
        }
    }

    private func verifyInstalled(at binary: URL) async throws {
        do {
            try await configuration.verify(binary)
        } catch is CancellationError {
            throw HerdrInstallError.cancelled
        } catch let error as HerdrInstallError {
            throw error
        } catch {
            throw HerdrInstallError.verificationFailed(error.localizedDescription)
        }
    }

    private func checkpoint() throws {
        if Task.isCancelled { throw HerdrInstallError.cancelled }
    }

    private static func errnoText(_ operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }
}

struct HerdrInstallManifest: Sendable, Equatable {
    let version: String
    let assets: [String: String]
    let sha256: [String: String]

    static func decode(_ data: Data) throws -> HerdrInstallManifest {
        struct Raw: Decodable {
            let version: String?
            let assets: [String: String]?
            let sha256: [String: String]?
        }

        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw HerdrInstallError.manifestInvalid(error.localizedDescription)
        }
        guard let version = raw.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else {
            throw HerdrInstallError.manifestInvalid("missing version")
        }
        guard let assets = raw.assets else {
            throw HerdrInstallError.manifestInvalid("missing assets")
        }
        guard let sha256 = raw.sha256 else {
            throw HerdrInstallError.manifestInvalid("missing sha256")
        }
        for (key, value) in sha256 where !HerdrDigest.isValidHex(value) {
            throw HerdrInstallError.manifestInvalid("invalid checksum for \(key)")
        }
        return HerdrInstallManifest(
            version: version,
            assets: assets,
            sha256: sha256
        )
    }

    func asset(for platform: HerdrPlatform) throws -> HerdrInstallAsset {
        guard let urlString = assets[platform.rawValue],
              let checksum = sha256[platform.rawValue] else {
            throw HerdrInstallError.assetMissing(platform.rawValue)
        }
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else {
            throw HerdrInstallError.manifestInvalid("asset URL for \(platform.rawValue) must be https")
        }
        return HerdrInstallAsset(url: url, sha256: checksum.lowercased())
    }
}

struct HerdrInstallAsset: Sendable, Equatable {
    let url: URL
    let sha256: String
}

enum HerdrDigest {
    static func hex(ofFileAt url: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func isValidHex(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}

final class URLSessionInstallTransport: NSObject, HerdrInstallTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let delegateQueue: OperationQueue
    private var session: URLSession!
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var destinations: [Int: URL] = [:]
    private var progressHandlers: [Int: @Sendable (Double?) async -> Void] = [:]
    private var writeErrors: [Int: HerdrInstallError] = [:]

    override init() {
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "herdr.install.transport"
        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw error
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HerdrInstallError.manifestUnavailable("HTTP \(http.statusCode)")
        }
        return data
    }

    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws {
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                continuations[task.taskIdentifier] = continuation
                destinations[task.taskIdentifier] = destination
                progressHandlers[task.taskIdentifier] = progress
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

extension URLSessionInstallTransport: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let handler = progressHandlers[downloadTask.taskIdentifier]
        lock.unlock()
        guard let handler else { return }
        let fraction = totalBytesExpectedToWrite > 0
            ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            : nil
        Task { await handler(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let destination = destinations[downloadTask.taskIdentifier]
        lock.unlock()
        guard let destination else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: location, to: destination)
        } catch {
            lock.lock()
            writeErrors[downloadTask.taskIdentifier] = .downloadFailed(error.localizedDescription)
            lock.unlock()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: task.taskIdentifier)
        let writeError = writeErrors.removeValue(forKey: task.taskIdentifier)
        destinations[task.taskIdentifier] = nil
        progressHandlers[task.taskIdentifier] = nil
        lock.unlock()
        guard let continuation else { return }

        if let error {
            if (error as? URLError)?.code == .cancelled {
                continuation.resume(throwing: HerdrInstallError.cancelled)
            } else {
                continuation.resume(throwing: HerdrInstallError.downloadFailed(error.localizedDescription))
            }
            return
        }
        if let writeError {
            continuation.resume(throwing: writeError)
            return
        }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation.resume(throwing: HerdrInstallError.downloadFailed("HTTP \(http.statusCode)"))
            return
        }
        continuation.resume()
    }
}

private final class VersionCheckRunner: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var claimed = false

    func run(binary: URL, continuation: CheckedContinuation<Void, Error>) {
        process.executableURL = binary
        process.arguments = ["--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [self] exited in
            guard claim() else { return }
            if exited.terminationStatus == 0 {
                continuation.resume()
            } else {
                continuation.resume(throwing: HerdrInstallError.verificationFailed(
                    "herdr --version exited with status \(exited.terminationStatus)"
                ))
            }
        }
        do {
            try process.run()
        } catch {
            guard claim() else { return }
            continuation.resume(throwing: HerdrInstallError.verificationFailed(
                "could not launch installed binary: \(error.localizedDescription)"
            ))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [self] in
            guard claim() else { return }
            process.terminate()
            continuation.resume(throwing: HerdrInstallError.verificationFailed(
                "herdr --version timed out"
            ))
        }
    }

    private func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
