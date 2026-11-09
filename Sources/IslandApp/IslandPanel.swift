import AppKit
import IslandCore
import QuartzCore
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        // Must stay last. `isFloatingPanel` and several window properties reset the level.
        level = .statusBar
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }
}

@MainActor
final class FrameAnimator {
    private var timer: Timer?
    private var startFrame: CGRect = .zero
    private var targetFrame: CGRect = .zero
    private var startTime: TimeInterval = 0
    private let duration: TimeInterval = 0.24
    private let onFrame: (CGRect) -> Void

    init(onFrame: @escaping (CGRect) -> Void) {
        self.onFrame = onFrame
    }

    var isRunning: Bool { timer != nil }

    func retarget(from current: CGRect, to target: CGRect) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            cancel()
            onFrame(target)
            return
        }
        if framesMatch(current, target) {
            cancel()
            onFrame(target)
            return
        }
        startFrame = current
        targetFrame = target
        startTime = CACurrentMediaTime()
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        tick()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - startTime
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 4)
        let frame = CGRect(
            x: startFrame.minX + (targetFrame.minX - startFrame.minX) * eased,
            y: startFrame.minY + (targetFrame.minY - startFrame.minY) * eased,
            width: startFrame.width + (targetFrame.width - startFrame.width) * eased,
            height: startFrame.height + (targetFrame.height - startFrame.height) * eased
        )
        onFrame(frame.integral)
        if progress >= 1 {
            cancel()
        }
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }
}

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    let panel: IslandPanel

    private let hosting: NSHostingView<IslandRootView>
    private let actions: IslandViewActions
    private var presentation: IslandPresentation
    private var placement: IslandPlacement
    /// Frozen deck height. Row statuses change the presenter's natural height on
    /// every tick; following it animates the panel while the list is being read.
    private var lockedDeckHeight: CGFloat?
    private var animator: FrameAnimator?
    private var isOnScreen = false
    /// True while the folder picker owns the screen. The panel is hidden and
    /// must not re-show or report lost focus until the picker ends.
    private var isPickerActive = false
    /// The display a quick task centers on. Captured when the card opens so a
    /// later mouse move cannot slide an open card to another screen.
    private var quickTaskScreenFrame: CGRect?
    /// The display the drop canvas lives on. A window only composites on the
    /// Space of the display it belongs to, so a canvas spanning every display
    /// would leave the droplet and the composer invisible on all the others.
    /// The canvas therefore follows the pointer's display for the whole drag.
    private var dropScreenFrame: CGRect?
    /// True between a left mouse down and up. Only an active drag may move the
    /// drop canvas; an open composer must stay where it was placed.
    private var isPointerDown = false
    /// True while we hide the panel ourselves. Without this, `resignKey()`
    /// synchronously posts `windowDidResignKey`, which re-enters the store and
    /// applies the collapse again, recursing until the stack overflows.
    private var isHidingPanel = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?

    var onEvent: ((IslandEvent) -> Void)?
    var onLostFocus: (() -> Void)?
    var statusItemFrameProvider: (() -> CGRect?)?

    init(presentation: IslandPresentation, actions: IslandViewActions) {
        let metrics = ScreenMetrics.current()
        let placement = IslandGeometry.placement(for: metrics, statusItemFrame: nil)
        let lockedDeckHeight = presentation.surface == .deck && presentation.windowTask == nil
            ? presentation.deckHeight
            : nil
        let frame = Self.frame(
            placement: placement,
            expanded: presentation.isExpanded,
            quickTask: presentation.quickTask != nil,
            quickTaskHeight: presentation.quickTask?.height ?? IslandGeometry.quickTaskSize.height,
            surface: presentation.surface,
            dropActive: presentation.isDropActive,
            deckHeight: lockedDeckHeight ?? presentation.deckHeight,
            dropScreenFrame: nil
        )
        let notch = Self.notchChrome(for: presentation, placement: placement)
        let anchor = IslandGeometry.dropAnchor(for: placement, panelFrame: frame)
        let anchorScreen = IslandGeometry.dropScreenAnchor(for: placement)

        self.presentation = presentation
        self.actions = actions
        self.placement = placement
        self.lockedDeckHeight = lockedDeckHeight
        self.panel = IslandPanel(contentRect: frame)
        self.hosting = NSHostingView(rootView: IslandRootView(
            presentation: presentation,
            actions: actions,
            notchWidth: notch?.width,
            notchHeight: notch?.height ?? 0,
            anchorX: anchor.x,
            anchorY: anchor.y,
            anchorScreen: anchorScreen,
            screens: Self.localScreenFrames(panelFrame: frame)
        ))

        super.init()

        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
        panel.setFrame(frame, display: false)

        animator = FrameAnimator { [weak self] frame in
            self?.panel.setFrame(frame, display: true)
        }

        installKeyMonitor()
        installMouseMonitor()
        appLog(
            "launch metrics screen=\(NSStringFromRect(metrics.screenFrame)) "
            + "visible=\(NSStringFromRect(metrics.visibleFrame)) safeTop=\(metrics.safeAreaTop) "
            + "auxLeft=\(metrics.auxTopLeft.map(NSStringFromRect) ?? "nil") "
            + "auxRight=\(metrics.auxTopRight.map(NSStringFromRect) ?? "nil")"
        )
        logState(tag: "launch")
        logProof(tag: "launch")
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
    }

    func apply(_ next: IslandPresentation, needsKey: Bool = false) {
        let previous = presentation

        presentation = next
        let enteredDrop = next.surface == .drop && previous.surface != .drop
        let leftDrop = previous.surface == .drop && next.surface != .drop
        if enteredDrop {
            // Start on the display the droplet was pulled from. The drag then
            // moves the canvas to whichever display the pointer enters.
            dropScreenFrame = Self.screenFrame(containing: NSEvent.mouseLocation)
                ?? placement.screenFrame
        } else if leftDrop {
            dropScreenFrame = nil
            isPointerDown = false
        }
        if previous.quickTask == nil, next.quickTask != nil {
            quickTaskScreenFrame = ScreenMetrics.activeScreenFrame()
        } else if previous.quickTask != nil, next.quickTask == nil {
            quickTaskScreenFrame = nil
        }
        syncDeckHeightLock(previous: previous, next: next)
        refreshPlacement()

        // The quick task is a modal that belongs in the center. Moving the
        // panel there from the status item would read as a fly-in animation,
        // so show it at its final frame instead.
        let quickTaskOpened = previous.quickTask == nil && next.quickTask != nil
        let quickTaskClosed = previous.quickTask != nil && next.quickTask == nil
        // The drop canvas and the quick-task close jump the window to a very
        // different frame in one step. Cross-fading there would squeeze the
        // outgoing card into the wrong size, so those swaps stay instant.
        let instantSurface = enteredDrop || leftDrop || quickTaskClosed

        let target = targetFrame
        render(panelFrame: target, surfaceMotion: !instantSurface)

        // A folder picker owns key focus. Re-showing the panel here would put
        // it over the picker; endPicker() restores the frame and key.
        if isPickerActive {
            refreshMousePolicy()
            return
        }

        let shouldShow = placement.isNotch
            ? (next.isVisible || next.dropletVisible || next.isWindowDragActive)
            : (next.isExpanded || next.isWindowDragActive)
        if shouldShow {
            if !isOnScreen {
                let start = quickTaskOpened
                    ? target
                    : IslandGeometry.frame(for: placement, expanded: false)
                panel.setFrame(start, display: true)
                panel.orderFrontRegardless()
                isOnScreen = true
                if enteredDrop || leftDrop || quickTaskOpened {
                    animator?.cancel()
                    panel.setFrame(target, display: true)
                } else {
                    animator?.retarget(from: start, to: target)
                }
                logProof(tag: "show")
            } else if enteredDrop || leftDrop || quickTaskOpened || quickTaskClosed {
                animator?.cancel()
                panel.setFrame(target, display: true)
            } else {
                animator?.retarget(from: panel.frame, to: target)
            }
            let windowTaskOpened = previous.windowTask == nil && next.windowTask != nil
            let dropOpened = previous.drop == nil && next.drop != nil
            if needsKey || next.isComposerFocused || quickTaskOpened || windowTaskOpened || dropOpened {
                panel.makeKeyAndOrderFront(nil)
            }
        } else if isOnScreen, !next.isWindowDragActive {
            animator?.cancel()
            isOnScreen = false
            isHidingPanel = true
            panel.resignKey()
            panel.orderOut(nil)
            isHidingPanel = false
            appLog("panel hidden")
        }

        refreshMousePolicy()

        if previous.headline != next.headline {
            appLog("[headline] \(previous.headline) -> \(next.headline)")
        }
        if (previous.quickTask == nil) != (next.quickTask == nil) {
            appLog("[quickTask] \(next.quickTask == nil ? "closed" : "open")")
        }
        if previous.quickTask?.isCreating != next.quickTask?.isCreating {
            appLog("[quickTask] creating=\(next.quickTask?.isCreating ?? false)")
        }
        if (previous.drop == nil) != (next.drop == nil) {
            appLog("[drop] \(next.drop == nil ? "closed" : "open")")
        }
        if previous.isExpanded != next.isExpanded || previous.isVisible != next.isVisible {
            logState(tag: "presentation")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.logProof(tag: "presentation")
            }
        }
    }

    /// The height every frame computation uses. While the deck is open the
    /// captured value wins, so live row statuses cannot resize the panel.
    private var effectiveDeckHeight: CGFloat {
        lockedDeckHeight ?? presentation.deckHeight
    }

    /// The frame the panel should have for the current presentation.
    private var targetFrame: CGRect {
        Self.frame(
            placement: placement,
            expanded: presentation.isExpanded,
            quickTask: presentation.quickTask != nil,
            quickTaskHeight: presentation.quickTask?.height ?? IslandGeometry.quickTaskSize.height,
            surface: presentation.surface,
            dropActive: presentation.isDropActive,
            deckHeight: effectiveDeckHeight,
            quickTaskScreen: quickTaskScreenFrame,
            dropScreenFrame: dropScreenFrame
        )
    }

    /// Captures the deck height when the deck opens, and releases the lock as
    /// soon as a window task owns the panel or the surface changes.
    private func syncDeckHeightLock(previous: IslandPresentation, next: IslandPresentation) {
        guard next.surface == .deck, next.windowTask == nil else {
            lockedDeckHeight = nil
            return
        }
        if lockedDeckHeight == nil
            || previous.surface != .deck
            || previous.windowTask != nil
            || previous.filter != next.filter
            || previous.query != next.query
            || previous.isSearching != next.isSearching {
            lockedDeckHeight = next.deckHeight
        }
    }

    private static func frame(
        placement: IslandPlacement,
        expanded: Bool,
        quickTask: Bool,
        quickTaskHeight: CGFloat,
        surface: IslandSurface,
        dropActive: Bool,
        deckHeight: CGFloat,
        quickTaskScreen: CGRect? = nil,
        dropScreenFrame: CGRect? = nil
    ) -> CGRect {
        IslandGeometry.frame(
            for: placement,
            expanded: expanded,
            quickTask: quickTask,
            quickTaskHeight: quickTaskHeight,
            surface: surface,
            dropActive: dropActive,
            deckHeight: deckHeight,
            dropScreenFrame: dropScreenFrame,
            quickTaskScreen: quickTaskScreen
        )
    }

    /// The display under the pointer. The drop canvas is a single window, and
    /// a window composites only on the Space of the display it belongs to, so
    /// the canvas has to cover exactly one display at a time.
    private static func screenFrame(containing point: CGPoint) -> CGRect? {
        let frames = NSScreen.screens.map(\.frame)
        if let hit = frames.first(where: { $0.contains(point) }) {
            return hit
        }
        // The pointer can sit in a gap between displays. Pick the closest.
        return frames.min { lhs, rhs in
            distanceSquared(from: point, to: lhs) < distanceSquared(from: point, to: rhs)
        }
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, point.x - rect.maxX), 0)
        let dy = max(max(rect.minY - point.y, point.y - rect.maxY), 0)
        return dx * dx + dy * dy
    }

    /// Screen frames in the panel's flipped local space, for composer clamping.
    private static func localScreenFrames(panelFrame: CGRect) -> [CGRect] {
        NSScreen.screens.map { screen in
            CGRect(
                x: screen.frame.minX - panelFrame.minX,
                y: panelFrame.maxY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
    }

    func makeKey() {
        guard !isPickerActive else { return }
        panel.makeKeyAndOrderFront(nil)
        isOnScreen = panel.isVisible
    }

    /// A folder picker is about to take key focus. Hide the card so the picker
    /// does not overlap it, and suppress the resign callback so the store does
    /// not read the handoff as click-away.
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

    /// Both picker outcomes come back here. Restore the frame and key so the
    /// card survives a cancelled folder choice. If a hotkey closed the card
    /// while the picker was up, keep the panel hidden instead of resurrecting
    /// a stray ambient bar.
    func endPicker() {
        isPickerActive = false
        let target = targetFrame
        animator?.cancel()
        let shouldShow = placement.isNotch
            ? (presentation.isVisible || presentation.dropletVisible || presentation.isWindowDragActive)
            : (presentation.isExpanded || presentation.isWindowDragActive)
        if shouldShow {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
            isOnScreen = true
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderOut(nil)
            isOnScreen = false
        }
        refreshMousePolicy()
    }

    /// During a drop the panel is the whole screen. This is the part that is
    /// still the island: dropping an Option-drag here cancels the lock.
    func isIslandDropCancelPoint(_ point: CGPoint) -> Bool {
        IslandGeometry.dropCancelRegion(for: placement).contains(point)
    }

    var tetherAnchor: CGPoint? {
        switch placement {
        case .notch(let notch, _):
            return CGPoint(x: notch.midX, y: notch.minY)
        case .menuBar:
            return CGPoint(x: panel.frame.midX, y: panel.frame.minY)
        }
    }

    /// The notch chrome belongs to the island surfaces. A centered quick task
    /// is a standalone modal, so it must not inherit the notch ears.
    private static func notchChrome(
        for presentation: IslandPresentation,
        placement: IslandPlacement
    ) -> CGRect? {
        guard presentation.quickTask == nil,
              case .notch(let rect, _) = placement else { return nil }
        return rect
    }

    private func render(panelFrame: CGRect, surfaceMotion: Bool = true) {
        let notch = Self.notchChrome(for: presentation, placement: placement)
        let anchor = IslandGeometry.dropAnchor(for: placement, panelFrame: panelFrame)
        let anchorScreen = IslandGeometry.dropScreenAnchor(for: placement)
        let revealsFromTop = presentation.surface == .peek
            || presentation.surface == .deck
            || presentation.surface == .detail
        hosting.rootView = IslandRootView(
            presentation: presentation,
            actions: actions,
            notchWidth: notch?.width,
            notchHeight: notch?.height ?? 0,
            anchorX: anchor.x,
            anchorY: anchor.y,
            anchorScreen: anchorScreen,
            screens: Self.localScreenFrames(panelFrame: panelFrame),
            surfaceMotion: surfaceMotion,
            revealSize: revealsFromTop ? panelFrame.size : nil
        )
    }

    func refreshPlacement() {
        let metrics = ScreenMetrics.current()
        let next = IslandGeometry.placement(
            for: metrics,
            statusItemFrame: statusItemFrameProvider?()
        )
        let moved = next != placement
        if moved {
            placement = next
            appLog(
                "placement=\(next.isNotch ? "notch" : "menuBar") "
                + "screen=\(NSStringFromRect(metrics.screenFrame)) safeTop=\(metrics.safeAreaTop)"
            )
        }
        // A placement move (display change, menu-bar anchor change) is a
        // discrete jump, so it snaps. Ordinary presentation changes must leave
        // the frame alone: apply() animates it, and snapping here would turn
        // that retarget into a no-op — the hover expand used to pop because of
        // this.
        if moved, isOnScreen, !(animator?.isRunning ?? false) {
            let target = targetFrame
            render(panelFrame: target, surfaceMotion: false)
            panel.setFrame(target, display: true)
        }
    }

    func screenParametersChanged() {
        animator?.cancel()
        refreshPlacement()
        if presentation.surface == .drop {
            // The display that hosted the canvas may be gone now. Re-anchor on
            // a display that still exists before the frame is computed.
            dropScreenFrame = Self.screenFrame(containing: NSEvent.mouseLocation)
                ?? placement.screenFrame
        }
        let target = targetFrame
        render(panelFrame: target)
        if isOnScreen {
            panel.setFrame(target, display: true)
        }
        logState(tag: "screens")
        logProof(tag: "screens")
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible, !isHidingPanel, !isPickerActive else { return }
        onLostFocus?()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.panel else { return event }
            return MainActor.assumeIsolated { self.handleKey(event) }
        }
    }

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshMousePolicy() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown:
                self.isPointerDown = true
            case .leftMouseUp:
                self.isPointerDown = false
            default:
                self.followDropPointer()
            }
            self.refreshMousePolicy()
            return event
        }
    }

    /// A drop canvas can only render on the Space of one display, so while the
    /// drag is live the panel follows the pointer's display. Without this the
    /// droplet and the composer are drawn on a display the window is not on,
    /// and the user sees nothing. The move is deferred one runloop turn because
    /// relocating the window changes the coordinates of the event in flight.
    private func followDropPointer() {
        guard presentation.surface == .drop, isPointerDown else { return }
        guard let screen = Self.screenFrame(containing: NSEvent.mouseLocation),
              screen != dropScreenFrame else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.presentation.surface == .drop,
                  self.isPointerDown,
                  let current = Self.screenFrame(containing: NSEvent.mouseLocation),
                  current != self.dropScreenFrame else { return }
            self.dropScreenFrame = current
            self.animator?.cancel()
            let target = self.targetFrame
            self.render(panelFrame: target, surfaceMotion: false)
            self.panel.setFrame(target, display: true)
            self.refreshMousePolicy()
        }
    }

    /// The ambient window carries a transparent lip for the droplet. Only the
    /// bar and the drop itself may take clicks; everything else falls through
    /// to the app underneath.
    private func refreshMousePolicy() {
        guard panel.isVisible, isOnScreen else {
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
            return
        }
        guard presentation.surface == .ambient,
              !presentation.isExpanded,
              !presentation.isWindowDragActive else {
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
            return
        }

        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        guard frame.contains(mouse) else {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }

        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let band = notchBandHeight
        let insideBar = local.y >= 0 && local.y <= band && local.x >= 0 && local.x <= frame.width
        let droplet = CGPoint(x: frame.width / 2, y: band + 10)
        let insideDroplet = presentation.dropletVisible
            && hypot(local.x - droplet.x, local.y - droplet.y) <= 22
        let shouldIgnore = !(insideBar || insideDroplet)
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    private var notchBandHeight: CGFloat {
        if case .notch(let rect, _) = placement { return rect.height }
        return 28
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if IslandTerminalNSView.containsResponder(panel.firstResponder) {
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "w" {
                actions.backToDeck()
                return nil
            }
            return event
        }
        // Marked text means an IME composition is in progress. Escape and
        // Return belong to the composition, not to the island.
        if let editor = panel.fieldEditor(false, for: nil) as? NSTextView,
           editor.hasMarkedText() {
            return event
        }

        guard let stroke = KeyStroke(event: event) else { return event }

        if presentation.drop != nil {
            if stroke.key == .escape {
                // The overlay owns the composer's close motion: fade the card,
                // send a detached drop home over 520 ms, then clear the drop.
                NotificationCenter.default.post(name: .herdrDropEscape, object: nil)
                return nil
            }
            if stroke.key == .return, stroke.modifiers.contains(.command) {
                actions.submitDropTask()
                return nil
            }
            return event
        }

        if presentation.quickTask != nil {
            if stroke.key == .escape {
                actions.closeQuickTask()
                return nil
            }
            if stroke.key == .return, stroke.modifiers.contains(.command) {
                actions.submitQuickTask()
                return nil
            }
            return event
        }

        if presentation.windowTask != nil {
            if stroke.key == .escape {
                onEvent?(.escape)
                return nil
            }
            if stroke.key == .return, stroke.modifiers.contains(.command) {
                actions.submitWindowTask()
                return nil
            }
            return event
        }

        if presentation.isSearching {
            switch stroke.key {
            case .upArrow:
                onEvent?(.moveSelection(-1))
                return nil
            case .downArrow:
                onEvent?(.moveSelection(1))
                return nil
            case .return:
                if let selected = presentation.selected {
                    actions.openDetail(selected.id)
                }
                return nil
            case .escape:
                actions.setSearching(false)
                return nil
            default:
                return event
            }
        }

        if !presentation.isComposerFocused,
           !stroke.modifiers.contains(.command),
           !stroke.modifiers.contains(.control),
           !stroke.modifiers.contains(.option),
           let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "/":
                actions.openDeck()
                actions.setSearching(true)
                return nil
            case "r":
                guard let selected = presentation.selected, selected.status != .blocked else {
                    return nil
                }
                actions.composerFocus(true)
                return nil
            case "s":
                guard let selected = presentation.selected else { return nil }
                actions.snooze(selected.id)
                return nil
            default:
                break
            }
        }

        let command = KeyboardRouter.route(
            stroke,
            composerFocused: presentation.isComposerFocused
        )
        switch command {
        case .toggle:
            return event
        case .dismiss:
            onEvent?(.escape)
            return nil
        case .openDetail:
            if let selected = presentation.selected {
                actions.openDetail(selected.id)
            }
            return nil
        case .send:
            onEvent?(.sendMessage)
            return nil
        case .moveSelection(let delta):
            onEvent?(.moveSelection(delta))
            return nil
        case .focusComposer:
            onEvent?(.setComposerFocus(true))
            return nil
        case .passThrough:
            return event
        }
    }

    private func logState(tag: String) {
        let metrics = ScreenMetrics.current()
        appLog(
            "[\(tag)] screen=\(NSStringFromRect(metrics.screenFrame)) safeTop=\(metrics.safeAreaTop) "
            + "placement=\(placement.isNotch ? "notch" : "menuBar") "
            + "panelLevel=\(panel.level.rawValue) frame=\(NSStringFromRect(panel.frame)) "
            + "isVisible=\(panel.isVisible) expanded=\(presentation.isExpanded) "
            + "quickTask=\(presentation.quickTask != nil) headline=\(presentation.headline)"
        )
    }

    private func logProof(tag: String) {
        appLog(
            "[\(tag)] panel level=\(panel.level.rawValue) frame=\(NSStringFromRect(panel.frame)) "
            + "isVisible=\(panel.isVisible)"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] ?? []
            let windowNumber = self.panel.windowNumber
            let mine = windows.filter {
                ($0[kCGWindowNumber as String] as? Int) == windowNumber
            }
            if mine.isEmpty {
                appLog(
                    "[\(tag)] cgwindow proof: no on-screen window \(windowNumber) "
                    + "(isVisible=\(self.panel.isVisible))"
                )
            }
            for window in mine {
                let number = window[kCGWindowNumber as String] ?? "?"
                let layer = window[kCGWindowLayer as String] ?? "?"
                let bounds = window[kCGWindowBounds as String] ?? "?"
                appLog("[\(tag)] cgwindow number=\(number) layer=\(layer) bounds=\(bounds)")
            }
        }
    }
}

extension Notification.Name {
    /// Escape while a drop composer is up. The overlay animates the card away
    /// and the drop home before asking the store to clear the drop.
    static let herdrDropEscape = Notification.Name("HerdrIsland.dropEscape")
}

extension KeyStroke {
    init?(event: NSEvent) {
        var modifiers: KeyModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.function) { modifiers.insert(.function) }

        let key: Key
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .return
        case 48: key = .tab
        case 126: key = .upArrow
        case 125: key = .downArrow
        default: key = .other
        }
        self.init(key: key, modifiers: modifiers)
    }
}

extension ScreenMetrics {
    @MainActor
    static func current() -> ScreenMetrics {
        guard let screen = preferredScreen() else {
            return ScreenMetrics(
                screenFrame: .zero,
                visibleFrame: .zero,
                safeAreaTop: 0,
                auxTopLeft: nil,
                auxTopRight: nil
            )
        }
        return ScreenMetrics(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxTopLeft: screen.auxiliaryTopLeftArea,
            auxTopRight: screen.auxiliaryTopRightArea
        )
    }

    /// The display under the pointer, where a transient modal should open.
    /// Falls back to the main display, then the first one.
    @MainActor
    static func activeScreenFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.frame ?? .zero
    }

    @MainActor
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
