# Pages — Surface dependency trees

Herdr Island is a single SwiftPM executable target (`Sources/IslandApp`). Swift files in the same target do not import each other; the trees below are built from actual symbol usage, with the system/module imports shown where relevant. `IslandCore` is a separate library target and is always imported explicitly.

Shared data path before any surface renders:

```
Sources/IslandApp/main.swift
└─ Sources/IslandApp/AppDelegate.swift
   ├─ Sources/IslandApp/IslandStore.swift        (owns IslandState, dispatch, polling, effects)
   │  └─ Sources/IslandCore/Reducer.swift        (all state transitions)
   │     ├─ Sources/IslandCore/State.swift       (IslandState.surface)
   │     ├─ Sources/IslandCore/Model.swift       (domain + presentation structs)
   │     ├─ Sources/IslandCore/Policy.swift      (keyboard + message policy)
   │     └─ Sources/IslandCore/Events.swift
   ├─ Sources/IslandCore/Presenter.swift         (IslandState -> IslandPresentation)
   ├─ Sources/IslandApp/IslandPanel.swift        (NSPanel + frame animation)
   └─ Sources/IslandApp/IslandRootView.swift     (root surface switch)
```

`IslandPresenter` returns one immutable `IslandPresentation`; every view below receives it plus `IslandViewActions`. No view owns data.

Legend: `[module]` = imported module only; `[view]` = local SwiftUI/AppKit view; `[util]` = local helper.

---

## 1. Collapsed ambient notch

Starting file: `Sources/IslandApp/IslandRootView.swift`

```
Sources/IslandApp/IslandRootView.swift
├─ [module] IslandCore (IslandPresentation, IslandGeometry.IslandSurface)
├─ [module] SwiftUI
├─ Sources/IslandApp/IslandViewActions.swift
├─ Sources/IslandApp/NotchEarsView.swift
│  ├─ [module] IslandCore (IslandGeometry.notchEarWidth)
│  ├─ [module] SwiftUI
│  ├─ Sources/IslandApp/Theme.swift
│  │  └─ [module] IslandCore (AgentStatus)
│  └─ Sources/IslandApp/IslandViewActions.swift
├─ Sources/IslandApp/ExpandedView.swift          (compiled branch, not shown in ambient)
│  └─ (see surfaces 2–6)
└─ Sources/IslandApp/LiquidDropOverlay.swift
   ├─ [module] AppKit, IslandCore, SwiftUI
   ├─ Sources/IslandApp/LiquidDropView.swift
   │  ├─ [module] AppKit, IslandCore (AgentKindOption), SwiftUI
   │  └─ Sources/IslandApp/AgentMarkView.swift
   │     ├─ [module] IslandCore (AgentStatus)
   │     └─ Sources/IslandApp/Theme.swift
   ├─ Sources/IslandApp/Theme.swift
   ├─ Sources/IslandApp/AgentMarkView.swift
   ├─ Sources/IslandApp/Formatting.swift
   │  └─ [module] IslandCore
   └─ Sources/IslandApp/IslandViewActions.swift
```

Also used by the ambient shell but not rendered until interaction: `Sources/IslandApp/DropletView.swift` (`NSViewRepresentable`, AppKit + SwiftUI only) for the menu-bar window-lock drag.

---

## 2. Peek / completed

Starting file: `Sources/IslandApp/PeekView.swift`

```
Sources/IslandApp/PeekView.swift
├─ [module] IslandCore (AgentRow, IslandGeometry, IslandPresentation)
├─ [module] SwiftUI
├─ Sources/IslandApp/IslandViewActions.swift
├─ Sources/IslandApp/Theme.swift
│  └─ [module] IslandCore (AgentStatus)
├─ Sources/IslandApp/AgentMarkView.swift
│  ├─ [module] IslandCore (AgentStatus)
│  └─ Sources/IslandApp/Theme.swift
├─ Sources/IslandApp/Formatting.swift
│  └─ [module] IslandCore (AgentReason, AgentStatus)
└─ Sources/IslandApp/NotchEarsView.swift          (AmbientBarView for the notch band)
   ├─ [module] IslandCore (IslandGeometry)
   ├─ [module] SwiftUI
   └─ Sources/IslandApp/Theme.swift

Rendered by: Sources/IslandApp/ExpandedView.swift
Background: NotchIslandShape + Theme.surface (Theme.swift)
```

