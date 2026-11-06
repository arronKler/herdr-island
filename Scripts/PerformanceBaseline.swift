import AppKit
import Carbon
import Darwin
import Foundation
import HerdrKit
import ImageIO
import IslandCore
import ScreenCaptureKit
import UniformTypeIdentifiers

// Linked against a frozen copy of the actual release libraries by the Python
// runner. This audit does not alter production settings or application code.
@MainActor
final class Baseline {
    var rows: [String: [String: Any]] = [:]
    var metadata: [String: Any] = [:]
    var notes: [String] = []
    var checksum = 0
    let output: URL
    let environment: HerdrEnvironment
    let cli: HerdrCLI
    let legacy: HerdrCLI

    init(output: URL) throws {
        self.output = output
        environment = try HerdrLocator.resolve()
        cli = HerdrCLI(binary: environment.binary, socketURL: environment.socket)
        legacy = HerdrCLI(binary: environment.binary)
    }

    func add(_ key: String, ms: Double, error: Error? = nil, kind: String = "live") {
        var row = rows[key] ?? ["samples_ms": [Double](), "failed_ms": [Double](), "errors": [String](), "kind": kind]
        if let error {
            row["failed_ms"] = (row["failed_ms"] as! [Double]) + [ms]
            let code = (error as? BackendFailure)?.kind.rawValue ?? "\((error as NSError).domain):\((error as NSError).code)"
            row["errors"] = (row["errors"] as! [String]) + [code]
        } else {
            row["samples_ms"] = (row["samples_ms"] as! [Double]) + [ms]
        }
        rows[key] = row
    }

    func measure(_ key: String, n: Int, kind: String = "live", _ body: () async throws -> Int) async {
        for _ in 0..<n {
            let start = ContinuousClock.now
            do { checksum &+= try await body(); add(key, ms: Self.ms(start), kind: kind) }
            catch { add(key, ms: Self.ms(start), error: error, kind: kind) }
        }
        print("measured \(key)")
        try? save()
    }

    func sync(_ key: String, n: Int, _ body: () throws -> Int) {
        for _ in 0..<n {
            let start = ContinuousClock.now
            do { checksum &+= try body(); add(key, ms: Self.ms(start), kind: "local_wall") }
            catch { add(key, ms: Self.ms(start), error: error, kind: "local_wall") }
        }
        print("measured \(key)")
    }

    static func ms(_ start: ContinuousClock.Instant) -> Double {
        let c = start.duration(to: .now).components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1e15
    }

