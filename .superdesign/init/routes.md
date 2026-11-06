# Routes — Presentation surfaces

Herdr Island has one window. "Routes" are the five `IslandSurface` values (`ambient`, `peek`, `deck`, `detail`, `drop`) plus three deck-level modes (`quickTask`, `windowTask`, settings) that the panel or a separate `NSWindow` renders. The surface is a pure function of `IslandState`; views never navigate themselves.

## Route summary

| Route | Trigger | Surface / state | Content size | Panel frame on notch display | Files |
| --- | --- | --- | --- | --- | --- |
| Ambient notch | default; nothing open | `.ambient` | ears 72pt each; bar 200×28 fallback | `notch.width + 144` × `notch.height + 32` | `IslandRootView`, `NotchEarsView`, `LiquidDropOverlay` |
| Peek | completion hold (`completionExpiry` non-empty) | `.peek`, auto-expand rules | 400×248 | 400 × (248 + notchHeight) | `PeekView` |
| Deck | hover / click / hotkey / blocked attention | `.deck` | 560 × 440–640 | 560 × (deckHeight + notchHeight) | `DeckView` |
| Deck filters | `needs` / `running` / `done` / `all` | `state.filter` | same deck | same | `DeckView`, `Presenter.makeDeckRows` |
| Detail | Return / row tap / `openDetail` | `.detail` | 660×640 | 660 × (640 + notchHeight) | `DetailView` |
| Quick task | Control+Option+N | `.deck` + `quickTask != nil` | 420×196 | 420 × (196 + notchHeight) | `QuickTaskView` |
| Window task | Option-drag droplet onto a window | `.deck` + `windowTask != nil` | 560 × 510 (+44/+42/+44/+42/+28) | 560 × (windowTaskHeight + notchHeight) | `WindowTaskView` |
| Droplet / drop | drag droplet (or click it) | `.drop` | canvas 720×640; card 340×260–418 | 720 × (640 + notchHeight) | `LiquidDropOverlay`, `LiquidDropView` |
| Settings | gear button or menu bar | separate `NSWindow` | 440×500 | standalone | `SettingsView`, `SettingsWindowController` |

Notes:
- Content sizes are from `IslandGeometry` and the README. On a notched display `IslandGeometry.frame` adds the physical notch height above the content, so the panel is taller than the quoted content size. On a notchless display the quoted size is the whole panel.
- Deck content width is always 560. `deckHeight` is computed by `Presenter.makeDeckHeight` and clamped to 440…640.
- Peek has no independent width: 400 fixed. Quick task is centered under the notch.

## Surface state machine

The canonical machine lives in `Sources/IslandCore/State.swift` (`IslandState.surface`, `isExpanded`, `canAutoCollapse`) and is projected by `IslandPresenter.present`. Verbatim:

```swift
public var surface: IslandSurface {
    if dropActive || drop != nil {
        return .drop
    }
    if quickTask != nil || windowTask != nil {
        return .deck
    }
    if detailOpen {
        return .detail
    }
    if manualOpen || hoverOpen || !blockedAttention.isEmpty {
        return .deck
    }
    if !completionExpiry.isEmpty {
        return .peek
    }
    return .ambient
}

public var isExpanded: Bool {
    quickTask != nil
        || manualOpen
        || hoverOpen
        || !blockedAttention.isEmpty
        || !completionExpiry.isEmpty
}

public var canAutoCollapse: Bool {
    !pointerInside && !composerFocused && !hasDraft && !windowDragActive
        && drop == nil && !dropActive
}
```

Presenter visibility:

```swift
let isVisible = isExpanded
    || drop != nil
    || state.dropActive
    || state.windowLock != nil
```

Transition inputs (`IslandReducer`):
- `.setHover(true)` → `hoverOpen = true` only when not already expanded; `.setHover(false)` clears hover unless blocked attention, unread completion, a draft, composer focus or window drag keeps it open.
- `.openDeck` → `manualOpen = true`, `detailOpen = false`, search cleared, selection ensured.
- `.openDetail(pane)` → `detailOpen = true`, `manualOpen = true`, hover cleared, preview reset and reloaded.
- `.backToDeck` → `detailOpen = false` (surface falls back to deck).
- `.openQuickTask` → `quickTask` set; `.closeQuickTask` ignores the close while `phase == .creating`.
- `.beginDrop` → `drop` created if nil, `dropActive = true`; `.openDropComposer` → phase `.composing`; `.closeDropComposer` clears `drop`/`dropActive` unless creating.
- `.lockWindow` → `windowLock` + `windowTask` set and `manualOpen = true`; `.unlockWindow` clears both.
- Auto-expand: `rules.autoExpandOnBlocked` (default true) raises blocked attention; `rules.autoExpandOnCompletion` (default true) creates a completion hold of `rules.completionHold` (default 8s). Expired completion holds are pruned, returning the island to ambient.

Hover timing is in `IslandStore.setHover`: open after 140ms, close after 220ms. The panel itself resizes with a 180ms interruptible cubic ease-out (`FrameAnimator`).

## Ambient notch

