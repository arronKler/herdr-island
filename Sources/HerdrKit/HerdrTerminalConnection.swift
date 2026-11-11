import Darwin
import Foundation

/// Owns one direct-terminal socket. Closing it never terminates the shell.
final class HerdrTerminalConnection: @unchecked Sendable {
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "local.herdr.island.terminal-wire")
    private var descriptor: Int32 = -1
    private var stopped = false
    private let deliver: @Sendable ([HerdrTerminalEvent]) -> Void

    init(deliver: @escaping @Sendable ([HerdrTerminalEvent]) -> Void) { self.deliver = deliver }

    func start(socket api: URL, pane: String, columns: Int, rows: Int, takeover: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let path = api.deletingLastPathComponent().appendingPathComponent(api.deletingPathExtension().lastPathComponent + "-client.sock").path
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                let encoded = Array(path.utf8) + [0]
                guard encoded.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                    throw HerdrTerminalWire.Failure("Herdr socket 路径过长。")
                }
                withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: encoded) }
                let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { throw posixFailure() }
                defer {
                    lock.lock(); descriptor = -1; lock.unlock()
                    Darwin.close(fd)
                }
                var noSignal: Int32 = 1
                _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                _ = fcntl(fd, F_SETFL, O_NONBLOCK)
                lock.lock(); descriptor = fd; let cancelled = stopped; lock.unlock()
                if cancelled { return }
                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
                }
                if result != 0 {
                    guard errno == EINPROGRESS else { throw posixFailure() }
                    let connectDeadline = Date().addingTimeInterval(5)
                    while true {
                        guard active, Date() < connectDeadline else { throw HerdrTerminalWire.Failure("终端连接超时。") }
                        var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        let ready = poll(&poller, 1, 100)
                        if ready < 0, errno == EINTR { continue }
                        guard ready >= 0 else { throw posixFailure() }
                        if ready == 0 { continue }
                        var error: Int32 = 0
                        var size = socklen_t(MemoryLayout<Int32>.size)
                        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 else { throw posixFailure() }
                        guard error == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(error)) }
                        break
                    }
                }
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { throw HerdrTerminalWire.Failure("Herdr socket 不属于当前用户。") }
                try writeAll(HerdrTerminalWire.hello(columns: columns, rows: rows), to: fd)
                var decoder = HerdrTerminalDecoder(), attached = false
                let deadline = Date().addingTimeInterval(10)
                while active {
                    if !attached, Date() > deadline { throw HerdrTerminalWire.Failure("终端连接超时。") }
                    var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    let polled = poll(&poller, 1, 100)
                    if polled < 0, errno == EINTR { continue }
                    guard polled >= 0 else { throw posixFailure() }
                    if polled == 0 { continue }
                    var bytes = [UInt8](repeating: 0, count: 65_536)
                    let count = Darwin.read(fd, &bytes, bytes.count)
                    if count < 0, [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                    guard count > 0 else { throw HerdrTerminalWire.Failure("终端连接已断开，可重连同一会话。") }
                    let events = try decoder.append(Data(bytes.prefix(count)))
                    if decoder.welcomed, !attached {
                        try writeAll(HerdrTerminalWire.control(pane: pane, takeover: takeover), to: fd)
                        attached = true
                    }
                    if !events.isEmpty { deliver(events) }
                    if events.contains(where: { if case .closed = $0 { return true }; return false }) { return }
                }
            } catch {
                if active { deliver([.closed(error.localizedDescription)]) }
            }
        }
    }

    func send(_ payload: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.async { [self] in
                lock.lock()
                // Duplicate under the lock so a disconnected descriptor can
                // never be reused for an unrelated file during a pending write.
                let fd = !stopped && descriptor >= 0 ? dup(descriptor) : -1
                lock.unlock()
                guard fd >= 0 else { return continuation.resume(throwing: CancellationError()) }
                defer { Darwin.close(fd) }
                do { try writeAll(payload, to: fd); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() {
        lock.lock(); stopped = true
        if descriptor >= 0 { _ = shutdown(descriptor, SHUT_RDWR) }
        lock.unlock()
    }
    private var active: Bool { lock.lock(); defer { lock.unlock() }; return !stopped }
    private func writeAll(_ payload: Data, to fd: Int32) throws {
        guard payload.count <= 2 * 1_024 * 1_024 else { throw HerdrTerminalWire.Failure("终端输入过大。") }
        let bytes = HerdrTerminalWire.framed(payload)
        var offset = 0
        let deadline = Date().addingTimeInterval(3)
        while offset < bytes.count {
            guard active, Date() < deadline else { throw HerdrTerminalWire.Failure("终端写入已取消或超时，输入不会重发。") }
            let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset) }
            if count > 0 { offset += count; continue }
            if count < 0, errno == EINTR { continue }
            if count < 0, [EAGAIN, EWOULDBLOCK].contains(errno) {
                var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&poller, 1, 100)
                continue
            }
            throw posixFailure()
        }
    }
    private func posixFailure() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
