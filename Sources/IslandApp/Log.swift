import Foundation

enum LogStream {
    case stdout
    case stderr
}

final class AppLog {
    static let shared = AppLog()

    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var stream: LogStream = .stdout
    private let formatter: DateFormatter

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.formatter = formatter
    }

    func configure(path: String?, stream: LogStream) {
        lock.lock()
        defer { lock.unlock() }
        self.stream = stream
        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            fileHandle = try? FileHandle(forWritingTo: url)
            fileHandle?.seekToEndOfFile()
        }
    }

    func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        switch stream {
        case .stdout:
            FileHandle.standardOutput.write(data)
        case .stderr:
            FileHandle.standardError.write(data)
        }
        fileHandle?.write(data)
    }
}

func appLog(_ message: String) {
    AppLog.shared.write(message)
}
