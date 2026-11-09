import AppKit
import IslandCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private var presentation: IslandPresentation?
    private var showHideItem: NSMenuItem?

    var onToggle: (() -> Void)?
    var onNewTask: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = StatusItemController.image(for: .starting)
            button.toolTip = "Herdr Island"
        }

        let menu = NSMenu()
        let showHide = NSMenuItem(
            title: "显示岛",
            action: #selector(toggleIsland),
            keyEquivalent: ""
        )
        showHide.target = self
        menu.addItem(showHide)
        showHideItem = showHide

        let newTask = NSMenuItem(
            title: "新建 agent 任务…  ⌃⌥N",
            action: #selector(newTaskPressed),
            keyEquivalent: ""
        )
        newTask.target = self
        menu.addItem(newTask)

        let settings = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Herdr Island", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func update(_ presentation: IslandPresentation) {
        self.presentation = presentation
        let text = StatusItemController.headline(presentation)
        statusItem.button?.toolTip = "Herdr Island · \(text)"
        showHideItem?.title = presentation.isExpanded || presentation.drop != nil ? "隐藏岛" : "显示岛"
        statusItem.button?.appearsDisabled = presentation.health == .failed
        statusItem.button?.image = StatusItemController.image(for: presentation.headline)
    }

    private static func image(for headline: IslandHeadline) -> NSImage? {
        guard let base = NSImage(
            systemSymbolName: "capsule.bottomhalf.filled",
            accessibilityDescription: "Herdr Island"
        ) else { return nil }

        let color: NSColor?
        switch headline {
        case .working: color = NSColor(Theme.working)
        case .blocked: color = NSColor(Theme.blocked)
        case .completed: color = NSColor(Theme.done)
        case .stale: color = NSColor(Theme.error)
        case .starting, .empty: color = nil
        }
        guard let color else {
            base.isTemplate = true
            return base
        }
        let image = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [color])
        ) ?? base
        image.isTemplate = false
        return image
    }

    var frame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    static func headline(_ presentation: IslandPresentation) -> String {
        switch presentation.headline {
        case .blocked(let count):
            return count == 1 ? "1 个需要你" : "\(count) 个需要你"
        case .completed(let count):
            return "\(count) 个已完成"
        case .working(let count):
            return "\(count) 个运行中"
        case .stale:
            return "Herdr 离线"
        case .starting:
            return "Herdr 启动中"
        case .empty:
            return "Herdr 空闲"
        }
    }

    @objc private func toggleIsland() {
        onToggle?()
    }

    @objc private func newTaskPressed() {
        onNewTask?()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
