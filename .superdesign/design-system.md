# Herdr Island — Kinetic Instrument

## Product

Herdr Island is a macOS command surface for coding agents. It lives at the top of the screen, in the notch or the menu bar, and answers one question at a glance: **which agent needs me now?**

- **Ambient**: a black bar in the notch, with counts on the left and right ears, and a single orange droplet hanging below.
- **Attention deck**: a compact panel that opens under the notch. It contains blocked agents, running agents, and the handoff back to the terminal.
- **Peek**: a four-second glance at finished or blocked work.
- **Droplet**: a solid orange teardrop dragged out of the island or the status item to start a task anywhere on the desktop.
- **Quick task, window task, detail, settings**: the same instrument language at different sizes.

The product is used by developers who already live in terminals. The interface must feel like an instrument, not a dashboard. It must be fast to scan, dense without being cramped, and honest about what is running where. The UI copy is Simplified Chinese; agent names, model names, paths, commands and terminal output stay Latin.

## Visual direction: Kinetic Instrument

A flat, high-contrast control panel cut from black paper. **Orange is the only signal. White is the only light.** There is no glass, no blur, no gradient, and no soft shadow. Borders are visible. Corners are sharp. Type does the heavy lifting. Motion is mechanical, not decorative.

This is a deliberate replacement for the previous dark-glass look. Keep the product's behavior and spatial model; replace the material, color, type, and motion.

### Material logic

- **Black plate = observe.** Ambient, deck, detail and peek are black instrument plates with 2px white borders.
- **White paper = act.** The blocked attention card, quick task, window task, droplet composer and settings are white paper cards with 2px ink borders.
- **Orange = human decision.** Orange marks blocked work, the primary action, the active filter, the droplet and live counts. It is never decorative.

## Palette

Only these colors may appear in the UI:

| Token | Value | Use |
| --- | --- | --- |
| Signal | `#FF4D00` | blocked state, primary action, active filter, ticker, droplet, key numbers |
| Ink | `#000000` | app surfaces, menu bar, notch, text on white |
| Paper | `#FFFFFF` | attention card, form surfaces, primary text on black |
| White 62 | `rgba(255,255,255,.62)` | secondary text on black |
| White 24 | `rgba(255,255,255,.24)` | dividers and row borders on black |
| Black 62 | `rgba(0,0,0,.62)` | secondary text on white |
| Black 16 | `rgba(0,0,0,.16)` | dividers on white |

- Desktop / presentation backdrop: warm neutral `#D8D3C7` with a faint 32px grid, or a black-and-white photograph. It is the only place a warm neutral may appear; it is outside the app surface.
- No blue, mint, purple, pink, green or any other hue. Status is never color alone; it is always paired with a word.

### Status language

| State | Treatment | Word |
| --- | --- | --- |
| Blocked | Orange fill, ink text; white attention card; orange footer | `需要你处理` |
| Running | White outline, white text on black; orange index; ticker moving | `运行中` |
| Done | White 62 text, no fill; thin white check; peek appears | `已完成` |
| Idle | White 24 text, no fill; no motion | `空闲` |
| Error | Orange 2px underline + `!` glyph, ink text | `发送失败` |

## Typography

Load from Google Fonts: **Archivo Black**, **Space Mono**, **Inter**. Chinese falls back to **PingFang SC** (600 for display, 400/500 for body). Never use a serif.

| Role | Face | Size | Treatment |
| --- | --- | --- | --- |
| Board / wordmark | Archivo Black | 28–72px | uppercase, line-height .86, tracking -.04em |
| Big count | Archivo Black | 44–72px | tabular, orange or white |
| Panel title | Archivo Black / PingFang SC 600 | 18–22px | uppercase English, sentence-case Chinese, tracking -.02em |
| Row title | Inter / PingFang SC | 14–16px | weight 600, sentence case |
| Body | Inter / PingFang SC | 13–14px | weight 400, line-height 1.5 |
| Label / metadata | Space Mono | 9–11px | uppercase, tracking .08em |
| Terminal / command | Space Mono | 11–12px | lowercase, white on ink |
| Chinese display | PingFang SC 600 | 28–64px | tracking 0, line-height 1.15 |

Rules:
- Counts, indices and timers use tabular figures.
- Mono labels are uppercase and tracked; Chinese labels are never letter-spaced.
- Do not fake-bold Chinese; use PingFang SC 600.

## Layout and material

