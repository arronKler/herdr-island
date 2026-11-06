import AppKit
import Foundation

// A separate process with an AppKit run loop provides a real, fully rendered
// capture target. Only synthetic content is ever captured by the audit.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 40, y: 80, width: 1000, height: 650),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.title = "Herdr Island baseline fixture"
window.isReleasedWhenClosed = false
window.ignoresMouseEvents = true
window.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
for index in 0..<24 {
    let label = NSTextField(labelWithString: "\(index + 1)  baseline.synthetic.task  |  status: ready  |  duration: 123 ms")
    label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
    label.textColor = index.isMultiple(of: 3) ? .systemGreen : .white
    label.frame = NSRect(x: 25, y: 20 + index * 25, width: 940, height: 24)
    window.contentView?.addSubview(label)
}
window.orderBack(nil)
window.display()
let infoURL = URL(fileURLWithPath: CommandLine.arguments[1])
var shown = false
let visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    if FileManager.default.fileExists(atPath: infoURL.appendingPathExtension("hide").path) {
        if shown { window.orderOut(nil); shown = false }
    } else if !shown, FileManager.default.fileExists(atPath: infoURL.appendingPathExtension("show").path) {
        shown = true
        window.orderFrontRegardless()
        window.display()
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    let data = try! JSONSerialization.data(withJSONObject: ["window_id": window.windowNumber, "scale": window.backingScaleFactor])
    try! data.write(to: infoURL)
}
app.run()
