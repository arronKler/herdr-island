# Extractable Components

Catalog only — no source. Every component is reusable in a redesign of the island; paths are repository-relative. "Props / state in" lists the data a component needs; "Hardcoded" lists values or copy baked into the implementation that a redesign must either keep as invariants or deliberately change.

## Layout primitives

### NotchBarShape
- **Source:** `Sources/IslandApp/Theme.swift`
- **Category:** shape / layout
- **Description:** Collapsed island silhouette — square at the menu-bar edge, rounded only at the bottom.
- **Props / state in:** `cornerRadius` (default 10) from the view rect.
- **Hardcoded:** bottom-only rounding, quadratic corner curve; no fill/stroke of its own.

### NotchIslandShape
- **Source:** `Sources/IslandApp/Theme.swift`
- **Category:** shape / layout
- **Description:** Expanded island silhouette with a notch-width collar in the menu-bar band and a wider body below; one path avoids a seam.
- **Props / state in:** `neckWidth`, `neckHeight`, `cornerRadius` (default 20).
- **Hardcoded:** centered neck; 20pt body radius; body top exactly at `neckHeight`.

### NotchEarsView / AmbientBarView
- **Source:** `Sources/IslandApp/NotchEarsView.swift`
- **Category:** app shell / status bar
- **Description:** Black ambient bar with a left status ear and a right status ear around a transparent camera-cutout gap.
- **Props / state in:** `presentation` (`health`, `summary`, `windowLock`), `actions.toggle`, `notchWidth`, `showsChrome`.
- **Hardcoded:** 72pt ear width; 4pt status dots; 10pt mono counts; 10pt sans labels; Chinese strings 重连 / 连接 / 待处理 / 锁定 / 安静 / 运行 / 完成 / 全安静; 1px white 3.5% bottom gradient; black fill and 11pt bottom radius (applied by `NotchEarsView`).

### ExpandedView
- **Source:** `Sources/IslandApp/ExpandedView.swift`
- **Category:** app shell / router
- **Description:** Switches between peek, deck, quick task, window task and detail inside a shared notch-collared background.
- **Props / state in:** `presentation.surface`, `.quickTask`, `.windowTask`, `notchWidth`, `notchHeight`, `actions`.
- **Hardcoded:** notch band height; 20pt surface radius fallback; gradient stops black / bar 10% / surface 34%.

## Core primitives

### StatusDot
- **Source:** `Sources/IslandApp/Theme.swift`
- **Category:** status / primitive
- **Description:** Colored status dot with an optional expanding pulse ring.
- **Props / state in:** `status: AgentStatus`, `size` (default 6); environment `accessibilityReduceMotion`.
- **Hardcoded:** 2.4s repeating ease-out pulse; ring 8pt larger, scale 0.72→1.18, opacity 0.8→0; pulse only blocked/working; accessibility hidden.

### Hairline
- **Source:** `Sources/IslandApp/Theme.swift`
- **Category:** separator
- **Description:** One-pixel horizontal rule.
- **Props / state in:** `color` (default `Theme.hairline`).
- **Hardcoded:** height exactly 1pt.

### KeyCap
- **Source:** `Sources/IslandApp/Theme.swift`
- **Category:** keyboard hint
- **Description:** 16pt minimum keycap with mono label and rounded outline.
- **Props / state in:** `text`.
- **Hardcoded:** 9.5pt medium mono, 4pt horizontal padding, 3pt radius, white 4% fill, 0.6pt hairline.

### AgentMarkView / AgentMark / AgentGlyphView
- **Source:** `Sources/IslandApp/AgentMarkView.swift`
- **Category:** identity / avatar
- **Description:** Rounded-square agent avatar with brand-tinted vector glyph and optional status dot; bare glyph variant for the droplet.
- **Props / state in:** `kind: String`, `size` (default 26), `status: AgentStatus?`, `monogram?`; `AgentMark` exposes `tint`, `displayName`, `wash`, `border`.
- **Hardcoded:** 13 marks (Claude, Codex, Cursor, Gemini, Copilot, OpenCode, Pi, Cline, Amp, Grok, Qwen, Kimi, Terminal); corner radius `size*0.27`; glyph box `size*0.58`; status dot `size*0.23`; fixed brand RGB values; hand-drawn `Shape` geometry.