- **Trigger:** default state. Also when only a window lock exists (`windowLock != nil` keeps the panel visible but the surface stays ambient).
- **Presenter state:** `surface == .ambient`, `isVisible == false` unless a drop/window lock exists; `summary` counts drive both ears; `health` drives the left ear.
- **Dimensions:** with a notch, width `notch.width + 72*2`, height `notch.height + 32` (32pt transparent lip below the menu bar); `NotchEarsView` itself is `notch.width + 144` × `notch.height`. Without a notch, a 200×28 black pill plus the 32pt lip.
- **Rendering:** black `NotchBarShape` (square top, 11pt bottom corners) behind the camera cutout. Left ear: stale/failed → amber dot + 重连; starting → spinner + 连接; blocked → amber dot + count + 待处理; window lock → mint lock + 锁定; otherwise mint dot + 安静. Right ear: working count + 运行, else completed count + 完成, else moon + 全安静. Only the ears and the droplet accept hit testing; the middle cutout is untouched.
- **Sources:** `Sources/IslandApp/IslandRootView.swift`, `Sources/IslandApp/NotchEarsView.swift`, `Sources/IslandApp/LiquidDropOverlay.swift`.

## Peek (completed)

- **Trigger:** `completionExpiry` non-empty and no stronger surface; produced when an agent transitions to done and `autoExpandOnCompletion` is enabled. Hovering/opening the deck takes precedence.
- **Presenter state:** `surface == .peek`; `summary.completed`; rows filtered to pending completion or done. `completionHold` default 8s; the peek's own progress bar is a 4s linear countdown.
- **Dimensions:** 400×248 content (plus notch height in the panel). 18pt horizontal padding, 14pt top, 16pt bottom.
- **Rendering:** 17pt amber/mint headline ("N 项完成" / "N 项待处理" / "全部安静"), project + age subline, chevron to deck. At most one completed row and one blocked row (or two blocked when nothing completed); each row is a 22pt avatar + title + project/reason + trailing 打开/待处理. Footer count + amber 打开面板 capsule. A 2pt bottom bar drains over 4s, tinted mint for completion and amber for blocked.
- **Sources:** `Sources/IslandApp/PeekView.swift`, `Sources/IslandApp/ExpandedView.swift`.

## Deck (task console)

- **Trigger:** hover over ears/droplet (140ms), click the ambient bar/droplet, Control+Option+H, `/` (opens search), blocked attention, or returning from detail.
- **Presenter state:** `surface == .deck`; `deckRows`, `deckGroups`, `deckHeight`, `filter`, `filterCounts`, `query`, `isSearching`, `selected`, `preview`, `composer`, `banner`.
- **Dimensions:** width 560. Height = `chrome 267 + listHeight + extra`, clamped 440…640. Empty list uses 190pt. Row heights: blocked 74, other 54, 8pt gaps, group headers 24 each. Extra: 24pt when searching, 38pt with a banner. Panel adds notch height.
- **Rendering:** header (20×12 `DeckGlyph`, "Herdr Island" 15pt semibold, count chips, machine capsule, search/gear/close) → filter capsule or search field → scrollable rows → optional banner → footer → keycap hint bar. Rows are grouped only in `all` (待处理/运行中/已完成/空闲); filtered and search modes are a flat list. Blocked rows get amber treatment; done rows mint; working rows neutral with progress/queued metadata.
- **Sources:** `Sources/IslandApp/DeckView.swift`, `Sources/IslandCore/Presenter.swift`.

### Deck filters

| Filter | Label | Rows | Sort |
| --- | --- | --- | --- |
| `.needs` (default) | 待处理 | blocked and not dismissed | longest wait first |
| `.running` | 运行中 | working | longest wait first |
| `.done` | 已完成 | done or pending completion | pending first, then wait |
| `.all` | 全部 | all non-dismissed | grouped 待处理/运行中/已完成/空闲 |

Selecting a filter clears the query and search (`Reducer.setFilter`). `/` sets `isSearching`, and a non-empty query overrides the filter, matching title, project, kind, status, machine, name and labels. Counts: needs excludes dismissed blocked; done includes pending completions; total is all rows. `⌘↩` sends; `R` focuses the composer; `S` snoozes; arrows move; Return opens detail; Esc peels input → search → detail → collapse.

## Detail

- **Trigger:** Return on the selected row or any row tap (`openDetail`).
- **Presenter state:** `surface == .detail`, `detailOpen == true`; selected row, preview (`loading` / `loaded` / `failed`), composer, banner, worktree and queue.
- **Dimensions:** 660×640 content (plus notch height). Rail 210pt + 1pt divider + 16pt gap; 20pt gutters; 30pt top padding.
- **Rendering:** left rail with grouped 待处理/运行中/其他 rows. Right: agent header (28pt mark, 15pt title, project · machine · kind · labels, status capsule, close), banner, status-tinted question card with reason/question and optional `$ command`, worktree banner, queued banner, read-only terminal (last 60 lines, 11.5pt mono, color-coded), action row (去终端 / 稍后 / 复制命令), trust note, composer. Blocked agents show a lock/refusal line instead of a text field.
- **Sources:** `Sources/IslandApp/DetailView.swift`, `Sources/IslandApp/AgentMarkView.swift`.

