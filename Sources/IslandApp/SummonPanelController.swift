import AppKit
import CoreGraphics
import IslandCore
import SwiftUI

/// The summon host. It is a second panel, not a second island surface: the
/// deck keeps its key state while this card is up, and a click in another app
/// closes only this panel.
@MainActor
final class SummonPanelController: NSObject, NSWindowDelegate {
    private let panel: IslandPanel
    private let hosting: NSHostingView<SummonRootView>
    private let actions: IslandViewActions
    private var summon: SummonPresentation?
    private var animator: FrameAnimator?
    private var isOnScreen = false
    /// True while we order the panel out ourselves. `resignKey` posts
    /// `windowDidResignKey` synchronously, and closing again from there would
    /// recurse.
    private var isHidingPanel = false
    /// True while a folder or file picker owns key focus. This panel is at
    /// `.statusBar` level and the picker is not, so showing the card would put
    /// it over the picker.
    private var isPickerActive = false
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?

    var onEvent: ((IslandEvent) -> Void)?

    private static let contentWidth: CGFloat = 360
    private static let padding: CGFloat = 16

    init(actions: IslandViewActions) {
        self.actions = actions
        self.panel = IslandPanel(contentRect: CGRect(
            x: 0,
            y: 0,
            width: Self.contentWidth + Self.padding * 2,
            height: 200
        ))
        self.hosting = NSHostingView(rootView: SummonRootView(
            summon: nil,
            actions: actions,
            onClose: {}
        ))

        super.init()

        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self

        animator = FrameAnimator { [weak self] frame in
            self?.panel.setFrame(frame, display: true)
        }

        installKeyMonitor()
        installClickMonitor()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    }

    func apply(_ next: SummonPresentation?) {
        guard let next else {
            hide()
            return
        }
        let wasOnScreen = isOnScreen
        summon = next
        hosting.rootView = SummonRootView(
            summon: next,
            actions: actions,
            onClose: { [weak self] in self?.closeFromCard() }
        )

        let target = targetFrame(for: next)
        if isPickerActive {
            panel.setFrame(target, display: false)
            return
        }
        if !wasOnScreen {
            isOnScreen = true
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            appLog("summon show frame=\(NSStringFromRect(target))")
            return
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animator?.cancel()
            panel.setFrame(target, display: true)
        } else {
            animator?.retarget(from: panel.frame, to: target)
        }
    }

    func hide() {
        summon = nil
        animator?.cancel()
        guard isOnScreen || panel.isVisible else {
            return
        }
        isOnScreen = false
        isHidingPanel = true
        panel.resignKey()
        panel.orderOut(nil)
        isHidingPanel = false
    }

    /// The picker is a separate window at a lower level, so the card steps
    /// aside for it and comes back when the picker closes.
    func beginPicker() {
        guard !isPickerActive else { return }
        isPickerActive = true
        animator?.cancel()
        isOnScreen = false
        isHidingPanel = true
        panel.resignKey()
        panel.orderOut(nil)
        isHidingPanel = false
    }

    func endPicker() {
        isPickerActive = false
        guard let summon else { return }
        isOnScreen = true
        panel.setFrame(targetFrame(for: summon), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func screenParametersChanged() {
        guard isOnScreen, let summon else { return }
        animator?.cancel()
        panel.setFrame(targetFrame(for: summon), display: true)
    }

    private func targetFrame(for summon: SummonPresentation) -> CGRect {
        IslandGeometry.summonFrame(
            point: summon.point,
            size: CGSize(
                width: Self.contentWidth + Self.padding * 2,
                height: summon.height
            ),
            screens: Self.screenMetrics()
        )
    }

    private static func screenMetrics() -> [ScreenMetrics] {
        NSScreen.screens.map { screen in
            ScreenMetrics(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top,
                auxTopLeft: screen.auxiliaryTopLeftArea,
                auxTopRight: screen.auxiliaryTopRightArea
            )
        }
    }

    /// Closing from the card's X must not let the subsequent resign post a
    /// second close, so the panel hides before the event reaches the store.
    func closeFromCard() {
        hide()
        onEvent?(.closeSummon)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible, !isHidingPanel, !isPickerActive, summon != nil else { return }
        // A popover, the file picker, or the settings window taking key is a
        // handoff inside the app, not a click elsewhere.
        if let key = NSApp.keyWindow, key !== panel, Self.isOwnWindow(key) {
            return
        }
        onEvent?(.closeSummon)
    }

    private static func isOwnWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return true }
        if window.className.contains("Popover") { return true }
        return NSApp.windows.contains { $0 === window && $0.isVisible && $0.level == .modalPanel }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.panel else { return event }
            return MainActor.assumeIsolated { self.handleKey(event) }
        }
    }

    /// The summon closes on a click anywhere outside it. The local monitor alone
    /// would miss clicks in another app, which never reach this process.
    private func installClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.summon != nil else { return }
                let point = NSEvent.mouseLocation
                if self.panel.frame.contains(point) { return }
                if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(point) }) { return }
                self.onEvent?(.closeSummon)
            }
        }
        // A click inside another of our windows (the settings window, a
        // popover) never reaches the global monitor, so the local one covers
        // the same rule for our own process.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.summon != nil else { return event }
            if event.window === self.panel { return event }
            if let window = event.window, Self.isOwnWindow(window) { return event }
            self.onEvent?(.closeSummon)
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // Marked text means an IME composition is in progress; Escape and
        // Return belong to the composition.
        if let editor = panel.fieldEditor(false, for: nil) as? NSTextView,
           editor.hasMarkedText() {
            return event
        }
        guard let stroke = KeyStroke(event: event) else { return event }
        if stroke.key == .escape {
            onEvent?(.closeSummon)
            return nil
        }
        if stroke.key == .return, stroke.modifiers.contains(.command) {
            if summon?.composer.send.canSubmit == true {
                actions.submitDelivery(.summon)
            }
            return nil
        }
        return event
    }
}

/// The summon's only content: the shared card inside a 16 pt gutter that also
/// holds its shadow, plus the muted context summary line the card owns.
struct SummonRootView: View {
    let summon: SummonPresentation?
    let actions: IslandViewActions
    var onClose: () -> Void

    var body: some View {
        Group {
            if let summon {
                DeliveryComposerCard(
                    composer: summon.composer,
                    actions: actions,
                    onClose: onClose
                )
                .frame(width: 360)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