### DeckGlyph
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** brand mark
- **Description:** Miniature island logo used in the deck header.
- **Props / state in:** none.
- **Hardcoded:** 20×12; square top, 6pt bottom corners; black fill; 0.6pt white 15% outline; 3pt amber dot offset (5.5, 5.5).

### DropletBody / DropletShape
- **Source:** `Sources/IslandApp/LiquidDropOverlay.swift`
- **Category:** decoration / shape
- **Description:** Glass water-drop view with gradient body, radial highlight, rim, specular and caustic ellipses.
- **Props / state in:** `width`, `height`, `breathe`, `lean`, `tint: Color?`.
- **Hardcoded:** four-curve pear outline; blue water gradient; white rim 0.7pt; highlight at 22%×10% offset (-16%, -18%); caustic at 32%×10% offset +34% height; blue shadow r8 y3; black shadow r2 y1; breathe scale 1.015/1.03.

### DesignMark / DesignMarkData
- **Source:** `Sources/IslandApp/DesignMark.swift`, `Sources/IslandApp/DesignMarkData.swift`
- **Category:** identity / vector data
- **Description:** Exact 24×24 agent logos from the design sprite, parsed from SVG path strings into cached `CGPath`s for CoreGraphics drawing at 11pt inside the droplet.
- **Props / state in:** `AgentKindOption`; returns an optional `CGPath` (nil when a mark has no sprite entry).
- **Hardcoded:** 13 path strings (Claude, Codex, Cursor, Gemini, Copilot, OpenCode, Pi, Cline, Amp, Grok, Qwen, Kimi, Terminal); 24×24 viewBox; supported commands M/L/H/V/C/A/Z with relative forms; `@MainActor` cache; tint supplied separately by `DropMarkRenderer` (#E08A6D, #A9C4FF, #7FB0FF, #FF8A72, #A49CFF, default #E8EBF1).

## Header / navigation controls

### countChip
- **Source:** `Sources/IslandApp/DeckView.swift` (private in `DeckView`)
- **Category:** status chip
- **Description:** Dot + count + label summary used three times in the header.
- **Props / state in:** title, count, tint color; zero state falls back to tertiary text.
- **Hardcoded:** 5pt dot; 10.5pt medium mono count; 11.5pt sans label; spacing 5.

### machineChip
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** status chip
- **Description:** Capsule with health dot and machine name.
- **Props / state in:** `presentation.health`, `presentation.machineLabel`.
- **Hardcoded:** 26pt height, 10pt horizontal padding, 10pt mono, mint/amber dot, white 4.5% fill + hairline.

### iconButton
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** button
- **Description:** 30×30 borderless SF Symbol action button with tooltip and accessibility label.
- **Props / state in:** symbol name, help text, action.
- **Hardcoded:** 13pt medium symbol, tertiary color, 30×30 hit area, `.plain` style.

### FilterTabs (filters / filterButton)
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** navigation / tabs
- **Description:** Capsule tab group for 待处理 / 运行中 / 已完成 / 全部 with counts.
- **Props / state in:** `presentation.filter`, `filterCounts`, `actions.setFilter`.
- **Hardcoded:** 3pt inset, 3pt spacing, 30pt tab height, 12pt horizontal padding, white 2.5% capsule, white 9% selected fill, 12.5pt medium label, 10pt mono count, selected text primary / unselected secondary.

### SearchField (searchBar)
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** input
- **Description:** Amber-tinted 36pt search row with magnifier, placeholder and `esc` hint.
- **Props / state in:** `presentation.query`, `actions.setQuery`, `actions.setSearching`; local `@FocusState`.
- **Hardcoded:** 9pt radius, amber 4.5% fill, amber 30% border, 12pt horizontal padding, 12.5pt sans, 9.5pt esc keycap; placeholder 搜索 agent、项目或动作…

## Agent rows

### AttentionRow (`attentionRow`)
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** row / blocked
- **Description:** Blocked-agent row with reason, avatar, title, last terminal line, age and amber 去处理 action.
- **Props / state in:** `AgentRow` (reason, kind, title, lastLine, project, worktree, waited, isSelected), `actions.jump` / `openDetail`.
- **Hardcoded:** 74pt list height; 14pt radius; 12pt vertical / 14pt horizontal padding; 30pt avatar; 10pt mono reason; 9.5pt agent label; 13.5pt semibold title; 11.5pt secondary line; 30pt amber button, 6pt radius; amber wash gradient when selected.

### WorkingRow (`workingRow`)
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** row / working-idle
- **Description:** Compact 24pt-avatar row for working, idle and unknown agents.
- **Props / state in:** title, project, kind, progress, isQueued, lastLine, status, waited, isSelected.
- **Hardcoded:** 54pt list height; 12pt radius; 12pt horizontal / 10pt vertical padding; 13pt medium title; 11.5pt tertiary metadata; 10pt mono age; selected white 5.5% fill.

### DoneRow (`doneRow`)
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** row / completed
- **Description:** Mint-washed completed row with optional NEW badge and 打开 affordance.
- **Props / state in:** title, project, isPendingCompletion, waited, isSelected.
- **Hardcoded:** 54pt list height; 12pt radius; mint 6.5% fill; mint 12% border (28% when selected); 9.5pt semibold NEW with 0.8 tracking; 10pt mono 打开.

### WorktreeChip
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** chip
- **Description:** Tiny branch chip showing the isolated worktree branch.
- **Props / state in:** branch string.
- **Hardcoded:** 18pt height, 5pt horizontal padding, 3pt radius, 9.5pt mono, amber text, amber 22% border, branch SF Symbol 9pt.

## Feedback / footers

### DecisionFooter
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** action footer
- **Description:** Blocked-state footer explaining that approval happens in the terminal, with 稍后 and amber 去终端处理.
- **Props / state in:** selected `AgentRow` (reason), `actions.snooze`, `actions.jump`.
- **Hardcoded:** 30pt shield circle; 12.5pt semibold title; 11.5pt tertiary subline; 34pt buttons; 8pt radius; amber label color rgb(0.09, 0.07, 0.03); 12pt top padding.

### ComposerFooter
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** input / action footer
- **Description:** Inline reply composer with optional queued-message banner, send button and new-task button.
- **Props / state in:** `presentation.composer` (text, canSend, isSending, refusal, queuedText), row status, `actions.draft` / `send` / `cancelQueued` / `openQuickTask`.
- **Hardcoded:** 38pt field, 9pt radius, 12pt padding; 34pt send/plus buttons; amber focus ring 0.7pt; 26pt blue queued strip; 9.5pt mono hints; Chinese placeholders and 发送后会在这一轮结束时自动投递.

### IdleFooter
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** empty-state action
- **Description:** Prompt plus amber 新任务 button when no agent is selected.
- **Props / state in:** `actions.openQuickTask`.
- **Hardcoded:** 12.5pt body; 34pt button; amber 7% fill; 8pt radius; copy 选一个 agent 查看终端，或开一个新任务.

### BannerView
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** feedback
- **Description:** 30pt success/error strip with dismiss button.
- **Props / state in:** `Banner` (text, isError), `actions.dismissBanner`.
- **Hardcoded:** 8pt radius; mint/red 9% fill; 10pt icon; 11.5pt message; 9pt bold dismiss X; 8pt top padding.

### HintBar
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** keyboard hints
- **Description:** Bottom shortcut legend with keycaps and a right-aligned summary.
- **Props / state in:** `presentation.isSearching`, `AmbientBarView.summaryLine(presentation)`.
- **Hardcoded:** keys ↵ / / R S; 9.5pt mono; 12pt spacing; hairline at 60% opacity; 24pt height.

### EmptyState
- **Source:** `Sources/IslandApp/DeckView.swift`
- **Category:** empty state
- **Description:** Miniature island illustration, filter-specific title/subtitle and amber CTA.
- **Props / state in:** `presentation.isSearching`, `presentation.filter`, `actions.openQuickTask`.
- **Hardcoded:** 44×28 black rounded island; 5pt mint dot; 13.5pt title; 12.5pt body; 34pt amber button; Chinese copy per filter.

## Detail components

### RailRow
- **Source:** `Sources/IslandApp/DetailView.swift`
- **Category:** row / navigation
- **Description:** 210pt-rail agent row with avatar, title and project · age.
- **Props / state in:** `AgentRow`, `actions.openDetail`.
- **Hardcoded:** 22pt avatar; 11.5pt medium title; 9.5pt mono metadata; 8pt padding; 9pt radius; selected white 6% fill.

### QuestionCard
- **Source:** `Sources/IslandApp/DetailView.swift`
- **Category:** status card
- **Description:** Status-tinted card with uppercase reason label, question/title and optional command chip.
- **Props / state in:** `AgentRow`, `PreviewPresentation` (question, command, reason).
- **Hardcoded:** 12pt radius; 14pt horizontal / 12pt vertical padding; 9.5pt uppercase mono label; 13.5pt semibold question; black 28% command well with amber `$`.

### TerminalPreview
- **Source:** `Sources/IslandApp/DetailView.swift`
- **Category:** read-only output
- **Description:** Dark terminal well rendering the last 60 lines with status coloring.
- **Props / state in:** `presentation.preview` (text, failure, isLoading).
- **Hardcoded:** 10pt radius; #090A0D fill; 11.5pt mono; 12pt horizontal / 10pt vertical padding; line limit 60; amber prompts, mint pass, red fail, tertiary comments; text selection enabled; loading and empty copy.

### DetailActionRow
- **Source:** `Sources/IslandApp/DetailView.swift`
- **Category:** action row
- **Description:** Primary jump, optional snooze, optional copy-command and trailing age.
- **Props / state in:** `AgentRow.status`, `preview.command`, `actions.jump` / `snooze`; AppKit pasteboard for copy.
- **Hardcoded:** 34pt buttons; 8pt radius; amber primary when blocked; white 7% secondary fill; hairline outline; 10pt arrow icon; 11.5pt sans labels.

## Task composers

### KindChip
- **Source:** `Sources/IslandApp/QuickTaskView.swift`
- **Category:** choice chip
- **Description:** 30pt agent-kind chip with glyph, label and amber selected state.
- **Props / state in:** `AgentKindOption`, selected kind, `actions.quickTaskKind`, disabled while creating.
- **Hardcoded:** 18pt avatar; 10.5pt label; 8pt horizontal padding; 8pt radius; amber 7% fill / 30% border selected; white 2% fill otherwise.

### QuickTaskComposer
- **Source:** `Sources/IslandApp/QuickTaskView.swift`
- **Category:** composer
- **Description:** 420×196 new-task card with header, input, model chips, folder chip and footer.
- **Props / state in:** `QuickTaskPresentation` (draft, kind, cwd, isCreating, error, canSubmit), all quick-task actions.
- **Hardcoded:** 20pt gutter; 16pt top / 14pt bottom; 38pt input + amber 开始; 30pt chips; 9pt radius; 18pt footer; Chinese copy 新任务 / 从当前目录开始 / ⌘↩ 开始.

### WindowTaskCard
- **Source:** `Sources/IslandApp/WindowTaskView.swift`
- **Category:** composer
- **Description:** 560×510 window-locked task card with capture explanation, destination picker and suggestions.
- **Props / state in:** `IslandPresentation`, `WindowTaskPresentation`, all window-task actions.
- **Hardcoded:** 20pt gutter; 30pt top / 16pt bottom; 36pt header; 84pt capture card; 110pt minimum task field; 34pt controls; three suggestion strings; Chinese copy and 锁定 mint capsule.

### CaptureCard
- **Source:** `Sources/IslandApp/WindowTaskView.swift`
- **Category:** informational card
- **Description:** Dashed window placeholder showing the locked window's pixel size and capture-on-send promise.
- **Props / state in:** `windowTask.lock.bounds`.
- **Hardcoded:** 104×62; 12pt radius; dashed 0.7pt hairlineHigh; 15pt macwindow icon; 9.5pt dimensions; 84pt height; raised 55% fill.

### DestinationChip
- **Source:** `Sources/IslandApp/WindowTaskView.swift`
- **Category:** choice chip
- **Description:** Horizontal target chip for "new agent" or an existing promptable agent.
- **Props / state in:** `PaneID?`, `AgentRow`, selected destination, `actions.windowTaskDestination`.
- **Hardcoded:** 34pt height; 20pt avatar; 10.5pt label; 180pt max width; 9pt radius; amber 8% selected fill / 30% border.

### SuggestionChip
- **Source:** `Sources/IslandApp/WindowTaskView.swift`
- **Category:** prompt starter
- **Description:** Capsule that fills the task draft with a suggested question.
- **Props / state in:** suggestion strings, `actions.windowTaskDraft`, disabled while busy.
- **Hardcoded:** 30pt height, 10pt horizontal padding, capsule white 3.5% fill + hairline; strings 总结这个窗口 / 列出下一步 / 找出风险点; 10.5pt sans.

### DropComposerCard
- **Source:** `Sources/IslandApp/LiquidDropOverlay.swift`
- **Category:** floating composer
- **Description:** 340pt floating card anchored to the detached droplet with model grid, worktree toggle and submit.
- **Props / state in:** `DropTaskPresentation`, `moreKinds` binding, all drop actions, close callback.
- **Hardcoded:** 16pt radius; #1B1E24→#121418 gradient; white 13% border; black 48% r22 y12 shadow + blue 8% r14; 16pt padding; 260/380(+38) heights; 34pt model buttons; 42pt input; 44pt worktree row; footer safety string 只创建 · 不代为批准.

## Decoration and motion

### LiquidDropView / LiquidDropRenderer
- **Source:** `Sources/IslandApp/LiquidDropView.swift`
- **Category:** motion / illustration
- **Description:** 60fps AppKit liquid drop with spring physics, 96pt neck break, detached drag, ripple and agent mark.
- **Props / state in:** `notchHeight`, `visible`, `composerVisible`, `composerRect`, `reduceMotion`, `markKind`, `lockMode`, tap/drag/close callbacks.
- **Hardcoded:** 96pt break distance; 22pt hit radius; 60Hz timer; 520ms return; 620ms ripple; 1.15s bob; 16ms layer fade; neck 24 segments; body 48 segments; 11pt agent mark from `DesignMark`'s 24×24 sprite; radial/linear gradient stops (#9AA6BA, #414A59, #12151C, #040507; highlights #D6EAFF / #96BEFF); blue halo #7AA0E6 16%.

### DropletView
- **Source:** `Sources/IslandApp/DropletView.swift`
- **Category:** drag source
- **Description:** 22×22 AppKit droplet that starts an `NSDraggingSession` for window locking.
- **Props / state in:** `isLocked`, drag began/moved/ended callbacks.
- **Hardcoded:** 22×22 intrinsic size; 15pt `drop.fill` symbol; blue #5C9CFF unlocked / green #30D158 locked; 32×32 drag image; halo alpha 10%/14%; 3pt drag threshold; pasteboard type `local.herdr.island.window-lock`.

## Settings

### SettingsView / SettingsModel
- **Source:** `Sources/IslandApp/SettingsView.swift`
- **Category:** settings form
- **Description:** Standalone 440×500 form for auto-expand, completion hold and permissions.
- **Props / state in:** `IslandRules`, Herdr binary/socket paths, screen-capture authorization, callbacks.
- **Hardcoded:** 440×500; 24pt padding; 17pt title; 11.5pt labels; 2–30s stepper; Chinese copy; system control styling (no custom dark treatment).