    func save() throws {
        var results = rows
        for (key, row) in rows {
            let values = (row["samples_ms"] as! [Double]).sorted()
            var item = row
            item["n"] = values.count
            item["failures"] = (row["failed_ms"] as! [Double]).count
            if !values.isEmpty {
                item["first_ms"] = (row["samples_ms"] as! [Double])[0]
                item["median_ms"] = (values[(values.count - 1) / 2] + values[values.count / 2]) / 2
                item["min_ms"] = values.first!
                item["max_ms"] = values.last!
                item["p95_ms"] = values.count >= 20 ? values[Int(ceil(Double(values.count) * 0.95)) - 1] as Any : NSNull()
            }
            results[key] = item
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "metadata": metadata, "metrics": results, "notes": notes, "checksum": checksum,
        ], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output, options: .atomic)
    }

    func readPaths() async throws {
        let agents = try await cli.listAgents()
        metadata["agent_count"] = agents.count
        metadata["preview_lines"] = IslandRules.default.previewLines
        await measure("agents.socket", n: 25) { try await self.cli.listAgents().count }
        await measure("agents.cli", n: 25) { try await self.legacy.listAgents().count }
        await measure("directory.focused", n: 25) { try await self.cli.focusedPaneCwd()?.count ?? 0 }
        await measure("directory.choices", n: 25) { try await self.cli.paneCwds().count }
        if let pane = agents.first(where: { $0.status == .working })?.pane ?? agents.first?.pane {
            await measure("preview.working_recent_60_lines", n: 25) {
                try await self.cli.readPreview(pane: pane, lines: IslandRules.default.previewLines).utf8.count
            }
            await measure("preview.working_visible_60_lines", n: 25) {
                try await Self.backgroundCommand(self.environment.binary, ["agent", "read", pane.rawValue, "--source", "visible", "--lines", "60", "--format", "text"]).count
            }
        }
        if let pane = agents.first(where: { $0.acceptsPrompt })?.pane {
            await measure("preview.idle_recent_60_lines", n: 25) {
                try await self.cli.readPreview(pane: pane, lines: IslandRules.default.previewLines).utf8.count
            }
        }
        await measure("service.first_snapshot", n: 20) {
            let service = HerdrService(cli: self.cli, socketURL: self.environment.socket)
            let stream = await service.start()
            var count = 0
            for await event in stream {
                if case .snapshot(let snapshot) = event { count = snapshot.agents.count; break }
                if case .sampleFailed(let error) = event { await service.stop(); throw error }
            }
            await service.stop()
            return count
        }
        for n in [max(agents.count, 1), 100, 500] { cpuPaths(count: n) }
        previewInvalidation()
        sync("terminal.normalize_60x160", n: 200) {
            TerminalText.lines(from: String(repeating: String(repeating: "x", count: 160) + "\n", count: 60)).count
        }
        sync("terminal.normalize_1000x160", n: 100) {
            TerminalText.lines(from: String(repeating: String(repeating: "x", count: 160) + "\n", count: 1000)).count
        }
    }

    func previewInvalidation() {
        let now = Date()
        let pane = PaneID("baseline-preview")
        let agent = Agent(pane: pane, workspace: "probe", kind: "claude", title: "Probe", project: "probe", status: .working)
        var state = IslandState()
        _ = IslandReducer.reduce(&state, .snapshot(AgentSnapshot(generation: 1, sampledAt: now, agents: [agent])), now: now)
        _ = IslandReducer.reduce(&state, .openDetail(pane), now: now)
        var reloads = 0
        var loading = 0
        for generation in 2...11 {
            _ = IslandReducer.reduce(&state, .previewResult(pane, .success("Unchanged preview")), now: now)
            let effects = IslandReducer.reduce(&state, .snapshot(AgentSnapshot(generation: UInt64(generation), sampledAt: now, agents: [agent])), now: now)
            reloads += effects.filter { if case .loadPreview = $0 { return true }; return false }.count
            if case .loading = state.previews[pane] { loading += 1 }
        }
        metadata["preview_unchanged_snapshot_probe"] = ["snapshots": 10, "reload_effects": reloads, "loading_states": loading]
    }

    func cpuPaths(count: Int) {
        let now = Date()
        let agents = (0..<count).map { index in
            Agent(pane: PaneID("baseline:\(index)"), workspace: "w\(index)", kind: "claude",
                  title: "Synthetic task \(index)", project: "project-\(index % 8)",
                  status: index.isMultiple(of: 5) ? .blocked : .working, stateChangeSeq: 1)
        }
        var state = IslandState()
        var generation: UInt64 = 1
        _ = IslandReducer.reduce(&state, .snapshot(AgentSnapshot(generation: generation, sampledAt: now, agents: agents)), now: now)
        _ = IslandReducer.reduce(&state, .openDeck, now: now)
        _ = IslandReducer.reduce(&state, .setFilter(.all), now: now)
        sync("state.snapshot_present_n\(count)", n: 100) {
            generation += 1
            let effects = IslandReducer.reduce(&state, .snapshot(AgentSnapshot(generation: generation, sampledAt: now, agents: agents)), now: now)
            return effects.count + IslandPresenter.present(state, now: now).rows.count
        }
        var query = false
        sync("state.search_present_n\(count)", n: 100) {
            query.toggle()
            _ = IslandReducer.reduce(&state, .setQuery(query ? "task" : "project-1"), now: now)
            return IslandPresenter.present(state, now: now).deckRows.count
        }
        _ = IslandReducer.reduce(&state, .openQuickTask(cwd: "/tmp", kind: .claude), now: now)
        sync("state.draft_present_n\(count)", n: 100) {
            query.toggle()
            _ = IslandReducer.reduce(&state, .setQuickTaskDraft(query ? "Fix the slow path" : "Fix the slow paths"), now: now)
            return IslandPresenter.present(state, now: now).rows.count
        }
        var liveTime = now
        sync("state.draft_present_live_clock_n\(count)", n: 100) {
            liveTime = liveTime.addingTimeInterval(0.017)
            query.toggle()
            _ = IslandReducer.reduce(&state, .setQuickTaskDraft(query ? "Fix the slow path" : "Fix the slow paths"), now: liveTime)
            return IslandPresenter.present(state, now: liveTime).rows.count
        }
        _ = IslandReducer.reduce(&state, .closeQuickTask, now: now)
        var changedAgents = agents
        sync("state.changed_snapshot_present_n\(count)", n: 100) {
            generation += 1
            liveTime = liveTime.addingTimeInterval(0.017)
            let index = Int(generation) % count
            let agent = changedAgents[index]
            changedAgents[index] = Agent(pane: agent.pane, workspace: agent.workspace,
                kind: agent.kind, title: agent.title, project: agent.project, status: agent.status,
                stateChangeSeq: agent.stateChangeSeq, lastLine: "Output revision \(generation)")
            _ = IslandReducer.reduce(&state, .snapshot(AgentSnapshot(generation: generation, sampledAt: liveTime, agents: changedAgents)), now: liveTime)
            return IslandPresenter.present(state, now: liveTime).rows.count
        }
    }

    func windowPaths() async throws {
        let info = CommandLine.arguments.first(where: { $0.hasPrefix("--fixture-info=") })
            .map { URL(fileURLWithPath: String($0.dropFirst("--fixture-info=".count))) }
        if let info { try Data().write(to: info.appendingPathExtension("show")) }
        defer { if let info { try? Data().write(to: info.appendingPathExtension("hide")) } }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let window = NSPanel(contentRect: NSRect(x: 40, y: 80, width: 1000, height: 650),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.backgroundColor = .white
        let label = NSTextField(labelWithString: "Herdr Island performance baseline — synthetic window")
        label.frame = NSRect(x: 30, y: 300, width: 900, height: 40)
        window.contentView?.addSubview(label)
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        let id: CGWindowID
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--window=") }),
           let provided = UInt32(argument.dropFirst("--window=".count)) { id = provided }
        else { id = CGWindowID(window.windowNumber) }
        let height = CGDisplayBounds(CGMainDisplayID()).height
        guard let targetEntries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let targetEntry = targetEntries.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              let targetRaw = targetEntry[kCGWindowBounds as String] as? NSDictionary,
              let targetBounds = CGRect(dictionaryRepresentation: targetRaw as CFDictionary) else {
            throw BackendFailure(.windowUnavailable, "Synthetic fixture has no window description.")
        }
        let fixtureBounds = ScreenCoordinates.appKitRect(fromQuartz: targetBounds, primaryDisplayHeight: height)
        let point = CGPoint(x: fixtureBounds.midX, y: fixtureBounds.midY)
        metadata["screen_recording_authorized"] = CGPreflightScreenCaptureAccess()
        metadata["display_count"] = NSScreen.screens.count
        sync("window.hit_test_enumerate_map", n: 100) {
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            self.metadata["onscreen_window_count"] = entries.count
            let windows = entries.compactMap { entry -> WindowInfo? in
                guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                      let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                      let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
                return WindowInfo(windowID: number.uint32Value, ownerPID: owner.int32Value,
                                  appName: entry[kCGWindowOwnerName as String] as? String ?? "",
                                  title: entry[kCGWindowName as String] as? String,
                                  bounds: ScreenCoordinates.appKitRect(fromQuartz: bounds, primaryDisplayHeight: height),
                                  layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                  alpha: CGFloat((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1))
            }
            let hit = WindowHitTester.target(at: point, in: windows, excludingPID: -1)
            if let hit { _ = NSRunningApplication(processIdentifier: hit.ownerPID)?.bundleIdentifier }
            return windows.count
        }
        sync("window.follow_single_description", n: 100) {
            let entries = CGWindowListCreateDescriptionFromArray([NSNumber(value: id)] as CFArray) as? [[String: Any]]
            guard let entries, entries.contains(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }) else {
                throw BackendFailure(.windowUnavailable, "The old description API returned no matching window.")
            }
            return entries.count
        }
        sync("window.follow_single_validated", n: 100) {
            let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
            guard let entries, entries.contains(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }) else {
                throw BackendFailure(.windowUnavailable, "No matching window.")
            }
            return entries.count
        }
        let drag = WindowDragCoordinator(excludingPID: ProcessInfo.processInfo.processIdentifier)
        drag.begin()
        let firstCandidate = ContinuousClock.now
        while drag.update(at: point)?.windowID != id {
            if firstCandidate.duration(to: .now) > .seconds(2) {
                drag.cancel()
                throw BackendFailure(.windowUnavailable, "Drag did not resolve the synthetic fixture.")
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        add("window.drag_first_candidate", ms: Self.ms(firstCandidate), kind: "production_first_candidate")
        sync("window.drag_cached_update", n: 100) {
            guard drag.update(at: point)?.windowID == id else { throw BackendFailure(.windowUnavailable, "Wrong drag target.") }
            return 1
        }
        sync("window.drop_fresh_hit", n: 25) {
            guard drag.end(at: point)?.windowID == id else { throw BackendFailure(.windowUnavailable, "Wrong drop target.") }
            return 1
        }
        drag.cancel()
        guard CGPreflightScreenCaptureAccess() else {
            notes.append("ScreenCaptureKit capture skipped: permission not already granted; no prompt requested.")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-capture-baseline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Equivalent capture stages, using only our own synthetic window and a
        // temporary destination. Production capture pruning is not invoked.
        for index in 0..<20 {
            let total = ContinuousClock.now
            do {
                var start = ContinuousClock.now
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                add("capture.enumerate", ms: Self.ms(start), kind: "equivalent_pipeline")
                guard let target = content.windows.first(where: { $0.windowID == id }) else { throw BackendFailure(.windowUnavailable, "probe missing") }
                metadata["capture_target_onscreen"] = target.isOnScreen
                metadata["capture_target_point_size"] = [target.frame.width, target.frame.height]
                let configuration = SCStreamConfiguration()
                configuration.showsCursor = false
                configuration.captureResolution = .best
                let scale = CommandLine.arguments.first(where: { $0.hasPrefix("--fixture-scale=") })
                    .flatMap { Double($0.dropFirst("--fixture-scale=".count)) } ?? 2
                let width = max(1, target.frame.width * scale)
                let height = max(1, target.frame.height * scale)
                let reduction = min(1, 4096 / max(width, height))
                configuration.width = max(1, Int((width * reduction).rounded()))
                configuration.height = max(1, Int((height * reduction).rounded()))
                metadata["capture_config_pixel_size"] = [configuration.width, configuration.height]
                start = .now
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
                add("capture.image", ms: Self.ms(start), kind: "equivalent_pipeline")
                metadata["capture_pixel_size"] = [image.width, image.height]
                start = .now
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                add("capture.png_encode", ms: Self.ms(start), kind: "equivalent_pipeline")
                start = .now
                try (data as Data).write(to: directory.appendingPathComponent("probe-\(index).png"), options: .atomic)
                add("capture.write", ms: Self.ms(start), kind: "equivalent_pipeline")
                add("capture.total", ms: Self.ms(total), kind: "equivalent_pipeline")
                metadata["capture_png_bytes"] = data.length
            } catch { add("capture.total", ms: Self.ms(total), error: error, kind: "equivalent_pipeline") }
        }
        print("measured capture stages")
        // The production lookup only caches metadata, validates the current
        // owner/size on every hit, and always captures fresh pixels on submit.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        if let window = content.windows.first(where: { $0.windowID == id }),
           let owner = window.owningApplication {
            let target = WindowTarget(windowID: id, ownerPID: owner.processID, appName: "Synthetic fixture",
                bounds: ScreenCoordinates.appKitRect(fromQuartz: window.frame, primaryDisplayHeight: height))
            await measure("capture.lookup_cold", n: 1, kind: "production_metadata_cold") {
                Int(try await WindowCaptureLookup.shared.window(for: target).windowID)
            }
            await measure("capture.lookup_validated_cached", n: 25, kind: "production_metadata_cached") {
                Int(try await WindowCaptureLookup.shared.window(for: target).windowID)
            }
            await measure("capture.production_total", n: 20, kind: "production_temporary_destination") {
                switch await WindowCaptureService.capture(target, in: directory) {
                case .success(let path): return (try Data(contentsOf: URL(fileURLWithPath: path))).count
                case .failure(let failure): throw failure
                }
            }
        }
        try save()
    }

    func automationPermission() -> OSStatus {
        var target = AEAddressDesc()
        let bytes = Array("com.mitchellh.ghostty".utf8)
        let status = bytes.withUnsafeBytes { AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &target) }
        guard status == noErr else { return OSStatus(status) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
    }

    func focusComponents() async {
        sync("focus.locate_application", n: 25) {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") == nil ? 0 : 1
        }
        await measure("focus.process_scan", n: 25) {
            try await Self.backgroundCommand(URL(fileURLWithPath: "/bin/ps"), ["-ax", "-o", "tty=,command="]).count
        }
        let permission = automationPermission()
        metadata["ghostty_automation_permission"] = permission
        guard permission == noErr else {
            notes.append("Ghostty AppleScript/full jump skipped: automation permission not already granted.")
            return
        }
        sync("focus.applescript_read_on_main", n: 25) {
            let script = NSAppleScript(source: "tell application \"Ghostty\" to get count of terminals")!
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error { throw NSError(domain: "AppleScript", code: (error["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? -1) }
            return Int(result.int32Value)
        }
    }

    func liveTasks() async throws {
        let service = HerdrService(cli: cli, socketURL: environment.socket)
        _ = await service.start()
        let recorder = ProbePanes(journal: output.appendingPathExtension("probes.json"))
        var last: PaneID?
        for index in 0..<3 {
            let start = ContinuousClock.now
            let result = await service.createTask(QuickTaskRequest(
                name: "island-baseline-\(UUID().uuidString.prefix(6).lowercased())",
                text: "Reply exactly BASELINE_READY. Do not use tools, edit files, or run commands.",
                kind: .claude, cwd: FileManager.default.currentDirectoryPath, label: "Island baseline probe"
            )) { progress in await recorder.record(progress, start: start) }
            switch result {
            case .success(let launch):
                if launch.agent?.status == .blocked {
                    add("task.cold_confirm", ms: Self.ms(start), error: BackendFailure(.agentBlocked, "approval required"))
                } else {
                    add("task.cold_confirm", ms: Self.ms(start))
                    last = launch.pane
                }
            case .failure(let failure):
                add("task.cold_confirm", ms: Self.ms(start), error: failure)
                notes.append("Controlled task \(index + 1): \(failure.kind.rawValue): \(failure.message)")
            }
            if case .success(let launch) = result, launch.agent?.status != .blocked {
                do {
                    _ = try await waitIdle(launch.pane, after: 0)
                    add("task.first_completion", ms: Self.ms(start))
                } catch { add("task.first_completion", ms: Self.ms(start), error: error) }
            }
            print("measured cold task \(index + 1)/3")
            metadata["owned_probe_panes"] = await recorder.panes.map(\.rawValue).sorted()
            try? save()
        }
        if let pane = last, !CommandLine.arguments.contains("--tasks-only") {
            do {
                var previous = try await waitIdle(pane, after: 0)
                for _ in 0..<5 {
                    let before = previous.completionSeq ?? 0
                    await measure("reply.existing_agent_ack", n: 1) {
                        try await self.cli.prompt(pane: pane, text: "Reply exactly BASELINE_REPLY. Do not use tools, edit files, or run commands.")
                        return 1
                    }
                    previous = try await waitIdle(pane, after: before)
                }
                if automationPermission() == noErr {
                    // Focus only the probe and restore the original Herdr pane/app.
                    let panes = try Self.command(environment.binary, ["pane", "list"])
                    let object = try JSONSerialization.jsonObject(with: panes) as? [String: Any]
                    let result = object?["result"] as? [String: Any]
                    let original = (result?["panes"] as? [[String: Any]])?.first { $0["focused"] as? Bool == true }?["pane_id"] as? String
                    let front = NSWorkspace.shared.frontmostApplication
                    let terminalQuery = "tell application \"Ghostty\" to get id of focused terminal of selected tab of front window"
                    var terminalError: NSDictionary?
                    let originalTerminal = NSAppleScript(source: terminalQuery)?.executeAndReturnError(&terminalError).stringValue
                    if let original, terminalError == nil, let originalTerminal, !originalTerminal.isEmpty {
                        await measure("focus.full_jump", n: 5) {
                            switch await service.focusPane(pane) {
                            case .success: return 1
                            case .failure(let error): throw error
                            }
                        }
                        do { try await cli.focus(pane: PaneID(original)) }
                        catch { notes.append("Could not restore the original Herdr pane after jump probes.") }
                        let escaped = originalTerminal.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                        _ = NSAppleScript(source: "tell application \"Ghostty\" to focus (first terminal whose id is \"\(escaped)\")")?
                            .executeAndReturnError(&terminalError)
                        let restored = NSAppleScript(source: terminalQuery)?.executeAndReturnError(&terminalError).stringValue
                        metadata["original_ghostty_terminal_restored"] = terminalError == nil && restored == originalTerminal
                        if restored != originalTerminal || terminalError != nil { notes.append("Could not verify restoration of the original Ghostty terminal.") }
                        front?.activate(options: [])
                    } else {
                        notes.append("Full jump skipped because the original pane/terminal could not be identified for restoration.")
                    }
                }
            } catch { notes.append("Probe continuation unavailable: \((error as? BackendFailure)?.kind.rawValue ?? "other")") }
        }
        if CommandLine.arguments.contains("--live-multiline") {
            let start = ContinuousClock.now
            let result = await service.createTask(QuickTaskRequest(
                name: "island-baseline-\(UUID().uuidString.prefix(6).lowercased())",
                text: "Reply exactly BASELINE_MULTILINE_READY.\nDo not use tools, edit files, or run commands.",
                kind: .claude, cwd: FileManager.default.currentDirectoryPath, label: "Island multiline probe"
            )) { progress in await recorder.record(progress, start: start) }
            switch result {
            case .success(let launch):
                if launch.agent?.status == .blocked {
                    add("task.multiline_confirm", ms: Self.ms(start), error: BackendFailure(.agentBlocked, "approval required"))
                } else {
                    add("task.multiline_confirm", ms: Self.ms(start))
                    do {
                        _ = try await waitIdle(launch.pane, after: 0)
                        add("task.multiline_first_completion", ms: Self.ms(start))
                    } catch { add("task.multiline_first_completion", ms: Self.ms(start), error: error) }
                }
            case .failure(let failure):
                add("task.multiline_confirm", ms: Self.ms(start), error: failure)
                notes.append("Controlled multiline task: \(failure.kind.rawValue): \(failure.message)")
            }
            print("measured multiline task")
            metadata["owned_probe_panes"] = await recorder.panes.map(\.rawValue).sorted()
            try? save()
        }
        await service.stop()
        for ms in await recorder.workspaceTimes { add("task.workspace", ms: ms) }
        var closed = 0
        for pane in await recorder.panes {
            do {
                let data = try Self.command(environment.binary, ["pane", "get", pane.rawValue])
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let result = object?["result"] as? [String: Any]
                let entry = result?["pane"] as? [String: Any]
                guard let workspace = entry?["workspace_id"] as? String else { continue }
                _ = try Self.command(environment.binary, ["workspace", "close", workspace])
                closed += 1
                await recorder.forget(pane)
            } catch { notes.append("Probe cleanup failed for owned pane \(pane.rawValue)") }
        }
        metadata["probe_workspaces_closed"] = closed
        metadata.removeValue(forKey: "owned_probe_panes")
        try save()
    }

    func waitIdle(_ pane: PaneID, after sequence: UInt64) async throws -> Agent {
        let deadline = ContinuousClock.now.advanced(by: .seconds(40))
        while ContinuousClock.now < deadline {
            if let agent = try await cli.listAgents().first(where: { $0.pane == pane }) {
                if agent.status == .blocked { throw BackendFailure(.agentBlocked, "approval required") }
                if agent.acceptsPrompt, (agent.completionSeq ?? 0) > sequence { return agent }
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw BackendFailure(.timeout, "probe did not complete")
    }

    nonisolated static func backgroundCommand(_ binary: URL, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try command(binary, arguments) })
            }
        }
    }

    nonisolated static func command(_ binary: URL, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BackendFailure(.commandFailed, "probe command failed") }
        return data
    }
}

private actor ProbePanes {
    let journal: URL
    var panes: Set<PaneID> = []
    var workspaceTimes: [Double] = []
    init(journal: URL) { self.journal = journal }
    func persist() {
        if panes.isEmpty { try? FileManager.default.removeItem(at: journal); return }
        if let data = try? JSONSerialization.data(withJSONObject: panes.map(\.rawValue).sorted()) {
            try? data.write(to: journal, options: .atomic)
        }
    }
    func forget(_ pane: PaneID) { panes.remove(pane); persist() }
    func record(_ progress: TaskCreationProgress, start: ContinuousClock.Instant) {
        if let pane = progress.pane { panes.insert(pane); persist() }
        if progress.stage == .agent {
            let c = start.duration(to: .now).components
            workspaceTimes.append(Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15)
        }
    }
}

@main
enum PerformanceBaseline {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let output = URL(fileURLWithPath: CommandLine.arguments[1])
                let baseline = try Baseline(output: output)
                baseline.metadata["appkit_run_loop"] = true
                if !CommandLine.arguments.contains("--tasks-only") {
                    if !CommandLine.arguments.contains("--capture-only") { try await baseline.readPaths() }
                    try await baseline.windowPaths()
                    if !CommandLine.arguments.contains("--capture-only") { await baseline.focusComponents() }
                }
                if CommandLine.arguments.contains("--live-tasks") { try await baseline.liveTasks() }
                try baseline.save()
                print("baseline complete: \(output.path)")
                exit(0)
            } catch {
                fputs("baseline failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }
}