- App surfaces are `#000000` with `2px solid #FFFFFF` borders. Panels have `border-radius: 0`.
- White paper surfaces are `#FFFFFF` with `2px solid #000000` borders.
- The only rounded shapes are pills and status chips: `border-radius: 999px`. Buttons may be pills or sharp rectangles, never soft rounded cards.
- Dividers are 1px `rgba(255,255,255,.24)` on black and 1px `rgba(0,0,0,.16)` on white. Section boundaries may be 2px white/ink.
- No drop shadows. No backdrop blur. No glass. No inner shadows. No gradients.
- Hierarchy comes from hard black/white blocks, visible rules, scale and type weight.
- Base spacing: 4px. Use 8, 12, 16, 20, 24, 32, 48.
- The deck is 560px wide. The ambient bar is 28px high. Panels open 16px below the menu bar or notch with no fake crown.
- The notch and menu bar are pure black. The status item is a white half-capsule with an ink outline and an orange state dot; blocked adds an orange badge with ink text.

## Signature components

### Signal ticker

A 28px orange strip across the top of the deck. Ink Space Mono text scrolls slowly: agent, action, project, separated by `//`. It is the only continuous motion in the panel. 24s linear loop. Pause on hover. With Reduce Motion, it becomes a static line.

### Deck header

Black. A 24×24 white square mark (a half-capsule cut by the top edge) followed by the wordmark `HERDR` on line one and `ISLAND` on line two in Archivo Black. To the right, a large orange blocked count (`01`) with a `需要你处理` Space Mono label underneath, then a compact `02 运行中 / 00 已完成` stat block separated by 1px white/24 rules. Counts are tabular.

### Attention card (white paper)

The focal element. White fill, 2px ink border, no radius. Inside:
- an orange `BLOCKED` / `需要你处理` pill with ink text;
- title in Archivo Black / PingFang SC 600, 20px, ink;
- meta line in Space Mono, uppercase: `CODEX · CHECKOUT · JUST NOW`;
- the command on a black strip in white Space Mono;
- a black pill action `去终端处理 →` with white text.

### Running row

Black, 1px white/24 top border. A large orange index (`02`), a white Inter 600 title, a Space Mono meta line, and a white-outline `运行中` pill. The row is 64px tall. No avatar illustrations; use a 2px white square with the agent's initial in Space Mono, or the agent's real mark in white.

### Done row

Black, 1px white/24 top border, 56px tall. A white check glyph, white 62 title, mono meta, and a `已完成` label in white 62. No orange.

### Footer

Solid orange bar, 2px ink top border. Left: `等待你的决定` in Archivo Black / PingFang SC 600 16px ink, with a Space Mono subline `批准与回答留在终端完成`. Right: a black pill `打开终端 ↗` in white Space Mono. This is the loudest element in the panel, and it appears only when a human is required.

### Droplet

A solid `#FF4D00` teardrop with a 2px ink outline and a small flat white highlight. No gradient, no glow. It hangs under the notch or status item. Dragging stretches it along the pointer; a 1px orange tether trails from the notch and snaps at 96px; releasing plants it and opens the composer at that point.

### Composer

White paper panel, 2px ink border, zero radius. A black input strip with white Space Mono text. Model chips are black-outline pills; selected is orange fill with ink text. The primary `开始` button is an orange pill with ink text. The isolation checkbox is a 2px ink square with an orange check.

## Surfaces

### Ambient notch

- Menu bar 28px, pure black. Camera notch centered; ears 72px each side.
- Left ear: `1 待处理` with an orange 6px square; idle is `安静` with a white/24 square.
- Right ear: `5 运行` in white; else `1 完成`; else `空闲`.
- 1px white/24 bottom border; 10px radius on the bottom corners only.
- Droplet 11×15, 6px below the notch center, solid orange with a 2px ink outline and a flat white highlight.
- Status item 22×18: white half-capsule, 2px ink outline, orange dot; blocked adds an orange badge with ink `1`.

### Peek — 400×248

Black plate, 2px white border, no radius, 16px below the notch. Orange 28px top strip with static mono `1 DONE // checkout // just now`. White result card inset 16px with 2px ink border: agent initial square, title, meta, black `打开` pill. Footer mono `1 运行中` left, black `打开面板 →` pill right. A 2px orange bottom progress bar drains over 4s. Blocked variant: orange strip, orange `需要你处理` pill, command on a black strip.

### Deck — 560×620

