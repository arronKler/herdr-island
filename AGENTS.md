# AGENTS.md

Guidance for coding agents working in this repository. `README.md` is the user-facing document and
holds the full build, release, and site instructions; this file records what an agent needs to know
before changing code.

## Layout

```text
Sources/IslandCore   Pure state machine. No AppKit, no Carbon, no Herdr, no I/O.
Sources/HerdrKit     Herdr adapter: CLI, Unix socket, DTOs, installer, Ghostty focus.
Sources/IslandApp    AppKit + SwiftUI shell: panels, menu bar, hotkeys, render harness, settings.
Tests/               IslandCoreTests, HerdrKitTests, IslandAppTests.
Scripts/             Packaging, release gate, site asset generation, tap bump.
```

Three rules hold this together, and a change that breaks one is a design error rather than a style
preference.

- `IslandCore` stays pure. `HerdrKit` parses every Herdr fact into an `Agent` at the boundary;
  state transitions live in `IslandReducer`; views render the `IslandPresentation` that
  `IslandPresenter` produces. Do not import AppKit into `IslandCore`.
- A submission rule lives once. `DeliveryPolicy.resolve` and `DeliveryPolicy.evaluate` in
  `Sources/IslandCore/Delivery.swift` decide where a task goes and whether it may be sent. The
  presenter and the reducer both call them, so a changed rule shows up in the UI and in the
  behavior at the same time.
- The three compose surfaces share one card. Lock, drop, and summon all render
  `DeliveryComposerCard` in `Sources/IslandApp/DeliveryComposerCard.swift`. They differ in host
  window and entry point, not in what the card contains. A fix in one surface that is not in that
  file is almost certainly a bug.

## Commands

```bash
swift build
swift test
Scripts/make-app.sh                      # release build, assemble build/HerdrIsland.app, ad-hoc sign
```

Every test named `testLive…` skips unless a real Herdr socket and a disposable pane are supplied.
They cover the live terminal, window capture, and Herdr install and task creation. A skipped test is
not a passing test, so do not claim live coverage from a plain `swift test` run. The suite is
XCTest; the `Testing Library Version` line swift-testing prints reports an empty run, not results.

## Render fixtures

`--render <dir>` is the primary way to see a UI change and the release gate for the packaged app.

```bash
.build/debug/HerdrIsland --render /tmp/herdr-render
python3 Scripts/make-site-shots.py /tmp/herdr-render site
python3 Scripts/make-og-cards.py site
```

Fixtures come from `FixtureName` in `Sources/IslandCore/Fixtures.swift`. Add a case there when a
state needs a picture, and keep the scene's frame in `manifest.json` accurate: the site crops to
that frame instead of shrinking a whole desktop.

### The render harness must not need a GPU

The release workflow smoke-tests on a `macos-15-intel` runner that has no usable GPU. Attaching a
SwiftUI view to an `NSWindow` is enough for SwiftUI to build a Metal layer, and
`+[MTLLoader sliceIDForDevice:]` then asserts `Target device architecture is nil` and kills the
process with SIGABRT. `MTLCreateSystemDefaultDevice() != nil` does not detect this, because that
runner returns a device whose architecture is nil.

So the main render path never mounts a window. Work that genuinely needs one runs in a child
process through `--render-window-check`, and the parent treats a signal death as a skipped check.
If you add measurement that needs layout inside a window, extend that child process rather than
adding a window to `RenderHarness.run`.

## Release

A release is a pushed tag, and the tag must name an explicit commit because other sessions can
share this working tree.

```bash
git push origin main
git tag -a v0.3.4 -m "Herdr Island 0.3.4" <commit>
git push origin refs/tags/v0.3.4
```

The version comes from the tag; nothing in the source hardcodes it. `.github/workflows/release.yml`
runs `verify-intel` (test, package, `Scripts/verify-release.py` against the archive) and then
`release`, which publishes the zip, its `.sha256`, a signed `appcast.xml`, and generated notes.

After the release exists:

1. Replace the generated notes with a written summary using `gh release edit <tag> --notes-file`.
2. Let the Homebrew tap catch up. `arronKler/homebrew-tap` has its own `Update cask` workflow that
   reads the latest release, so it must run only after the release exists; it can also be
   dispatched by hand. `Scripts/bump-tap.sh` does the same against a local tap checkout and is a
   no-op when the cask already matches.
3. Verify the published archive rather than trusting the run: download it, compare
   `shasum -a 256` against the published digest, check `CFBundleShortVersionString`, run
   `codesign --verify --deep --strict`, confirm `lipo -archs` lists both `arm64` and `x86_64`, and
   run `Scripts/verify-release.py` on it. Test the cask with `--appdir` into a temporary directory,
   never into `/Applications`.

Do not force-move a tag that is already pushed. If a tag must be replaced, cut a new one; a tag
that never produced a release can simply be deleted, locally and remotely.

## UI changes

The island is dark-only; `IslandPanel` pins its appearance so AppKit-drawn controls inside it stay
dark. Keep new surfaces on that `Theme` palette in `Sources/IslandApp/Theme.swift` rather than
introducing colors inline.

- Boundaries follow the 4px spacing scale. Some existing rows use finer optical values; new and
  changed layout should land on 4px steps, with cards centered inside panels and nothing touching
  or crossing a panel edge.
- Context that is captured automatically is not a control. Show recipient, input, explicit file
  attachments, and send. Do not add switches or chips for context the user would have to inspect.
- Agent icons are the official brand marks, sourced from `Sources/IslandApp/DesignMarkData.swift`,
  which holds all 13 marks. No approximations and no font glyphs.
- The access point does not animate slowly. A delayed island or droplet defeats the point of the
  app.

## Boundaries to keep

- Network access exists in exactly two places. `UpdateController` (Sparkle) checks the signed
  appcast on GitHub daily. `HerdrInstaller` in `Sources/HerdrKit` fetches `herdr.dev/latest.json`
  and the matching archive, but only after the user presses the install button in the setup card.
  Nothing else opens a socket to the internet; do not add a third without treating it as a
  documentation change. `site/what-it-reads.html` currently names only the Sparkle path, so a
  change here should also close that gap in the copy.
- No telemetry, no background service, no login item, no LaunchAgent.
- `LSUIElement` is set; the app is an accessory and does not appear in the Dock.
- Commit messages use a conventional `type: summary` prefix (`feat:`, `fix:`, `test:`, `docs:`).
- `decisions.tsv` is a historical design log, last appended in November 2026 and not referenced by
  the README. Do not treat it as a required step for new work.