## Quick task (Control+Option+N)

- **Trigger:** global hotkey Control+Option+N; menu bar "new task"; deck plus button. Pre-fills the current Herdr pane directory and last-used model.
- **Presenter state:** `surface == .deck` because `quickTask != nil`; `QuickTaskPresentation` (draft, kind, cwd, isCreating, error, canSubmit). Closing is ignored while creating.
- **Dimensions:** 420×196 content (plus notch height). 20pt side padding, 16pt top, 14pt bottom.
- **Rendering:** 22pt agent mark + 新任务 + 从当前目录开始 + optional creating spinner + close; single-line input + amber 开始 button; three primary model chips, 更多 menu, folder chip; footer "在 <folder> 新建 <agent>，不改动现有终端" and ⌘↩ 开始. Error line under controls.
- **Sources:** `Sources/IslandApp/QuickTaskView.swift`, `Sources/IslandApp/ExpandedView.swift`.

## Window task (Option-drag droplet)

- **Trigger:** hold Option and drag the droplet onto a window; release locks that windowID and opens the task composer. Option-drag is not a new-task drag.
- **Presenter state:** `surface == .deck` because `windowTask != nil`; `windowLock` (app, title, bounds, owner PID), destination agent, kind, cwd, phase, error, capture permission, last delivery. Default destination is the selected promptable agent, else the first promptable agent.
- **Dimensions:** 560 wide. Base height 510, plus 44 for a blocked agent, 42 for a destination refusal, 44 when screen recording is unauthorized, 42 for an error, 28 for a delivery line (clamped by the panel geometry to the computed height). Plus notch height.
- **Rendering:** app icon + window title + app name + mint 锁定 capsule + unlock; dashed 104×62 capture card; optional blocked notice; 3–6 line task field; horizontal destination chips (新 agent + up to 8 promptable agents); kind menu + cwd + 截图并发送; three suggestion capsules; permission/error/delivery notices; footer. Sending captures one PNG at submit time.
- **Sources:** `Sources/IslandApp/WindowTaskView.swift`, `Sources/IslandCore/WindowLock.swift`, `Sources/IslandApp/WindowCaptureService.swift`.

## Droplet and drop

- **Trigger:** click the droplet (opens composer at rest) or drag it. Drag starts a new-task drop; Option-drag is window lock. Crossing 96pt from the notch breaks the neck and detaches the drop; release shows a ripple and anchors the composer at the drop point.
- **Presenter state:** `surface == .drop` whenever `drop != nil` or `dropActive`; `DropTaskPresentation` (draft, kind, cwd, useWorktree, branch, isCreating, error, canSubmit).
- **Dimensions:** drop canvas 720×640 content (plus notch). Floating composer card 340 wide, 260 tall (380 with 更多 expanded, +38 with an error), placed above the drop when it would overflow, 12pt screen margins, 38pt top clamp.
- **Rendering:** liquid pear body, neck/foot/collar, satellite bead, shine and caustics, halo, ripples and an 11pt agent mark. The card has header, model buttons + 更多 grid, 2–3 line input + 开始, git worktree toggle (disabled outside a repo), folder/safety footer, error line. Background taps close after the drop returns home (520ms when detached, 220ms otherwise).
- **Sources:** `Sources/IslandApp/LiquidDropOverlay.swift`, `Sources/IslandApp/LiquidDropView.swift`, `Sources/IslandApp/DropletView.swift`.

## Settings

- **Trigger:** deck gear button; menu bar "设置"; not a panel surface.
- **Presenter state:** none — `SettingsModel` persists `autoExpandOnBlocked`, `autoExpandOnCompletion`, `completionHold` and emits `IslandRules`.
- **Dimensions:** standalone 440×500 titled window, centered, 24pt padding.
- **Rendering:** title, Herdr binary + socket paths, toggles, 2–30s stepper, Automation button + copy, screen-recording status + button, explanatory copy.
- **Source:** `Sources/IslandApp/SettingsView.swift`.

## Design rationale from `design/herdr-island-redesign.html`

- Signal before information: the two notch ears plus a droplet replace colored status icons and a floating pill.
- Attention is a queue, not inventory: blocked → done-unread → running → idle; the list is ordered for the user.
- One action away: command + context action instead of list + buttons; blocked is the only state that interrupts.
- Quiet is the default: done peeks, it does not seize the panel; blocked auto-expands once, then only the badge remains.
- The menu bar is the canvas; the panel grows from the notch's lower edge, not from screen center.
- Motion answers only three questions: where it came from, what changed, what can be interrupted. All transitions retarget from the current frame, never queue or jump.
- 380ms is the ceiling for expansion in the prototype (the app ships a 180ms frame resize); row state changes 140ms.
- The droplet is tension, not an icon: weight, inertia, a liquid neck, a pear-shaped body; it breaks at 96px and never drags a line home.
- Color is status, not decoration: amber = human decision, blue = working, mint = done/locked, red = error; no themes.
- Safety is a design constraint: never auto-approve, never send `y`/Enter, never upload terminal content or captures.
