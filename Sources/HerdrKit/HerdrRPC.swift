import Darwin
import Foundation
import IslandCore

indirect enum HerdrRPCValue: Sendable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case array([HerdrRPCValue])
    case object([String: HerdrRPCValue])

    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .integer(let value): return value
        case .bool(let value): return value
        case .array(let value): return value.map(\.jsonValue)
        case .object(let value): return value.mapValues(\.jsonValue)
        }
    }
}

struct HerdrRPCError: Error, Sendable {
    let code: String
    let message: String
}

/// A single local request without a subprocess. This transport never retries;
/// callers may retry reads, but must preserve at-most-once dispatch for mutations.
struct HerdrRPC: Sendable {
    let socketURL: URL

    func request(method: String, params: [String: HerdrRPCValue] = [:], timeout: TimeInterval) async throws -> Data {
        let id = UUID().uuidString
        var request = try JSONSerialization.data(withJSONObject: [
            "id": id, "method": method, "params": params.mapValues(\.jsonValue),
        ])
        request.append(0x0A)
        let operation = RPCOperation()
        let path = socketURL.path
        let bytes = request
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try operation.run(path: path, request: bytes, id: id, timeout: timeout)
                    })
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class RPCOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private func checkCancellation() throws {
        lock.lock()
        let cancelled = cancelled
        lock.unlock()
        if cancelled { throw CancellationError() }
    }

    func run(path: String, request: Data, id: String, timeout: TimeInterval) throws -> Data {
        try checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(max(timeout, 0)))
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw socketFailure() }
        defer { Darwin.close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw socketFailure() }
        var noSignal: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw socketFailure()
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw BackendFailure(.commandFailed, "Herdr socket path is too long.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else { throw socketFailure() }
            try wait(fd, for: Int16(POLLOUT), deadline: deadline)
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else {
                throw BackendFailure(.commandFailed, "Herdr socket connection failed.")
            }
        }
        var sent = 0
        while sent < request.count {
            try wait(fd, for: Int16(POLLOUT), deadline: deadline)
            let count = request.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: sent), request.count - sent)
            }
            if count > 0 { sent += count }
            else if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            else { throw socketFailure() }
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            try wait(fd, for: Int16(POLLIN), deadline: deadline)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard count > 0 else { throw BackendFailure(.commandFailed, "Herdr socket closed before replying.") }
            buffer.append(contentsOf: chunk.prefix(count))
            guard buffer.count <= 4 * 1024 * 1024 else {
                throw BackendFailure(.decode, "Herdr socket response is too large.")
            }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? String == id else {
                    throw BackendFailure(.decode, "Herdr socket returned an invalid response.")
                }
                if let error = object["error"] as? [String: Any],
                   let code = error["code"] as? String {
                    throw HerdrRPCError(code: code, message: error["message"] as? String ?? code)
                }
                guard object["result"] is [String: Any], object["error"] == nil else {
                    throw BackendFailure(.decode, "Herdr socket returned an invalid response.")
                }
                try checkCancellation()
                return line
            }
        }
    }

    private func wait(_ fd: Int32, for events: Int16, deadline: ContinuousClock.Instant) throws {
        while true {
            try checkCancellation()
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw BackendFailure(.timeout, "Herdr socket request timed out.") }
            let components = remaining.components
            let milliseconds = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(max(1, min(100, milliseconds.rounded(.up)))))
            if result > 0 { return } // read/write reports EOF or socket errors.
            if result < 0, errno != EINTR { throw socketFailure() }
        }
    }

    private func socketFailure() -> BackendFailure {
        BackendFailure(.commandFailed, "Herdr socket: \(String(cString: strerror(errno)))")
    }
}
