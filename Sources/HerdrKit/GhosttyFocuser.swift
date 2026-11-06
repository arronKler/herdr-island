import AppKit
import Darwin
import Foundation
import IslandCore

public struct GhosttyFocuser: Sendable {
    public enum Target: Sendable, Equatable {
        case exactTerminal(tty: String)
        case activatedGhostty
    }

    private let herdrBinary: URL
    private let log: @Sendable (String) -> Void
    private static let queue = DispatchQueue(label: "HerdrIsland.GhosttyFocus", qos: .userInitiated)

    public init(herdrBinary: URL, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.herdrBinary = herdrBinary
        self.log = log
    }

    public func focusHerdrTUI() async -> Result<Target, BackendFailure> {
        guard let applicationURL = await Self.ghosttyURL() else {
            return .failure(BackendFailure(
                .ghosttyNotFound,
                "Ghostty is not installed. The pane was selected in Herdr."
            ))
        }
        let path = herdrBinary.resolvingSymlinksInPath().path
        let outcome: Result<Target, BackendFailure> = await withCheckedContinuation { continuation in
            Self.queue.async {
                // No shell process, script compilation, or Apple-event wait runs
                // on the UI thread. Resolve fresh on every jump: a TTY can be
                // reused after a terminal closes or Ghostty restarts.
                let ttys = Self.herdrTTYs(herdrPath: path)
                log("herdr TUI ttys: \(ttys.joined(separator: ", "))")
                for tty in ttys {
                    do {
                        guard let terminal = try GhosttyAppleEvents.terminal(tty: tty) else { continue }
                        try GhosttyAppleEvents.focus(terminal)
                        continuation.resume(returning: .success(.exactTerminal(tty: tty)))
                        return
                    } catch let failure as BackendFailure {
                        if [.automationDenied, .timeout, .ghosttyNotFound].contains(failure.kind) {
                            continuation.resume(returning: .failure(failure))
                            return
                        }
                        log("no Ghostty terminal for \(tty): \(failure.message)")
                    } catch {
                        log("could not resolve Ghostty terminal: \(error.localizedDescription)")
                    }
                }
                do {
                    try GhosttyAppleEvents.activate()
                    continuation.resume(returning: .success(.activatedGhostty))
                } catch let failure as BackendFailure {
                    continuation.resume(returning: .failure(failure))
                } catch {
                    continuation.resume(returning: .failure(BackendFailure(.other, error.localizedDescription)))
                }
            }
        }
        if case .failure(let failure) = outcome, failure.kind == .ghosttyNotFound {
            // AppleScript used to launch a stopped application implicitly.
            // Keep that behavior without requiring a script on the main thread.
            return await Self.launchGhostty(at: applicationURL)
        }
        return outcome
    }

    /// Read process metadata in one kernel snapshot, then inspect arguments only
    /// for matching executables. `ps ... command` fetches arguments/environment
    /// for every process, which dominates the old jump path on a busy desktop.
    static func herdrTTYs(herdrPath: String) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 128)
        var loaded = false
        // A process may start between the size query and the actual snapshot.
        for _ in 0..<3 {
            size = processes.count * stride
            if sysctl(&mib, UInt32(mib.count), &processes, &size, nil, 0) == 0 {
                loaded = true
                break
            }
            guard errno == ENOMEM else { return [] }
            processes = [kinfo_proc](repeating: kinfo_proc(), count: processes.count * 2)
        }
        guard loaded else { return [] }
        var result: [String] = []
        var seen: Set<String> = []
        for var process in processes.prefix(size / stride).sorted(by: { $0.kp_proc.p_pid < $1.kp_proc.p_pid }) {
            let name = withUnsafeBytes(of: &process.kp_proc.p_comm) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            guard name == "herdr", process.kp_eproc.e_tdev != dev_t(-1) else { continue }
            let pid = process.kp_proc.p_pid
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                  isHerdrTUI(executablePath: String(cString: path),
                             argumentCount: argumentCount(pid: pid), herdrPath: herdrPath) else { continue }
            var device = [CChar](repeating: 0, count: 1_024)
            guard devname_r(process.kp_eproc.e_tdev, S_IFCHR, &device, Int32(device.count)) != nil else { continue }
            let tty = "/dev/" + String(cString: device)
            if seen.insert(tty).inserted { result.append(tty) }
        }
        return result
    }

    static func isHerdrTUI(executablePath: String, argumentCount: Int32?, herdrPath: String) -> Bool {
        guard argumentCount == 1 else { return false }
        return URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
            == URL(fileURLWithPath: herdrPath).resolvingSymlinksInPath()
    }

    private static func argumentCount(pid: pid_t) -> Int32? {
        var maxMIB = [CTL_KERN, KERN_ARGMAX]
        var maximum: Int32 = 0
        var maxSize = MemoryLayout<Int32>.size
        guard sysctl(&maxMIB, UInt32(maxMIB.count), &maximum, &maxSize, nil, 0) == 0,
              maximum >= MemoryLayout<Int32>.size else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(maximum))
        var size = bytes.count
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, UInt32(mib.count), &bytes, &size, nil, 0) == 0,
              size >= MemoryLayout<Int32>.size else { return nil }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    }

    static func errorKind(number: Int, message: String) -> BackendFailure {
        let lower = message.lowercased()
        if number == -1743 || lower.contains("not authorized") || lower.contains("automation") {
            return BackendFailure(
                .automationDenied,
                "Automation permission for Ghostty is required. Allow Herdr Island in System Settings > Privacy & Security > Automation."
            )
        }
        if number == -1728 { return BackendFailure(.paneUnavailable, message) }
        if number == -600 || lower.contains("not running") {
            return BackendFailure(.ghosttyNotFound, "Ghostty is not running.")
        }
        if number == -1712 { return BackendFailure(.timeout, "Ghostty did not respond to the focus request.") }
        return BackendFailure(.other, message)
    }

    @MainActor
    private static func ghosttyURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")
    }

    @MainActor
    private static func launchGhostty(at url: URL) async -> Result<Target, BackendFailure> {
        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(returning: .failure(BackendFailure(.ghosttyNotFound, error.localizedDescription)))
                } else {
                    continuation.resume(returning: .success(.activatedGhostty))
                }
            }
        }
    }
}

