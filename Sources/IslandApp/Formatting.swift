import Foundation
import IslandCore

enum IslandFormat {
    static func age(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        if value < 45 { return "刚刚" }
        if value < 3_600 { return "\(max(1, value / 60)) 分" }
        if value < 86_400 { return "\(value / 3_600) 时" }
        return "\(value / 86_400) 天"
    }

    static func ageFromNow(_ date: Date) -> String {
        age(Date().timeIntervalSince(date))
    }

    static func ago(_ seconds: TimeInterval) -> String {
        let value = age(seconds)
        return value == "刚刚" ? "刚刚" : "\(value)前"
    }

    static func completedAgo(_ seconds: TimeInterval) -> String {
        let value = age(seconds)
        return value == "刚刚" ? "刚刚完成" : "\(value)前完成"
    }

    static func status(_ status: AgentStatus, pending: Bool = false) -> String {
        if pending { return "已完成" }
        switch status {
        case .blocked: return "需要你"
        case .working: return "运行中"
        case .done: return "已完成"
        case .idle: return "空闲"
        case .unknown: return "未知"
        }
    }

    static func reason(_ reason: AgentReason?) -> String {
        switch reason {
        case .approval: return "等待批准"
        case .auth: return "等待登录"
        case .question: return "等待回答"
        case .input: return "等待输入"
        case nil: return "需要处理"
        }
    }

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func folderName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日"
        return formatter.string(from: date)
    }
}

enum RepoCheck {
    static func isGitRepository(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var url = URL(fileURLWithPath: path)
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return true
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return false
    }
}
