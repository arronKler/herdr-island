import AppKit
import Foundation

struct LaunchOptions {
    var renderDirectory: String?
    var printState = false
    var noAutoExpand = false
    var demo = false
    var logPath: String?
    var newTaskText: String?
    var newTaskSend = false
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

if let directory = launchOptions.renderDirectory {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let code = RenderHarness.run(directory: directory)
    exit(code)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate(options: launchOptions)
application.delegate = delegate
application.run()
