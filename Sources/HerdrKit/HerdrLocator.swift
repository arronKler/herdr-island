import Foundation
import IslandCore

public struct HerdrEnvironment: Sendable, Equatable {
    public let binary: URL
    public let socket: URL

    public init(binary: URL, socket: URL) {
        self.binary = binary
        self.socket = socket
    }
}

public enum HerdrLocator {
    public static func socketURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment["HERDR_SOCKET"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent(".config/herdr/herdr.sock")
    }

    public static func candidates(
        override: String?,
        environment: [String: String],
        home: URL
    ) -> [URL] {
        var paths: [String] = []
        if let override, !override.isEmpty {
            paths.append((override as NSString).expandingTildeInPath)
        }
        paths.append(home.appendingPathComponent(".local/bin/herdr").path)
        paths.append("/opt/homebrew/bin/herdr")
        paths.append("/usr/local/bin/herdr")
        if let searchPath = environment["PATH"] {
            for directory in searchPath.split(separator: ":") where !directory.isEmpty {
                paths.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("herdr").path)
            }
        }

        var seen: Set<String> = []
        return paths.compactMap { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }

    public static func resolve(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> HerdrEnvironment {
        let searched = candidates(override: override, environment: environment, home: home)
        for candidate in searched where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return HerdrEnvironment(
                binary: candidate,
                socket: socketURL(environment: environment, home: home)
            )
        }
        let listed = searched.map(\.path).joined(separator: "\n  ")
        throw BackendFailure(
            .binaryNotFound,
            "Could not find the herdr binary. Searched:\n  \(listed)"
        )
    }
}
