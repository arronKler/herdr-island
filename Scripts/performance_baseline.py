#!/usr/bin/env python3
"""Measure a frozen release, without rebuilding or changing the running app.

Default: local read paths, pure state transformations, and a synthetic window.
--live-tasks additionally creates three harmless Claude probes, sends follow-up
prompts only to the owned probe, and cleans up those workspaces.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / "Sources").rglob("*.swift"))}


def summarize(values):
    ordered = sorted(values)
    return {
        "samples_ms": values, "n": len(values), "failures": 0,
        "first_ms": values[0], "median_ms": statistics.median(values),
        "p95_ms": ordered[math.ceil(len(values) * .95) - 1] if len(values) >= 20 else None,
        "min_ms": min(values), "max_ms": max(values), "kind": "fresh_process_read_state",
    }


def host():
    commands = run(["ps", "-axo", "comm"]).splitlines()
    return {"load_average": os.getloadavg(), "swift_frontend_count": sum(x.endswith("/swift-frontend") for x in commands)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--live-tasks", action="store_true")
    parser.add_argument("--live-multiline", action="store_true", help="Also verify one new multiline Claude task; requires --live-tasks")
    parser.add_argument("--capture-only", action="store_true")
    parser.add_argument("--tasks-only", action="store_true", help="Verify task creation only, skipping existing-agent replies/focus; requires --live-tasks")
    parser.add_argument("--allow-stale-artifacts", action="store_true",
                        help="Audit the installed release even when source edits are newer; recorded in the manifest")
    args = parser.parse_args()
    if args.live_multiline and not args.live_tasks:
        parser.error("--live-multiline requires --live-tasks")
    if args.tasks_only and (not args.live_tasks or args.capture_only):
        parser.error("--tasks-only requires --live-tasks and cannot be combined with --capture-only")
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    products = ROOT / ".build/out/Products/Release"
    app = ROOT / "build/HerdrIsland.app"
    artifacts = [products / f"lib{module}.a" for module in ["HerdrKit", "IslandCore"]]
    artifacts.append(app / "Contents/MacOS/HerdrIsland")
    for path in artifacts:
        if not path.exists():
            raise SystemExit(f"Missing release artifact: {path}. Build it explicitly first.")
    start_sources = sources()
    manifest = {
        "git_head": run(["git", "rev-parse", "HEAD"], cwd=ROOT),
        "working_tree_dirty": bool(run(["git", "status", "--porcelain"], cwd=ROOT)),
        "source_sha256": start_sources,
        "artifact_sha256": {str(p.relative_to(ROOT)): sha(p) for p in artifacts},
        "system": run(["sw_vers"]), "machine": run(["sysctl", "-n", "hw.model"]),
        "logical_cpus": int(run(["sysctl", "-n", "hw.ncpu"])),
        "memory_bytes": int(run(["sysctl", "-n", "hw.memsize"])),
        "swift_version": run(["swift", "--version"]), "herdr_version": run(["herdr", "--version"]),
        "host_before": host(), "live_tasks_enabled": args.live_tasks, "live_multiline_enabled": args.live_multiline,
        "tasks_only": args.tasks_only,
        "measurement_basis": "Frozen prebuilt release libraries/application; not a clean HEAD checkout.",
    }
    manifest["sources_newer_than_library"] = [
        str(p.relative_to(ROOT))
        for module in ["IslandCore", "HerdrKit"]
        for p in (ROOT / "Sources" / module).glob("*.swift")
        if p.stat().st_mtime > (products / f"lib{module}.a").stat().st_mtime
    ]
    if manifest["sources_newer_than_library"] and not args.allow_stale_artifacts:
        raise SystemExit("Release libraries are stale; build explicitly before measuring: " + ", ".join(manifest["sources_newer_than_library"]))
    with tempfile.TemporaryDirectory(prefix="island-baseline-") as temporary:
        snapshot = Path(temporary)
        for module in ["HerdrKit", "IslandCore"]:
            shutil.copy2(products / f"lib{module}.a", snapshot)
            shutil.copytree(products / f"{module}.swiftmodule", snapshot / f"{module}.swiftmodule")
        shutil.copytree(app, snapshot / "HerdrIsland.app")
        frozen_app_path = snapshot / "HerdrIsland.app/Contents/MacOS/HerdrIsland"
        if sha(frozen_app_path) != manifest["artifact_sha256"][str(artifacts[-1].relative_to(ROOT))]:
            raise SystemExit("Application changed during snapshot; retry after packaging completes")
        harness = snapshot / "PerformanceBaseline.swift"
        shutil.copy2(ROOT / "Scripts/PerformanceBaseline.swift", harness)
        fixture_source = snapshot / "PerformanceWindow.swift"
        shutil.copy2(ROOT / "Scripts/PerformanceWindow.swift", fixture_source)
        manifest["harness_sha256"] = sha(harness)
        manifest["fixture_sha256"] = sha(fixture_source)
        manifest["runner_sha256"] = sha(Path(__file__))
        capture_sources = []
        for name in ["WindowCaptureLookup.swift", "WindowCaptureService.swift", "WindowDragCoordinator.swift"]:
            source = ROOT / "Sources/IslandApp" / name
            shutil.copy2(source, snapshot / name)
            capture_sources.append(str(snapshot / name))
        manifest["capture_source_sha256"] = {Path(p).name: sha(Path(p)) for p in capture_sources}
        for module in ["HerdrKit", "IslandCore"]:
            original = products / f"lib{module}.a"
            if sha(snapshot / original.name) != manifest["artifact_sha256"][str(original.relative_to(ROOT))]:
                raise SystemExit("Release artifacts changed during snapshot; retry after the build completes")
        binary = snapshot / "baseline"
        command = [
            "swiftc", "-parse-as-library", "-O", "-swift-version", "5",
            "-target", f"{platform.machine()}-apple-macosx14.0", "-I", str(snapshot),
            str(harness), *capture_sources,
            str(snapshot / "libHerdrKit.a"), str(snapshot / "libIslandCore.a"),
            "-o", str(binary),
        ]
        print("Compiling the audit harness against frozen release libraries...", flush=True)
        subprocess.run(command, check=True)
        fixture_binary = snapshot / "fixture"
        subprocess.run(["swiftc", str(fixture_source), "-o", str(fixture_binary)], check=True)
        durations = []
        frozen_app = snapshot / "HerdrIsland.app/Contents/MacOS/HerdrIsland"
        for _ in range(0 if args.tasks_only else 20):
            start = time.monotonic_ns()
            payload = json.loads(run([str(frozen_app), "--print-state"], timeout=15))
            durations.append((time.monotonic_ns() - start) / 1e6)
            if payload.get("health") != "ok":
                raise RuntimeError("The frozen application did not read a healthy state")
        if durations:
            print("Measured 20 fresh-process state reads (not first painted UI frame).", flush=True)
        partial = snapshot / "samples.json"
        fixture_info = snapshot / "window.json"
        fixture = subprocess.Popen([str(fixture_binary), str(fixture_info)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 8
        while not fixture_info.exists() and time.monotonic() < deadline and fixture.poll() is None:
            time.sleep(.05)
        if not fixture_info.exists():
            fixture.terminate()
            fixture.wait(timeout=3)
            raise RuntimeError("Synthetic capture window did not initialize")
        window = json.loads(fixture_info.read_text())
        command = [str(binary), str(partial), f"--window={window['window_id']}",
                   f"--fixture-info={fixture_info}", f"--fixture-scale={window['scale']}"]
        if args.live_tasks:
            command.append("--live-tasks")
        if args.live_multiline:
            command.append("--live-multiline")
        if args.capture_only:
            command.append("--capture-only")
        if args.tasks_only:
            command.append("--tasks-only")
        started = time.monotonic()
        manifest["completed"] = False
        app_capture_probes = []
        try:
            subprocess.run(command, cwd=ROOT, check=True, timeout=600)
            # Direct executable probes inherit the launching process identity.
            # A separate LaunchServices probe is required for normal GUI TCC.
            if not args.tasks_only:
                fixture_info.with_suffix(".json.hide").unlink(missing_ok=True)
                fixture_info.with_suffix(".json.show").touch()
                time.sleep(.2)
            for _ in range(0 if args.tasks_only else 3):
                probe = subprocess.run([str(frozen_app), "--capture-probe-window", str(window["window_id"])],
                                       capture_output=True, text=True, timeout=30)
                result = json.loads(probe.stdout)
                result["exit_code"] = probe.returncode
                app_capture_probes.append(result)
            manifest["completed"] = True
        finally:
            fixture.terminate()
            try:
                fixture.wait(timeout=3)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()
            manifest["elapsed_run_seconds"] = time.monotonic() - started
            manifest["host_after"] = host()
            end_sources = sources()
            manifest["sources_changed_during_run"] = [k for k, v in start_sources.items() if end_sources.get(k) != v]
            if partial.exists():
                payload = json.loads(partial.read_text())
                # Recover only explicitly journaled probe panes if interrupted.
                journal = partial.with_suffix(partial.suffix + ".probes.json")
                pending = json.loads(journal.read_text()) if journal.exists() else []
                for pane in pending:
                    try:
                        info = json.loads(run(["herdr", "pane", "get", pane], timeout=8))
                        workspace = info["result"]["pane"]["workspace_id"]
                        run(["herdr", "workspace", "close", workspace], timeout=8)
                    except (subprocess.SubprocessError, KeyError):
                        payload.setdefault("notes", []).append(f"Manual cleanup may be needed for owned probe {pane}")
                payload["manifest"] = manifest
                payload["app_capture_probes"] = app_capture_probes
                if durations:
                    payload["metrics"]["app.fresh_process_state"] = summarize(durations)
                output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    print(f"Saved {output}", flush=True)


if __name__ == "__main__":
    main()