---

## 3. Deck (with pending / running / done / all filters)

Starting file: `Sources/IslandApp/DeckView.swift`

```
Sources/IslandApp/DeckView.swift
├─ [module] IslandCore (AgentRow, DeckGroup, TaskFilter, IslandGeometry, IslandPresentation)
├─ [module] SwiftUI
├─ Sources/IslandApp/IslandViewActions.swift
├─ Sources/IslandApp/Theme.swift
│  ├─ [module] IslandCore (AgentStatus)
│  ├─ NotchBarShape, NotchIslandShape, StatusDot, Hairline, KeyCap
│  └─ TypeSize (10/11.5/12.5/13/13.5/15/17), Layout.pad = 20
├─ Sources/IslandApp/AgentMarkView.swift
│  ├─ [module] IslandCore
│  └─ Sources/IslandApp/Theme.swift
├─ Sources/IslandApp/Formatting.swift
│  └─ [module] IslandCore
└─ Sources/IslandApp/NotchEarsView.swift          (AmbientBarView notch band)
   ├─ [module] IslandCore
   ├─ [module] SwiftUI
   └─ Sources/IslandApp/Theme.swift

Rendered by: Sources/IslandApp/ExpandedView.swift
Background: NotchIslandShape gradient (Theme.bar/surface)
```

Filter behavior is computed upstream, not in the view: `Sources/IslandCore/Presenter.swift` (`makeDeckRows`, `makeGroups`, `makeDeckHeight`, `DeckFilterCounts`) from `IslandState.filter`, `.query`, `.isSearching`.

---

## 4. Detail

Starting file: `Sources/IslandApp/DetailView.swift`

```
Sources/IslandApp/DetailView.swift
├─ [module] AppKit (NSPasteboard for copy-command)
├─ [module] IslandCore (AgentRow, IslandGeometry, PreviewPresentation)
├─ [module] SwiftUI
├─ Sources/IslandApp/IslandViewActions.swift
├─ Sources/IslandApp/Theme.swift
│  ├─ [module] IslandCore (AgentStatus)
│  └─ NotchIslandShape, StatusDot, Hairline
├─ Sources/IslandApp/AgentMarkView.swift
│  ├─ [module] IslandCore
│  └─ Sources/IslandApp/Theme.swift
├─ Sources/IslandApp/Formatting.swift
│  └─ [module] IslandCore
└─ Sources/IslandApp/NotchEarsView.swift          (AmbientBarView notch band)
   ├─ [module] IslandCore
   ├─ [module] SwiftUI
   └─ Sources/IslandApp/Theme.swift

Rendered by: Sources/IslandApp/ExpandedView.swift
Background: NotchIslandShape gradient (black -> bar -> surface)
```

---

## 5. Quick task (Control+Option+N)

Starting file: `Sources/IslandApp/QuickTaskView.swift`

```
Sources/IslandApp/QuickTaskView.swift
├─ [module] IslandCore (AgentKindOption, QuickTaskPresentation)
├─ [module] SwiftUI
├─ Sources/IslandApp/IslandViewActions.swift
├─ Sources/IslandApp/Theme.swift
│  └─ [module] IslandCore (AgentStatus)
├─ Sources/IslandApp/AgentMarkView.swift
│  ├─ [module] IslandCore
│  └─ Sources/IslandApp/Theme.swift
└─ Sources/IslandApp/Formatting.swift
   └─ [module] IslandCore (IslandFormat.folderName)

Hosted by: Sources/IslandApp/ExpandedView.swift (taskSurface)
Background: NotchIslandShape gradient or Theme.surface (ExpandedView)
```

No notch ear band is drawn inside QuickTaskView; `ExpandedView` adds `AmbientBarView` above it. Geometry (`IslandGeometry.frame(quickTask: true)`) sets 420×196.

