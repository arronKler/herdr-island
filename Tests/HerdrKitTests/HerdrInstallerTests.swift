import CryptoKit
import Foundation
import XCTest
@testable import HerdrKit
import IslandCore

final class HerdrInstallerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdr-installer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testDecodesParallelManifestTables() throws {
        let bytes = Data("binary".utf8)
        let manifest = try HerdrInstallManifest.decode(makeManifest(
            sha256: ["macos-aarch64": sha256Hex(bytes)]
        ))
        XCTAssertEqual(manifest.version, "0.9.5")
        XCTAssertEqual(
            manifest.assets["macos-aarch64"],
            "https://example.test/herdr-macos-aarch64"
        )
        XCTAssertEqual(manifest.sha256["macos-aarch64"], sha256Hex(bytes))
    }

    func testSelectsAarch64AndX86Assets() throws {
        let arm = String(repeating: "a", count: 64)
        let intel = String(repeating: "b", count: 64)
        let manifest = try HerdrInstallManifest.decode(makeManifest(
            assets: [
                "macos-aarch64": "https://example.test/arm",
                "macos-x86_64": "https://example.test/intel",
            ],
            sha256: ["macos-aarch64": arm, "macos-x86_64": intel]
        ))

        let armAsset = try manifest.asset(for: .macosAArch64)
        XCTAssertEqual(armAsset.url.absoluteString, "https://example.test/arm")
        XCTAssertEqual(armAsset.sha256, arm)
        let intelAsset = try manifest.asset(for: .macosX86_64)
        XCTAssertEqual(intelAsset.url.absoluteString, "https://example.test/intel")
        XCTAssertEqual(intelAsset.sha256, intel)
    }

    func testMissingChecksumIsAssetMissing() throws {
        let manifest = try HerdrInstallManifest.decode(makeManifest(
            sha256: ["macos-x86_64": String(repeating: "a", count: 64)]
        ))
        XCTAssertThrowsError(try manifest.asset(for: .macosAArch64)) { error in
            XCTAssertEqual(error as? HerdrInstallError, .assetMissing("macos-aarch64"))
        }
    }

    func testMalformedChecksumIsManifestInvalid() {
        for checksum in ["abc", String(repeating: "a", count: 63), String(repeating: "g", count: 64)] {
            XCTAssertThrowsError(try HerdrInstallManifest.decode(makeManifest(
                sha256: ["macos-aarch64": checksum]
            )), "checksum \(checksum) should be rejected") { error in
                guard case .manifestInvalid = error as? HerdrInstallError else {
                    return XCTFail("expected manifestInvalid, got \(error)")
                }
            }
        }
    }

    func testUppercaseChecksumIsNormalized() throws {
        let checksum = String(repeating: "A", count: 64)
        let manifest = try HerdrInstallManifest.decode(makeManifest(
            sha256: ["macos-aarch64": checksum]
        ))
        XCTAssertEqual(try manifest.asset(for: .macosAArch64).sha256, checksum.lowercased())
    }

    func testNonHTTPSAssetIsRejected() {
        for url in ["http://example.test/herdr", "not a url"] {
            XCTAssertThrowsError(try HerdrInstallManifest.decode(makeManifest(
                assets: ["macos-aarch64": url],
                sha256: ["macos-aarch64": String(repeating: "a", count: 64)]
            )).asset(for: .macosAArch64), "asset \(url) should be rejected") { error in
                guard case .manifestInvalid = error as? HerdrInstallError else {
                    return XCTFail("expected manifestInvalid, got \(error)")
                }
            }
        }
    }

    func testPlatformSelection() {
        XCTAssertEqual(HerdrPlatform.current(machine: "arm64"), .macosAArch64)
        XCTAssertEqual(HerdrPlatform.current(machine: "aarch64"), .macosAArch64)
        XCTAssertEqual(HerdrPlatform.current(machine: "x86_64"), .macosX86_64)
        XCTAssertEqual(HerdrPlatform.current(machine: "amd64"), .macosX86_64)
        XCTAssertNil(HerdrPlatform.current(machine: "riscv64"))
        XCTAssertNil(HerdrPlatform.current(machine: "i386"))
    }

    func testInstallVerifiesChecksumAndPlacesAtomically() async throws {
        let bytes = Data("#!/bin/sh\necho herdr\n".utf8)
        let transport = StubTransport(
            manifest: manifest(for: bytes),
            asset: bytes
        )
        let installation = try await makeInstaller(transport: transport).install { _ in }

        XCTAssertEqual(installation.version, "0.9.5")
        XCTAssertEqual(installation.binary, installDirectory.appendingPathComponent("herdr"))
        XCTAssertEqual(try Data(contentsOf: installation.binary), bytes)
        let attributes = try FileManager.default.attributesOfItem(atPath: installation.binary.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testInstallReplacesAnExistingBinary() async throws {
        let bytes = Data("new binary".utf8)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try Data("old binary".utf8).write(to: installDirectory.appendingPathComponent("herdr"))

        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        let installation = try await makeInstaller(transport: transport).install { _ in }

        XCTAssertEqual(try Data(contentsOf: installation.binary), bytes)
    }

    func testInstallSkipsDownloadWhenDestinationMatches() async throws {
        let bytes = Data("already installed".utf8)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let destination = installDirectory.appendingPathComponent("herdr")
        try bytes.write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        let recorded = URLChecker()

        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        let installation = try await makeInstaller(transport: transport) { url in
            await recorded.record(url)
        }.install { _ in }

        XCTAssertEqual(transport.downloadCount, 0)
        XCTAssertEqual(installation.binary, destination)
        let verified = await recorded.urls
        XCTAssertEqual(verified, [destination])
    }

    func testChecksumMismatchLeavesNoDestination() async throws {
        let bytes = Data("tampered".utf8)
        let transport = StubTransport(
            manifest: makeManifest(sha256: ["macos-aarch64": String(repeating: "0", count: 64)]),
            asset: bytes
        )

        do {
            _ = try await makeInstaller(transport: transport).install { _ in }
            XCTFail("expected checksumMismatch")
        } catch {
            guard case .checksumMismatch = error as? HerdrInstallError else {
                return XCTFail("expected checksumMismatch, got \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: installDirectory.appendingPathComponent("herdr").path)
        )
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installDirectory.path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix("herdr-download-") })
    }

    func testDownloadFailureIsTyped() async throws {
        let bytes = Data("binary".utf8)
        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        transport.downloadError = URLError(.networkConnectionLost)

        do {
            _ = try await makeInstaller(transport: transport).install { _ in }
            XCTFail("expected downloadFailed")
        } catch {
            guard case .downloadFailed = error as? HerdrInstallError else {
                return XCTFail("expected downloadFailed, got \(error)")
            }
        }
    }

    func testPermissionDeniedIsTyped() async throws {
        try XCTSkipIf(getuid() == 0, "root can write a read-only directory")

        let readOnly = directory.appendingPathComponent("readonly", isDirectory: true)
        let installDirectory = readOnly.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: installDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installDirectory.path)
        }

        let bytes = Data("binary".utf8)
        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        let installer = HerdrInstaller(configuration: .init(
            manifestURL: URL(string: "https://example.test/latest.json")!,
            installDirectory: installDirectory,
            platform: .macosAArch64,
            transport: transport,
            verify: { _ in }
        ))

        do {
            _ = try await installer.install { _ in }
            XCTFail("expected permissionDenied")
        } catch {
            guard case .permissionDenied = error as? HerdrInstallError else {
                return XCTFail("expected permissionDenied, got \(error)")
            }
        }
    }

    func testProgressOrderAndFractions() async throws {
        let bytes = Data("binary".utf8)
        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        transport.fractions = [0.25, 0.5, 1.0]
        let recorder = ProgressRecorder()

        _ = try await makeInstaller(transport: transport).install { progress in
            await recorder.record(progress)
        }

        let events = await recorder.events
        XCTAssertEqual(events.map(stageName), [
            "resolving", "downloading", "downloading", "downloading",
            "verifying", "installing", "finished",
        ])
        let fractions = events.compactMap { progress -> Double? in
            if case .downloading(_, let fraction) = progress { return fraction }
            return nil
        }
        XCTAssertEqual(fractions, [0.25, 0.5, 1.0])
    }

    func testInstalledBinaryIsFoundByLocator() async throws {
        let bytes = Data("binary".utf8)
        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        let installation = try await makeInstaller(transport: transport).install { _ in }

        let resolved = try HerdrLocator.resolve(
            override: nil,
            environment: [:],
            home: directory
        )
        XCTAssertEqual(resolved.binary, installation.binary)
    }

    func testCancellationIsTyped() async throws {
        let bytes = Data("binary".utf8)
        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        transport.downloadError = CancellationError()

        do {
            _ = try await makeInstaller(transport: transport).install { _ in }
            XCTFail("expected cancelled")
        } catch {
            XCTAssertEqual(error as? HerdrInstallError, .cancelled)
        }
    }

    func testManifestCancellationIsTyped() async throws {
        let bytes = Data("binary".utf8)
        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        transport.manifestError = CancellationError()

        do {
            _ = try await makeInstaller(transport: transport).install { _ in }
            XCTFail("expected cancelled")
        } catch {
            XCTAssertEqual(error as? HerdrInstallError, .cancelled)
        }
    }

    func testVerificationFailureIsTyped() async throws {
        let bytes = Data("binary".utf8)
        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        let destination = installDirectory.appendingPathComponent("herdr")

        do {
            _ = try await makeInstaller(transport: transport) { url in
                XCTAssertEqual(url, destination)
                throw HerdrInstallError.verificationFailed("smoke test failed")
            }.install { _ in }
            XCTFail("expected verificationFailed")
        } catch {
            guard case .verificationFailed = error as? HerdrInstallError else {
                return XCTFail("expected verificationFailed, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    func testVerificationFailureDropsTheMatchingBinarySoRetryDownloads() async throws {
        let bytes = Data("binary".utf8)
        let destination = installDirectory.appendingPathComponent("herdr")
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try bytes.write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)

        let transport = StubTransport(manifest: manifest(for: bytes), asset: bytes)
        do {
            _ = try await makeInstaller(transport: transport) { _ in
                throw HerdrInstallError.verificationFailed("broken")
            }.install { _ in }
            XCTFail("expected verificationFailed")
        } catch {
            guard case .verificationFailed = error as? HerdrInstallError else {
                return XCTFail("expected verificationFailed, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(transport.downloadCount, 0)

        _ = try await makeInstaller(transport: transport).install { _ in }
        XCTAssertEqual(transport.downloadCount, 1)
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    func testLiveInstallWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["ISLAND_LIVE_INSTALL"] == "1" else {
            throw XCTSkip("set ISLAND_LIVE_INSTALL=1 to run the live installer test")
        }

        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdr-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let installer = HerdrInstaller(configuration: .live(home: home))
        let installation = try await installer.install { _ in }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installation.binary.path))
        XCTAssertTrue(installation.binary.path.hasPrefix(home.path))

        let process = Process()
        process.executableURL = installation.binary
        process.arguments = ["--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private var installDirectory: URL {
        directory.appendingPathComponent(".local/bin", isDirectory: true)
    }

    private func makeInstaller(
        transport: StubTransport,
        verify: @escaping @Sendable (URL) async throws -> Void = { _ in }
    ) -> HerdrInstaller {
        HerdrInstaller(configuration: .init(
            manifestURL: URL(string: "https://example.test/latest.json")!,
            installDirectory: installDirectory,
            platform: .macosAArch64,
            transport: transport,
            verify: verify
        ))
    }

    private func manifest(for bytes: Data) -> Data {
        makeManifest(sha256: ["macos-aarch64": sha256Hex(bytes)])
    }

    private func makeManifest(
        version: String = "0.9.5",
        assets: [String: String] = [
            "macos-aarch64": "https://example.test/herdr-macos-aarch64"
        ],
        sha256: [String: String]
    ) -> Data {
        let object: [String: Any] = [
            "version": version,
            "protocol": 22,
            "endpoint_generation": 1,
            "assets": assets,
            "sha256": sha256,
            "notes": "ignored",
            "releases": ["0.9.5": [String: Any]()],
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func stageName(_ progress: HerdrInstallProgress) -> String {
        switch progress {
        case .resolving: "resolving"
        case .downloading: "downloading"
        case .verifying: "verifying"
        case .installing: "installing"
        case .finished: "finished"
        }
    }
}

private final class StubTransport: HerdrInstallTransport, @unchecked Sendable {
    let manifestData: Data
    let assetData: Data
    var manifestError: Error?
    var downloadError: Error?
    var fractions: [Double?] = [0.25, 0.5, 1.0]

    private let lock = NSLock()
    private var downloads = 0

    init(manifest: Data, asset: Data) {
        manifestData = manifest
        assetData = asset
    }

    var downloadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return downloads
    }

    func data(from url: URL) async throws -> Data {
        if let manifestError { throw manifestError }
        return manifestData
    }

    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws {
        lock.lock()
        downloads += 1
        lock.unlock()
        if let downloadError { throw downloadError }
        try assetData.write(to: destination)
        for fraction in fractions {
            await progress(fraction)
        }
    }
}

private actor ProgressRecorder {
    private(set) var events: [HerdrInstallProgress] = []

    func record(_ event: HerdrInstallProgress) {
        events.append(event)
    }
}

private actor URLChecker {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }
}