Black plate, 2px white border, 16px below the notch. Top: 28px orange ticker. Header 84px. Filter row: four segments in Space Mono 10px; active is orange fill with ink text, counts tabular. Content: one white attention card (132px), two 64px running rows, one 56px done row. Footer: solid orange 64px bar when blocked. Inline composer: black field with 1px white/24 border and an orange send square. Bottom keycap bar 28px: `/ 搜索  R 回复  S 稍后  ⏎ 详情  ESC 收起`.

### Detail — 660×640

Black plate, 2px white border. Left rail 210px with grouped list, orange indices, white titles, mono meta; selected row has a 2px orange left border and white/8 fill. Right: header with agent mark, title, meta, status pill. Blocked card white with orange pill, question, black command strip. Terminal well pure black with 1px white/24 border, 11px Space Mono, monochrome output with orange prompt; no syntax colors. Action row: orange primary `去终端处理`, white-outline `稍后`, mono ghost `复制命令`. Footer safety note 10px mono white/62.

### Quick task — 420×196

White paper card, 2px ink border. Header: black droplet glyph, `新任务` in PingFang SC 600 16 ink, mono `从当前目录开始`. Agent chips: black-outline pills 24px; selected orange fill, ink text. Input: black strip 40px with white Space Mono `输入任务…`. Footer: `herdr-island` cwd chip, worktree checkbox (2px ink square, orange check), orange `开始 →` pill.

### Window task — 560×510

White paper card, 2px ink border. Header: black window glyph, window title in PingFang SC 600 16 ink, app name mono, orange lock square + `锁定`. Capture card: black 96×64 well with a 2px dashed white/62 border, `发送时截取这个窗口`, `900 × 620`, privacy line. Task field: black strip 120px with white mono. Target row: `发送到` + agent pills (selected orange). Suggestion chips: black-outline pills. Primary `截图并发送` orange pill bottom-right. Footer mono black 62.

### Droplet composer — 340×260

White paper card, 2px ink border, 12px above the drop point. Header, model chips, 3-line black input, orange `开始` pill, worktree checkbox, footer. A 3px orange tether at the top center fades after 160ms. One ripple ring at the release point; no permanent line.

### Settings — 440×500

White paper window, 2px ink border. Title `设置` in Archivo Black / PingFang SC 600 18. Grouped rows separated by 1px black/16. Toggles are 2px ink squares with an orange check; steppers are black-outline pills. Footer mono black 62. This is a control sheet, not a black console.

## Motion

- Panel open: 220ms, clip-path wipe from the top edge. No soft spring, no scale-from-center.
- Panel close: 140ms, wipe upward.
- Ticker: 24s linear marquee. Pause on hover.
- Number change: 160ms vertical flip, no layout shift.
- Blocked attention: 1.2s step pulse on the orange pill or border, not a soft glow.
- Droplet drag: follows the pointer with a slight velocity stretch; a 1px hard tether snaps at 96px; return 260ms ease-out.
- Hover: 90ms, hard color inversion or 2px underline, not opacity fade.
- Peek → deck: 220ms, the white result card expands into the deck header area; no cross-fade.
- Reduced motion: stop the ticker, replace pulses with a static orange state, make panel changes instant. Dragging still follows the pointer.

## Copy

Terse Chinese; no exclamation marks, no emoji, no "AI magic" language.

- Status: `需要你处理`, `运行中`, `已完成`, `空闲`, `发送失败`.
- Actions: `去终端处理`, `打开终端`, `稍后`, `复制命令`, `开始`, `截图并发送`, `打开面板`.
- Safety: `批准与回答留在终端完成，岛不会代为操作。`
- Avoid: `智能`, `一键`, `超级`, `魔法`, `效率翻倍`.

## Accessibility

- Body text on black is white at 100%; secondary text is at least white 62. On white, body is ink; secondary is at least black 62.
- Every interactive element has a visible `:focus-visible` 2px orange outline offset 2px.
- Status is never color alone; the word is always present.
- Minimum hit target 32×32px; primary actions 40px tall.
- `prefers-reduced-motion` stops the ticker, pulses and wipes.
- No information is conveyed by hover alone.

## Do not

- Do not use glassmorphism, blur, translucency, gradients, glows, or soft shadows.
- Do not use blue, mint, purple, pink, or any hue outside the palette.
- Do not use rounded cards, large corner radii, or floating pill containers for whole panels.
- Do not use serif type, emoji, generic AI brains/sparkles, or fake code screenshots.
- Do not turn the app into a landing page, dashboard, or analytics screen.
- Do not add decorative illustrations or stock photography inside the app panels.
- Do not use orange on more than one primary action per surface.
