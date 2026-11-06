import AppKit
import Foundation
import IslandCore

/// Explicit diagnostic mode for measuring the signed application's capture
/// identity. It never requests permission, starts an agent, or prunes captures.
enum WindowCaptureProbe {
    @MainActor
    static func run(windowID: UInt32) async -> Int32 {
        let start = ContinuousClock.now
        var result: [String: Any] = ["authorized": WindowCaptureService.isAuthorized,
                                     "bundle_id": Bundle.main.bundleIdentifier ?? "unbundled"]
        var code: Int32 = 1
        do {
            guard let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
                  let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw as CFDictionary) else {
                throw BackendFailure(.windowUnavailable, "Probe window is not available.")
            }
            let target = WindowTarget(windowID: windowID, ownerPID: pid.int32Value, appName: "Capture probe",
                bounds: ScreenCoordinates.appKitRect(fromQuartz: frame, primaryDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height))
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-capture-probe-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            switch await WindowCaptureService.capture(target, in: directory) {
            case .success(let path):
                result["png_bytes"] = try Data(contentsOf: URL(fileURLWithPath: path)).count
                result["success"] = true
                code = 0
            case .failure(let failure): throw failure
            }
        } catch {
            result["success"] = false
            result["error_kind"] = (error as? BackendFailure)?.kind.rawValue ?? "other"
            result["error"] = (error as? BackendFailure)?.message ?? error.localizedDescription
        }
        let duration = start.duration(to: .now).components
        result["duration_ms"] = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
        return code
    }
}
