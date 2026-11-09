import Darwin
import Foundation
import IslandCore

public enum HerdrSocketLine: Equatable, Sendable {
    case subscriptionStarted
    case facts(AgentFacts)
    case event(kind: String?)
    case error(String)
    case other
}

public enum HerdrSocketProtocol {
    public static func subscribeRequest(panes: [PaneID], id: String = "sub") -> Data {
        var subscriptions: [[String: String]] = panes
            .sorted()
            .map { ["type": "pane.agent_status_changed", "pane_id": $0.rawValue] }
        subscriptions.append(["type": "pane.created"])
        subscriptions.append(["type": "pane.closed"])

        let request: [String: Any] = [
            "id": id,
            "method": "events.subscribe",
            "params": ["subscriptions": subscriptions],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]))
            ?? Data(#"{"id":"sub","method":"events.subscribe","params":{"subscriptions":[]}}"#.utf8)
        var line = data
        line.append(0x0A)
        return line
    }

    public static func classify(_ line: Data, at: Date = Date()) -> HerdrSocketLine {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return .other
        }
        if let result = object["result"] as? [String: Any],
           result["type"] as? String == "subscription_started" {
            return .subscriptionStarted
        }
        if let event = object["event"] as? String {
            switch HerdrWire.decodeSocketEvent(line, at: at) {
            case .facts(let facts):
                return .facts(facts)
            case .rebuild:
                return .event(kind: event)
            case nil:
                return .other
            }
        }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? error["code"] as? String ?? "unknown error"
            return .error(message)
        }
        return .other
    }
}

/// A subscriber to the Herdr server socket. Status changes arrive as facts and update the
/// island in place; every other event invalidates the cache and asks the service to resample.
public actor HerdrSocket {
    public typealias InvalidationHandler = @Sendable () async -> Void
    public typealias FactsHandler = @Sendable (AgentFacts) async -> Void

    private static let receiveTimeout: timeval = timeval(tv_sec: 0, tv_usec: 300_000)

    private let socketURL: URL
    private let onInvalidate: InvalidationHandler
    private let onFacts: FactsHandler
    private let log: @Sendable (String) -> Void
    private var panes: [PaneID] = []
    private var runTask: Task<Void, Never>?

    public init(
        socketURL: URL,
        onInvalidate: @escaping InvalidationHandler,
        onFacts: @escaping FactsHandler = { _ in },
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.socketURL = socketURL
        self.onInvalidate = onInvalidate
        self.onFacts = onFacts
        self.log = log
    }

    public func start(panes: [PaneID] = []) {
        guard runTask == nil else {
            updatePanes(panes)
            return
        }
        self.panes = panes.sorted()
        runTask = Task { [weak self] in await self?.loop() }
    }

    public func updatePanes(_ panes: [PaneID]) {
        let sorted = panes.sorted()
        guard sorted != self.panes else { return }
        self.panes = sorted
        guard runTask != nil else { return }
        log("rebuilding subscription for \(sorted.count) panes")
        runTask?.cancel()
        runTask = Task { [weak self] in await self?.loop() }
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
    }

    private func loop() async {
        var attempt = 0
        while !Task.isCancelled {
            let subscribed = await connectAndRead()
            if Task.isCancelled { break }
            if subscribed {
                attempt = 0
            }
            let delay = Self.backoff(attempt)
            attempt = min(attempt + 1, 4)
            log("socket reconnecting in \(Int(delay))s")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private static func backoff(_ attempt: Int) -> TimeInterval {
        switch attempt {
        case 0: 1
        case 1: 2
        case 2: 4
        default: 30
        }
    }

    private func connectAndRead() async -> Bool {
        let path = socketURL.path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            log("socket() failed with errno \(errno)")
            return false
        }
        defer { Darwin.close(fd) }

        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var timeout = Self.receiveTimeout
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            log("socket path is too long: \(path)")
            return false
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            log("socket connect failed: \(String(cString: strerror(errno)))")
            return false
        }

        let request = HerdrSocketProtocol.subscribeRequest(panes: panes)
        guard Self.writeAll(fd, request) else {
            log("socket subscribe write failed: \(String(cString: strerror(errno)))")
            return false
        }

        var buffer = Data()
        var subscribed = false

        while !Task.isCancelled {
            switch await Self.blockingRead(fd, capacity: 65536) {
            case .bytes(let chunk, let count):
                buffer.append(contentsOf: chunk[0..<count])
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard !line.isEmpty else { continue }
                    switch HerdrSocketProtocol.classify(line) {
                    case .subscriptionStarted:
                        subscribed = true
                        log("subscribed to \(panes.count) panes")
                    case .facts(let facts):
                        if subscribed {
                            await onFacts(facts)
                            log("socket facts \(facts.pane.rawValue) \(facts.status?.rawValue ?? "unknown")")
                        }
                    case .event(let kind):
                        if subscribed {
                            await onInvalidate()
                            log("socket event \(kind ?? "unknown")")
                        }
                    case .error(let message):
                        log("socket error line: \(message)")
                    case .other:
                        break
                    }
                }
            case .wouldBlock:
                continue
            case .closed:
                return subscribed
            case .failed(let code):
                log("socket read failed: \(String(cString: strerror(code)))")
                return subscribed
            }
        }
        return subscribed
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private enum ReadOutcome: Sendable {
        case bytes([UInt8], Int)
        case wouldBlock
        case closed
        case failed(Int32)
    }

    private nonisolated static func blockingRead(
        _ fd: Int32,
        capacity: Int
    ) async -> ReadOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<ReadOutcome, Never>) in
            DispatchQueue.global(qos: .utility).async {
                var chunk = [UInt8](repeating: 0, count: capacity)
                let count = Darwin.read(fd, &chunk, capacity)
                if count > 0 {
                    continuation.resume(returning: .bytes(chunk, count))
                } else if count == 0 {
                    continuation.resume(returning: .closed)
                } else {
                    let code = errno
                    if code == EAGAIN || code == EWOULDBLOCK || code == EINTR {
                        continuation.resume(returning: .wouldBlock)
                    } else {
                        continuation.resume(returning: .failed(code))
                    }
                }
            }
        }
    }
}
