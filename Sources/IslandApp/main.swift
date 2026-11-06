import AppKit
import Foundation
import HerdrKit

struct LaunchOptions {
    var renderDirectory: String?
    var printState = false
    var noAutoExpand = false
    var demo = false
    var logPath: String?
    var newTaskText: String?
    var newTaskSend = false
    var settings = false
    var captureProbeWindow: UInt32?
}

func parseLaunchOptions(_ arguments: [String]) -> LaunchOptions {
    var options = LaunchOptions()
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--render":
            index += 1
            if index < arguments.count {
                options.renderDirectory = arguments[index]
            }
        case "--print-state":
            options.printState = true
        case "--no-auto-expand":
            options.noAutoExpand = true
        case "--demo":
            options.demo = true
        case "--log":
            index += 1
            if index < arguments.count {
                options.logPath = arguments[index]
            }
        case "--new-task":
            index += 1
            if index < arguments.count {
                options.newTaskText = arguments[index]
            }
        case "--new-task-send":
            options.newTaskSend = true
        case "--settings":
            options.settings = true
        case "--capture-probe-window":
            index += 1
            if index < arguments.count { options.captureProbeWindow = UInt32(arguments[index]) }
        default:
            break
        }
        index += 1
    }
    return options
}

let launchOptions = parseLaunchOptions(Array(CommandLine.arguments.dropFirst()))
AppLog.shared.configure(
    path: launchOptions.logPath,
    stream: launchOptions.printState ? .stderr : .stdout
)

if launchOptions.printState {
    let code = await PrintState.run(options: launchOptions)
    exit(code)
}

if let windowID = launchOptions.captureProbeWindow {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    Task { @MainActor in exit(await WindowCaptureProbe.run(windowID: windowID)) }
    application.run()
    exit(1)
}

if let directory = launchOptions.renderDirectory {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let code = RenderHarness.run(directory: directory)
    exit(code)
}

if launchOptions.settings {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let environment = try? HerdrLocator.resolve()
    let controller = SettingsWindowController(
        rules: IslandSettings.rules(),
        herdrPath: environment?.binary.path ?? "herdr not found",
        socketPath: environment?.socket.path ?? HerdrLocator.socketURL().path,
        onChange: { _ in }
    )
    controller.show()
    application.run()
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate(options: launchOptions)
application.delegate = delegate
application.run()