---

## 6. Window task

Starting file: `Sources/IslandApp/WindowTaskView.swift`

```
Sources/IslandApp/WindowTaskView.swift
├─ [module] AppKit (NSRunningApplication icon lookup)
├─ [module] IslandCore (AgentRow, IslandGeometry, WindowTaskPresentation)
├─ [module] SwiftUI
├─ Sources/IslandApp/IslandViewActions.swift
├─ Sources/IslandApp/Theme.swift
│  └─ [module] IslandCore (AgentStatus)
├─ Sources/IslandApp/AgentMarkView.swift
│  ├─ [module] IslandCore
│  └─ Sources/IslandApp/Theme.swift
└─ Sources/IslandApp/Formatting.swift
   └─ [module] IslandCore (IslandFormat.folderName)

Hosted by: Sources/IslandApp/ExpandedView.swift (taskSurface)
State source: Sources/IslandCore/WindowLock.swift (WindowTarget, WindowTaskState)
Capture effect: Sources/IslandApp/WindowCaptureService.swift (ScreenCaptureKit)
Panel effects: Sources/IslandApp/WindowDragCoordinator.swift, WindowTetherController.swift
```

No direct notch-band code: `ExpandedView` supplies `AmbientBarView` and the shared background.

---

## 7. Droplet input / drag (drop canvas + composer)

Starting file: `Sources/IslandApp/LiquidDropOverlay.swift`

```
Sources/IslandApp/LiquidDropOverlay.swift
├─ [module] AppKit, IslandCore, SwiftUI
├─ Sources/IslandApp/LiquidDropView.swift
│  ├─ [module] AppKit
│  ├─ [module] IslandCore (AgentKindOption)
│  ├─ [module] SwiftUI (NSViewRepresentable)
│  ├─ Sources/IslandApp/DesignMark.swift      (exact CGPath agent logos)
│  │  ├─ [module] CoreGraphics
│  │  ├─ [module] IslandCore (AgentKindOption)
│  │  └─ Sources/IslandApp/DesignMarkData.swift (generated 24×24 SVG path data)
│  └─ (defines CubicBezierEasing, LiquidDropRenderer, DropMarkRenderer)
├─ Sources/IslandApp/Theme.swift              (DropletBody tint, composer colors)
├─ Sources/IslandApp/AgentMarkView.swift
├─ Sources/IslandApp/Formatting.swift
│  └─ [module] IslandCore (folderName, RepoCheck)
└─ Sources/IslandApp/IslandViewActions.swift

Hosted by: Sources/IslandApp/IslandRootView.swift (always at zIndex 20)
State source: Sources/IslandCore/Reducer.swift (.beginDrop/.endDrop/.openDropComposer/.closeDropComposer)
Drag routing: Sources/IslandApp/WindowDragCoordinator.swift (Option-drag -> window lock)
Menu-bar lock droplet: Sources/IslandApp/DropletView.swift (AppKit only)
```

`LiquidDropOverlay` defines `DropletBody` / `DropletShape`, the floating `DropComposerCard`, and the transition modifier. `LiquidDropView` is a self-contained 60fps AppKit renderer; it only needs `AgentGlyphView` from `AgentMarkView.swift`.

---

## 8. Settings

Starting file: `Sources/IslandApp/SettingsView.swift`

```
Sources/IslandApp/SettingsView.swift
├─ [module] AppKit (NSWindow, NSHostingController, NSWorkspace)
├─ [module] IslandCore (IslandRules)
├─ [module] SwiftUI
├─ Sources/IslandApp/Theme.swift              (TypeSize tokens)
└─ Sources/IslandApp/IslandSettings.swift     (UserDefaults persistence)
   └─ [module] IslandCore (IslandRules)

Opened by: Sources/IslandApp/AppDelegate.swift (showSettings)
Also used by: Sources/IslandApp/StatusItemController.swift (menu item callback)
```

Settings is a separate centered `NSWindow` (440×500), not part of `IslandRootView`; it does not receive `IslandPresentation` or `IslandViewActions`.