/// These are the public four-character codes in Ghostty.sdef. Constructing the
/// Apple events directly avoids reloading/compiling its scripting dictionary on
/// every jump. Descriptors stay local to the serial focus queue.
enum GhosttyAppleEvents {
    static func code(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func terminalQuery(tty: String) -> NSAppleEventDescriptor {
        let current = NSAppleEventDescriptor(descriptorType: code("exmn"), data: Data())!
        let comparison = NSAppleEventDescriptor.record()
        comparison.setDescriptor(NSAppleEventDescriptor(enumCode: code("=   ")), forKeyword: code("relo"))
        comparison.setDescriptor(object(want: "prop", form: "prop",
                                        data: NSAppleEventDescriptor(typeCode: code("Gtty")), from: current),
                                 forKeyword: code("obj1"))
        // A string descriptor carries quotes/backslashes literally; there is no
        // generated script source or interpolation to escape.
        comparison.setDescriptor(NSAppleEventDescriptor(string: tty), forKeyword: code("obj2"))
        return object(want: "Gtrm", form: "test", data: comparison.coerce(toDescriptorType: code("cmpd"))!)
    }

    static func terminal(tty: String) throws -> NSAppleEventDescriptor? {
        let reply = try send(eventClass: "core", eventID: "getd", directObject: terminalQuery(tty: tty))
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else { return nil }
        // Ghostty returns stable terminal-ID specifiers. Using one of these for
        // focus avoids an index selecting another terminal after a tab closes.
        if result.descriptorType == code("list") { return result.atIndex(1) }
        return result.descriptorType == code("obj ") ? result : nil
    }

    static func focus(_ terminal: NSAppleEventDescriptor) throws {
        _ = try send(eventClass: "Ghst", eventID: "Fcus", directObject: terminal)
    }

    static func activate() throws {
        _ = try send(eventClass: "misc", eventID: "actv")
    }

    static func replyFailure(_ reply: NSAppleEventDescriptor) -> BackendFailure? {
        guard let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 else { return nil }
        return GhosttyFocuser.errorKind(number: Int(error.int32Value),
                                       message: reply.paramDescriptor(forKeyword: code("errs"))?.stringValue
                                        ?? "Could not focus Ghostty.")
    }

    private static func send(eventClass: String, eventID: String,
                             directObject: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID),
                                          targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.mitchellh.ghostty"),
                                          returnID: -1, transactionID: 0)
        if let directObject { event.setParam(directObject, forKeyword: code("----")) }
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract, .dontRecord], timeout: 2)
        } catch let error as NSError {
            throw GhosttyFocuser.errorKind(number: error.code, message: error.localizedDescription)
        }
        if let failure = replyFailure(reply) { throw failure }
        return reply
    }

    private static func object(want: String, form: String, data: NSAppleEventDescriptor,
                               from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(data, forKeyword: code("seld"))
        record.setDescriptor(from, forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj "))!
    }
}
