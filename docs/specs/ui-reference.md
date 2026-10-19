# Wispr Flow 1.6.1147 — UI reference for the rebuild

Static UI reference for **Wispr Flow 1.6.1147** (`com.electron.wispr-flow`, LSMinimumSystemVersion 12.0). Every value below was read from the installed bundle without running it: the Electron `app.asar` (webpack main and renderer bundles), the CSS that the renderers inject at runtime, `Resources/assets`, the native Swift helper, `Info.plist` files and `afinfo` on the sound files. The app was never launched, the screen was never captured, and no user data was read.

Companion docs: `behaviour.md` (what happens), `strings.md` (wording), `local-models.md` (on-device models). Section numbers here are referenced as "UI §n".

## Evidence tags

| Tag | Meaning |
|---|---|
| **[C nnnnn]** | CSS from a renderer bundle. The styles are CSS Modules compiled by css-loader and injected by style-loader, so the CSS text sits inside the JS as strings. Class names were recovered from each module's `locals` map. `nnnnn` is the webpack module id, so the rule can be found again. |
| **[J]** | Renderer JavaScript: React components, constants, timers. |
| **[M]** | Main-process JavaScript (`.webpack/main/index.js`): `BrowserWindow` options, geometry functions, preference defaults. |
| **[R]** | A resource: an asset file, `Info.plist`, `afinfo`/`identify` output, an asset catalog. |
| **[U]** | Inferred, derived by arithmetic from several rules, or not proven by one rule. Check before relying on it. |

**Units.** CSS `px` in Electron equals one macOS point. All sizes below are in points.

## Architecture notes (for porting)

- **Electron app.** Each surface is its own `BrowserWindow` running a React renderer. The windows are:
  - `status`: the **Flow Bar** (floating pill), titled "Flow Status Indicator".
  - `hub`: the main window, titled "Flow Hub". It also hosts onboarding and the Settings modal.
  - `contextMenu`: a transparent window covering the whole work area. It draws the Flow Bar's right-click menu and some popovers.
  - `scratchpad`: the "Scratchpad" notes window.
  - `accessibility_drop`: a small panel that helps the user drag the app into the Accessibility list.
  - `overlay`: extension panels (iframes).
  - `meeting_recorder`: the Notetaker **notepad** window (UI §10.1).
  - Out of scope: `feature_tour` (tour overlay plus a 45 % black dim window) and `meeting_ax_inspector` (internal debugging).
- **Native Swift helper** (`swift-helper-app-dist/Wispr Flow.app`, `LSUIElement`). It draws no UI of its own: its asset catalog holds only the app icon and logos. It has a `FloatingWebPanelWindow` and window-positioning code used by the Notetaker's split-screen join (UI §10.1). A nested `FlowPermissionGuide.app` (macOS 26+) uses the third-party *Permiso* Swift library to show a passive overlay panel next to System Settings, with a draggable app icon and an arrow. See UI §5.5 [R][B strings].
- **One design system everywhere.** Every renderer re-injects the same token sheet (`[C 40564]`) and shared components:
  - Button `[C 82099]`, IconButton `[C 70809]`, Text `[C 50717]`, Heading `[C 43861]`, display Heading `[C 33357]`.
  - Stack `[C 14749]`, Tooltip `[C 92709]`, Toast `[C 11102]`, Modal `[C 93976]`, Switch `[C 86115]`, Input `[C 1013]`, Menu `[C 15245]`.
- **Porting.**
  - The rebuild is native: AppKit panels plus SwiftUI content.
  - Map CSS `transition` and `@keyframes` to Core Animation or SwiftUI animations. Map `linear(...)` spring easings to a spring with a similar curve. The control points are given below.
- **Readable CSS dumps.** The extracted, de-hashed CSS for every window is in `scratchpad/flow/css/*.css`. It is a lookup aid only and is not part of the repo.

---

## 1. Global design tokens

### 1.1 Raw palette (`:root, [data-theme=light]`) [C 40564]

Brand scales (50 → 950):

| Scale | 50 | 100 | 200 | 300 | 400 | 500 | 600 | 700 | 800 | 900 | 950 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **sand** (warm off-white) | #fcfcfb | #faf9f7 | #f8f7f3 | #f7f6f2 | #f6f5f1 | #f5f4f0 | #eeebe3 | #c5c0b3 | #a39d8e | #736e62 | #4d4a42 |
| **vast** (neutral greys) | #e9e8e1 | #deddd7 | #c8c8c2 | #b3b2ad | #9d9c98 | #878683 | #71716e | #5b5b59 | #464544 | #30302f | #1a1a1a |
| **dawn** (lilac) | #fdfbff | #fcf7ff | #faf1ff | #f7ebff | #f4e1ff | #f0d7ff | #d2ace9 | #a26ec1 | #6c358c | #502b66 | #3c2947 |
| **signal** (pink) | #fffcfe | #fff2fc | #ffe4fa | #ffd7f7 | #ffc9f5 | #ffbcf2 | #e78bd5 | #c56cb4 | #a3398f | #7d266c | #3f0433 |
| **lumen** (cream) | #fffffd | #fffffb | #fffff5 | #ffffef | #ffffeb | #f7f7db | #efefc9 | #e2e2ac | #d3d388 | #bfbf68 | #a9a939 |
| **fathom** (teal) | #e2f5f2 | #ceedea | #b8e4dc | #9fd9cf | #84cdc1 | #68bdb0 | #4daa9d | #369489 | #247872 | #1a5c5c | #034f46 |
| **pulse** (rose) | #fdf2f3 | #fce3e5 | #fac7cc | #f99ea9 | #df7a88 | #bd5768 | #96384a | #7f1c34 | #500a1d | #320510 | #180205 |
| **flare** (coral) | #fdf2f0 | #fce4de | #fac9be | #f9a28e | #ff6c4c | #d34528 | #a6280b | #751d0a | #4e1206 | #300903 | #180301 |
| **glow** (amber) | #fdf3ea | #fce5d1 | #facda1 | #ffa946 | #d7892a | #af6a06 | #834f0c | #5c370b | #3c2407 | #251403 | #110701 |
| **chord** (violet) | #f7f3fd | #efe5fc | #e1cbf9 | #cea8f8 | #c29be1 | #965ace | #7232a6 | #571b83 | #3a0c5b | #230639 | #10021d |

Extra vast steps: `--vast-875 #343432`, `--vast-910 #2a2a29`, `--vast-925 #202020`. Other raw colours: `--pure-white #ffffff`, `--pure-black #000000`.

`red`, `orange`, `green`, `blue` and `yellow` 50–950 are the stock Tailwind v3 values. Examples: `--red-600 #dc2626`, `--green-400 #34d399`, `--green-500 #10b981`, `--blue-600 #2563eb`. There is one extra step, `--red-450 #ff5757`.

Named singles (light):

| Token | Value |
|---|---|
| `--lumen` | #ffffeb |
| `--fathom` | #034f46 |
| `--accent` | #fff |
| `--shade-white` | #fff |
| `--shade-black` | #000 |
| `--muted-hover` | #f1ebe1 |
| `--success-100` / `-500` / `-700` | #d4f6e1 / #4fbf78 / #368855 |
| `--warning-400` / `-700` | #ffd467 / #efa249 |
| `--destructive-400` / `-500` / `-700` | #f87171 / #ee6a6a / #bc3d3d |

### 1.2 Semantic tokens, light vs dark [C 40564]

Dark applies under `[data-theme=dark]` on `<html>`. Light is the default: the attribute is absent.

| Token | Light | Dark |
|---|---|---|
| `--background` | sand-50 #fcfcfb | vast-950 #1a1a1a |
| `--background-secondary` | sand-600 #eeebe3 | vast-900 #30302f |
| `--background-tertiary` | sand-500 #f5f4f0 | vast-925 #202020 |
| `--card` | pure-white | pure-black |
| `--popover` | sand-50 | vast-950 |
| `--primary` | vast-950 #1a1a1a | sand-50 #fcfcfb |
| `--primary-foreground` | sand-50 | vast-950 |
| `--foreground` | vast-950 | vast-50 #e9e8e1 |
| `--foreground-secondary` | vast-950 | vast-100 #deddd7 |
| `--foreground-tertiary` | vast-600 #71716e | vast-400 #9d9c98 |
| `--border` | sand-600 #eeebe3 | vast-900 #30302f |
| `--ring` | sand-950 #4d4a42 | sand-600 |
| `--destructive` | red-600 | red-450 #ff5757 |
| `--destructive-foreground` | red-100 | red-600 @ 15 % |
| `--info` / `-foreground` | blue-600 / blue-100 | blue-400 / blue-600 @ 20 % |
| `--success` / `-foreground` | green-600 / green-100 | green-400 / green-400 @ 15 % |
| `--warning` / `-foreground` | orange-600 / orange-100 | orange-500 / orange-500 @ 15 % |
| `--recording-foreground` / `-background` | green-600 / green-50 | green-400 / green-400 @ 15 % |
| `--neutral-10/50/100/200/300/400/500/600/800/900` | sand-50 / sand-500 / sand-500 / sand-600 / sand-600 / sand-950 / sand-950 / vast-900 / vast-950 / vast-950 | background / bg-tertiary / bg-tertiary / border / border / fg-tertiary / fg-tertiary / fg-secondary / foreground / foreground |
| `--shade-white` / `--shade-black` | #fff / #000 | **background / foreground (inverted)** |

Notes:

- **Dark-mode SVG rule.** In dark mode, SVG `path`, `rect` and `circle` elements filled `#312D37`, `#1A1A1A` or `#49454D` are recoloured to `currentcolor` [C 40564].
- **Theme switching** [J].
  - Preference `theme`, default `"light"` [M]. Light deletes `data-theme`; any other value sets it.
  - The switch uses a View Transition cross-fade of **200 ms** (`html[data-theme-transition=fade]`). While switching, a temporary style kills all other transitions.
- **The Flow Bar window never sets `data-theme`.** It always resolves the light values, so the pill stays black (`--shade-black #000`) whatever the system appearance [J][C].
- **Onboarding pages force light** (`data-theme="light"`) [J].

### 1.3 Typography [C 40564][C 50717][C 43861][C 33357]

Global defaults: `html { font-family: Figtree, sans-serif; font-feature-settings: "salt" on; -webkit-font-smoothing: antialiased; }` and `strong { font-weight: 600 }`.

**Font families** (bundled variable TTFs in `Resources/assets/fonts`) [R]:

| Family | Files | Weight axis | Used for |
|---|---|---|---|
| **Figtree** | `Figtree-VariableFont_wght.ttf`, `-Italic-` | 100–900 | All UI text (default) |
| **EB Garamond** | `EBGaramond-VariableFont_wght.ttf`, `-Italic-` | 100–900 | Display headings: page titles, onboarding hero lines, big numbers. Accent words in italic. |
| **Google Sans Code** | `GoogleSansCode-VariableFont_wght.ttf`, `-Italic-` | 100–900 | Monospace: Transform prompt codes and the label in the processing pill. Fallback `menlo, consolas, monaco, monospace`. |
| **Manrope** | `Manrope-VariableFont_wght.ttf` | 200–900 | Diff view text ("See changes"), 14 px, line-height 2 |

**Text component** (`size-*-{regular|emphasis|strong}`; weights 400 / **550** / 600) [C 50717]:

| Size | font-size / line-height |
|---|---|
| lg | 18 / 28 |
| md | 16 / 24 |
| **sm (body default)** | **15 / 20** |
| xs | 12 / 20 |
| xxs | 10 / 18 |

Text colours: default `--foreground`, muted `--foreground-tertiary`, primary `--primary`, destructive `--destructive-500`, warning `--warning-400`, success `--success-500`. Usage across the hub: 15/20 appears 602 times, 12/20 345 times, 16/24 129 times.

**Heading, sans** (weight 600) [C 43861]:

| Level | Size / line-height |
|---|---|
| 1 | 32 / 40 |
| 2 | 28 / 34 |
| 3 | 24 / 32 |
| 4 | 20 / 28 |
| 5 | 18 / 24 |

**Heading, serif display** (EB Garamond 400, `letter-spacing: -0.04em`) [C 33357]:

| Level | Size / line-height |
|---|---|
| 1 | 72 / 72 |
| 2 | 48 |
| 3 | 36 |
| 4 | **28 / 28** (Settings page titles, card values) |

Hero numerals elsewhere use 108 px with `letter-spacing: -4.32px`.

**Section labels** (Settings sidebar, onboarding progress): 12/20, weight 600, `text-transform: uppercase`, `letter-spacing: .075em` [C 58560][C 32437].

### 1.4 Spacing scale (Stack `gap-*`) [C 14749]

0, 2, 4, 8, 12, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112.

### 1.5 Corner radii (frequency in hub CSS) [C]

| Radius | Count |
|---|---|
| 8 | 217 |
| 12 | 136 |
| 6 | 135 |
| 4 | 110 |
| 16 | 81 |
| 9999 (pill) | 68 |
| 2 | 35 |
| 10 | 27 |
| 24 | 22 |
| 20 | 16 |

The Flow Bar uses **22.5** (UI §2).

### 1.6 Shadows (ink `rgba(26,26,26,…)`) [C]

| Name [U] | Value | Typical use |
|---|---|---|
| xs | `0 1px 2px 0 .05` | notification container |
| sm | `0 1px 3px 0 .1, 0 1px 2px -1px .1` | badges |
| md | `0 4px 6px -1px .1, 0 2px 4px -2px .1` | onboarding key block |
| lg | `0 10px 15px -3px .1, 0 4px 6px -4px .1` | menus, condensed toast |
| xl | `0 20px 25px -5px .1, 0 8px 10px -6px .1` | modals, Settings modal |
| 2xl | `0 25px 50px -12px .25` | large overlays |

### 1.7 Z-order (CSS) [C]

| Layer | z-index |
|---|---|
| Tooltip, Flow Bar tooltip positioner | 900 |
| Blur overlay dialogs | 800 |
| Modal overlay | 700 |
| Menu positioner | 600 |
| Onboarding content | 500 |

### 1.8 Motion [C][J]

**Named easings:**

| Name | Definition |
|---|---|
| **Snap** | `cubic-bezier(0.05, 0.6, 0.4, 0.95)`. Every Flow Bar size change uses it, at **100 ms**. |
| **Spring** (`--spring-easing`) | `linear(0, 0.005, 0.019 1.8%, 0.079 3.9%, 0.476 13.5%, 0.663 19.1%, 0.738 22%, 0.8 25.1%, 0.852 28.4%, 0.894 32%, 0.928 36%, 0.953 40.5%, 0.972 45.6%, 0.985 51.6%, 0.997 67.3%, 1)`. Overdamped, about 0.5 s settle. Used with 150 ms for sidebars, switches and modals, and with 420 ms for notification morphs. |
| **Toast** | `linear(0, 0.007, 0.026 2.9%, 0.106 6.3%, 0.558 19.3%, 0.742 25.6%, 0.87 31.7%, 0.918, 0.957, 0.986 41.6%, 1.007 45.3%, 1.021 49.4%, 1.027 54% 60.9%, 1.007 83.2%, 1)`. Slight overshoot. |
| Material | `cubic-bezier(0.4, 0, 0.2, 1)` (post-Transform width/height, 250–400 ms) |

**Shared keyframes:**

| Keyframe | Definition |
|---|---|
| `spin` | 0→360° |
| `fade-in` / `fade-out` | opacity 0↔1 |
| `pulse` | 50 %: opacity .05 |
| `shimmer-sweep` | background-position 150 % → −150 % |
| `rainbow-gradient-wave` | background-position 100 % → 0 % |
| `rainbow-pill-ring-spin` | conic ring rotates 360°, 6 s linear |

`prefers-reduced-motion: reduce` turns off the waveform keyframes, the meeting transitions and the tooltip slide.

### 1.9 Brand marks [R]

- **App icon** (`electron.icns`, 16–1024 px):
  - A macOS squircle with a vertical gradient from **#393148** (top) to **#191521** (bottom).
  - Five rounded white bars (**#f5f5f5**), tall–short–mid–short–tall: a "W" built from audio bars.
  - Reference: `scratchpad/flow/assets/images/app-icon-256.png`.
- **Word mark** `flowLogo.png` (427×123): the bar glyph followed by "Flow" in a geometric sans, ink about #1a1a1a.
- **Rainbow accent** (processing ring and Transform labels):
  - Conic ring: `#f0d7ff → #ffbcf2 → #ff6c4c → #ffa946 → #7232a6 → #f0d7ff`.
  - Label gradient: `#FFD5A4, #FFAB9A, #FFC1F4, #DBA0FF`.

---

## 2. The Flow Bar (status window)

### 2.1 Window [M]

| Option | Value |
|---|---|
| Title | "Flow Status Indicator" |
| `type` | `"panel"` on macOS (`"toolbar"` on Windows) |
| `transparent` / `backgroundColor` | true / `#00000000` |
| `frame` / `hasShadow` / `roundedCorners` | false / false / false |
| `focusable` | `allowBubbleFocus`, default **false** (a non-activating panel) |
| `resizable`, `movable`, `minimizable`, `maximizable`, `closable`, `fullscreenable` | all false |
| `skipTaskbar` | true |
| `hiddenInMissionControl`, `titleBarStyle:"hidden"` | macOS |
| `alwaysOnTop` | true, level **`"screen-saver"`** (re-asserted every time it is shown) |
| `setVisibleOnAllWorkspaces` | `true, {visibleOnFullScreen: true, skipTransformProcessType: true}` |
| `setIgnoreMouseEvents` | `true, {forward: true}` by default. On macOS a poll checks the alpha under the cursor and turns mouse events on only over opaque pixels. On Windows it uses `setShape(rects)` with up to 128 rects reported by the renderer. |
| `backgroundThrottling` | false |
| Shown with | `showInactive()`: it never takes focus |
| Content protection | `setContentProtection(true)` only while a meeting is being recorded and `hideMeetingRecorderInScreenShare` is on, so the bar does not appear in screen shares (UI §10.2) |

**Rebuild mapping:**

- Use a borderless, non-activating `NSPanel` at `.screenSaver` level with `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
- Turn on `ignoresMouseEvents` except over the pill's hot area. A tracking area or a `hitTest` override replaces the alpha poll.

### 2.2 Window geometry and position [M module 58601]

The window is a large transparent canvas. The pill is drawn inside it.

| Dock edge (`statusDockEdge`, default **"bottom"**) | Window size | Position |
|---|---|---|
| **bottom** | **512 × 614** | x = workArea.x + (workArea.width − 512) / 2; bottom edge = bottom of the usable area |
| left / right | **490 × min(1144, usable height)** | flush to the left or right edge (past any side Dock), vertically centred |

Details:

- **Usable area (macOS).**
  - It starts from `workArea`.
  - When the Dock is set to auto-hide, the Dock's strip is added back, so the bar sits near the very bottom of the screen.
  - The menu bar inset is kept.
- **Following displays** [M].
  - Every **400 ms** the main process reads the display under the mouse cursor and recomputes the bounds.
  - If they changed it moves the window. The move is animated when it is under 100 pt; otherwise it jumps.
  - Then it sends `status:monitorChanged`.
  - During a Dock-edge transition the window fades to opacity 0 and comes back after at most 600 ms.
- **Dock visibility (1.6.1174)** [M module 58601][helper `DockWindowObserver`]:
  - The native helper polls every **0.5 s** (100 ms leeway): `CGWindowListCopyWindowInfo(onScreenOnly | excludeDesktopElements)`, windows owned by "Dock", skipping the ⌘-Tab switcher (`AXProcessSwitcherList`, 0.2 s AX timeout). It sends `DockInfoUpdate {isVisible, x, y}` when that changes; the main process relayouts on a visibility change.
  - Dock visible: the usable area is `workArea`. Dock not visible (a full-screen space): the Dock's strip (left, right, bottom) is added back; the menu-bar inset stays.
  - The window's bottom edge is the usable area's bottom; the move is animated (AppKit's own window-move time) when it is under 100 pt on both axes.
- **Rebuild** (`FlowBarPlacement`): the same rule per screen. `visibleFrame` while the Dock shows; the strip added back when the Dock is hidden (an inset of 8 pt or less) or the screen shows a full-screen space, detected from window bounds only (no Screen Recording): normal-level windows that each reach from the screen's bottom edge to the menu bar's line and together span its width (one app, or Split View). Re-evaluated every 400 ms and on space, front-app, display and `com.apple.dock.prefchanged` changes; short moves glide for `animationResizeTime`, Reduce Motion jumps. An auto-hidden Dock that slides in is not tracked (neither does the original).
- **Pill offset from the bottom** [U, derived from UI §2.3]:
  - The pill's bottom edge sits **14 pt above the bottom of the usable area**: the hover area's 8 pt bottom margin plus the hot area's 6 pt padding.
  - It is centred horizontally.
  - On the left or right edge, the pill sits about 6 pt in from the edge.

### 2.3 Layout inside the window [C 29][C 31201]

```
rootContainer (100vh, flex; bottom: column, align centre, justify end, gap 16)
 └ islandStage (bottom: 420 × 300, content aligned bottom-centre; left/right: 440 × 420)
    ├ notificationLayer (absolute; bottom: 14 above window bottom, centred)
    ├ indicatorLayer    (absolute; bottom: 0, centred, pointer-events none)
    │   └ hoverArea (bottom: height 40, margin −6 9 8, items aligned to bottom)
    │       └ hotArea (padding 6 10 [bottom] / 6 [side]; gap 6; background rgba(0,0,0,.004) so it can be hit)
    │           └ bubbleWrapper → [leftPickers] bubbleContainer → thoughtBubble → rowContainer [rightPickers]
    └ reminderLayer (typing-reminder pill; bottom: 14 above window bottom, centred)
```

- When the bubble is in the *ready* state, `hotArea::before` grows the hit target by **12 pt on every side**.
- `.thoughtBubble` carries `transition: all .1s cubic-bezier(0.05,0.6,0.4,0.95)`. Every change of size, colour and radius between states animates with it.

### 2.4 States [J enum `fw`][C 31201]

Fill = `--shade-black` **#000**. Border = **1 px `--vast-900` #30302f**. Radius = **22.5**. Sizes are width × height for the bottom edge. On the left or right edge the two values swap: the pill turns vertical, with the same numbers transposed.

| State (`fw`) | CSS class | Bottom size | Fill / border | Content |
|---|---|---|---|---|
| `hidden` | `fadeOut` | — | opacity 0 | none. Used before onboarding finishes and when the bar is hidden (UI §2.15). |
| **`resting`** (idle) | `resting` | **40 × 8** | `rgba(0,0,0,.5)` / **1 px `rgba(255,255,255,.5)`**, radius **6** | waveform present at opacity 0 (13 × 5). The resting bar is a thin translucent capsule. |
| **`ready`** (hover over the resting bar) | `ready` | **50 × 30** | black / #30302f. Hover: **#30302f / #5b5b59**. | microphone glyph (12 × 16, `--shade-white`); pickers appear beside the pill (UI §2.9) |
| `context-menu` | `ready` | 50 × 30 | as ready | mic glyph; the menu is open in the contextMenu window |
| `initializing` | `activePtt` | 73 × 30 | black / #30302f | waveform, bars dim |
| **`active_ptt`** (push-to-talk held) | `activePtt` | **73 × 30** | black / #30302f | **10-bar waveform** (UI §2.6) |
| **`active_popo`** (hands-free) | `activePopo` | **102.5 × 30** | black / #30302f | **[✕ cancel] [waveform] [✓ finish]**. Buttons are 18 × 18 circles (UI §2.5); row gap 4. |
| **`processing`** | `processing` | **98 × 30**, padding 6 12 | black / #30302f | static dim waveform + **8-spoke spinner** (UI §2.7); row gap 6 |
| `polish_processing` | `polishProcessing` | 136 × 30, padding 6 12; width and height transition 250 ms Material | black / #30302f | progress fill + label + spinner (UI §2.11) |
| `polish_completed_action` | `polishCompleted` | **152 × 30** | black; hover #4a4a4a, border #5b5b59 | "Done. See changes" (UI §2.11) |
| `polish_completed_na`, `polish_failed` | `resting` | 40 × 8 | as resting | — |
| `auto_cleanup_completed` | `autoCleanupCompleted` | max-content × 30 | black; hover #4a4a4a | "Cleaned up! See what's changed" |
| `hotkey_reminder` | `growthNudgeActive` | fit-content × **32** | black / #30302f | nudge text (UI §2.13) |
| `instruct_completed` | `postInstructBubble` | fit-content | transparent | entry animation 280 ms `cubic-bezier(0.2,0.7,0.3,1)`, from scale .9 / opacity 0 |
| **`error`** | `error` | **91 × 30**, padding 6, gap 2 | black / **1.5 px `--destructive-500` #ee6a6a** | waveform (dim) |

Mode overlays, added on top of the state:

| Mode | Class | Effect |
|---|---|---|
| **Command Mode** | `commandMode` | border **1 px #ffa946** (glow-300); waveform bars **#ffa946**; spinner tint `rgba(255,169,70,…)` |
| Instruct Mode | `instructMode` | border **1.5 px `--signal-500` #ffbcf2**; bars and spinner pink. On the bottom edge, ready / ptt / popo / processing / error become an auto-width capsule, 30 tall, padding 0 12, radius 500. |
| Rainbow processing (experiment) | `rainbowProcessing` | 400 × 400 conic ring (UI §1.9) spinning 6 s, behind an inset-1 black fill; no border |
| **Meeting** (Notetaker recording) | `meetingMode` | **2 px `--green-500` #10b981** border, 5-bar waveform, stop button. Full spec in UI §10.2. |
| Collapse from Instruct | `instructCollapsing` | animates back to 40 × 8 in 300 ms (snap); background, border and radius over 200 ms |

### 2.5 Hands-free buttons [C 31201][J]

| Button | Size | Fill | Glyph | Tooltip |
|---|---|---|---|---|
| **Cancel** (left) | 18 × 18 circle | `--sand-950` **#4d4a42** | "x" glyph, 12 pt, stroke 3, colour `--sand-50` | "Cancel" |
| **Finish** (right) | 18 × 18 circle | `--background` **#fcfcfb** | "check" glyph, 12 pt, stroke 3, colour `--foreground` #1a1a1a | "Finish and paste" |

- In every other state both buttons collapse to 0 × 0, animated with the same 100 ms snap.
- A disabled button gets opacity .4.

### 2.6 Waveform [J component `z_`][C 60666][C 31201]

| Property | Value |
|---|---|
| Bar count | **10** (`barCount` default) |
| Bar size | width **2**, min-height 2, radius 0.5 |
| Gap | 2 |
| Container (bottom edge) | height 18, padding 8 4, row. Content box is 46 × 2 [U]. |
| Container (side edge) | width 18, padding 4 8, column; bars become 2-tall horizontal strokes scaled on X |
| Colour, silent or not yet capturing | `rgba(255,255,255,.4)` |
| Colour, mic active (speech) | **#fff** |
| Per-bar height weight | `max(0, 1 − d² / 48)` where d = `|4.5 − i|`, giving **0.578, 0.745, 0.870, 0.953, 0.995, 0.995, 0.953, 0.870, 0.745, 0.578** |
| Live scale | `scaleY(audioScale × weight × k)`, transform-origin centre |
| `audioScale` | `max(1, 5 × level)`, so the range is 1–5. Gain is 5 for dictation, 2 for meetings. |
| Idle oscillation `k` | keyframes `wave`, **1 s, ease-in-out, infinite**: 0 % ×1, 20 % ×1.2, 40 % ×1.5, 80 % ×1.1, 90 % ×1.3, 100 % ×1 |
| Phase offsets | `animation-delay` = 0, .1, .2, .3, .4, −.5, −.4, −.3, −.2, −.1 s for bars 0…9 |
| Maximum visual height | 2 × 5 × 0.995 × 1.5 ≈ **15 pt** inside the 30 pt pill [U] |
| When the oscillation runs | only while speech is detected (`showWaveformAnimation`). In silence the bars sit at 2 × 2 dots at 40 % white. |
| Reduced motion | no keyframes; only the level scale |

Reference renders: `assets/videos/waveform.mp4` (730×300, 7.5 s) shows exactly this pill: black capsule, grey rim, 10 white bars, centre-weighted. A frame is saved as `scratchpad/flow/assets/onboarding/waveform-mp4-3s.png`.

**Mini waveform** (inside notifications and reminders) [C 62242]:

- 5 bars, 2 wide, gap 2, box height 10.
- Gains .8, 1, 1.2, 1, .8; delays .2, .3, .4, −.5, −.4 s.
- `--audio-scale = 5 × level`.

### 2.7 Audio-level pipeline [M][J hook `Bl`]

1. **Per audio packet** (the worklet sends 640-sample chunks): `dB = 20·log10(rms + 1e-10)`.
2. **Adaptive scaler.**
   - The floor starts at 0 dB and follows the quietest dB seen, never below **−60 dB**.
   - `level = clamp((dB − floor) / 20, 0, 1)`.
3. **Batching.** Levels are averaged over **150 ms** and sent to the bar (`status:audioLevel`).
4. **Smoothing in the bar, per animation frame** (dt clamped to 1–200 ms):
   - `a = prev·0.85^(dt/16.67) + target·(1 − 0.85^(dt/16.67))`.
   - The change is then **slew-limited to 1.6 units/s** and floored to 0.01.
   - It writes `--audio-scale = max(1, 5·a)`.
   - It stops ticking once both target and value reach 0.

### 2.8 Processing spinner [J `i_`][C 64037]

- 16 × 16 box with **8 spokes**. Each spoke is 2 × 5, radius 1, `rotate(45°·i) translate(0, −6)`.
- Colour fades `rgba(163,148,199,.88) → .15` over **1.1 s linear infinite**. Spoke delay is `−0.1375·(7−i)` s.
- Command-mode tint: `rgba(255,169,70,…)`. Instruct-mode tint: signal-500.

### 2.9 Pickers beside the pill (appear in `ready`) [C 10408/71070/82608/57676/33894/36808]

- Each picker is a **30 × 30** circle: fill #000, **1.5 px #30302f** border. Hover: #30302f fill, #5b5b59 border. Icons are 14 pt, white.
- Placement on the bottom edge:
  - The left group sits to the left of the pill, padding-right 2.
  - The right group sits to the right, padding 0 12 0 2.
  - Pickers within a group are 2 apart.
- On the side edges the groups stack above and below the pill.
- Show and hide animate opacity, scale (0↔1) and width with the 100 ms snap.

| Picker | Module | Rebuild |
|---|---|---|
| Language | `effectiveLanguagePicker` (left group) | drop: set in Settings |
| **Transform / polish wand** | `autoPolishPicker`. Expands to 54 wide with a caret tab 22 × 22; prompt code 10 pt Google Sans Code, weight 600. | keep if Transforms ship |
| **Scratchpad** | `scratchpadContainer` (right group) | keep as "Quick note": opens Notes with a blank note focused |
| Start meeting ("Take notes") | `startMeetingContainer` (right group) | drop from the bar: the Notetaker shortcut and the hub start meetings |
| Fetch links, Instruct chat | — | drop |

### 2.10 Tooltips on the bar [C 31201][C 92709][J]

| Property | Value |
|---|---|
| Style | black capsule: background `--shade-black`, 1 px #30302f border, **radius 34**, padding 6 14, Figtree **15/20 400**, white, nowrap, gap 4 |
| Keytip spans | bold white. Positive keytips use `--accent`. "Next step" text uses `--signal-500`. |
| Offset from the pill | 4. The cancel and finish buttons use 10. |
| Show delay | 50 ms. Lock 100 ms. |
| Fade | opacity 120 ms. Slide `transform 180ms ease`. |
| Positioner z-index | 900 |
| Hub tooltip (generic) | neutral-800 fill, neutral-200 text, radius 8, 12/20 600. `sm` variant 15/20, padding 6 12. Max width 350. Arrow 10. |

### 2.11 Transform ("Polish") progress and result pills [C 55907][C 98869][J `s_`]

- **Processing** (136 × 30):
  - A progress fill (`--vast-900`, opacity .5) grows from 0 to 100 % over **7 s** (rAF).
  - When the result arrives it eases to 100 % in **750 ms**.
  - The label is 12/20 600 in `--neutral-400`. The 16 pt spinner sits at the right.
  - Rotating status labels ("Drafting", "Tightening", …) cross-fade over **280 ms**, at stage boundaries of 2 s and 4 s.
- **Done** (152 × 30):
  - Sparkle icon 14 pt, then "Done." in white 12/20 400 and "See changes" in **`--signal-500` #ffbcf2**.
  - Hover: fill #4a4a4a. Clicking opens the diff (UI §6.3).
  - The cross-fade between the two layers takes 200 ms.
- **Rainbow label variant:**
  - 10/18 600 Google Sans Code in #dba0ff.
  - Or a gradient text (`#FFD5A4, #FFAB9A, #FFC1F4, #DBA0FF`, 200 % wide, `rainbow-gradient-wave` 3 s linear).

### 2.12 Notifications attached to the bar [C 79621][C 11102]

Cards rise from the bar inside `notificationLayer`. Examples: errors, "Flow can't paste right now. Text saved to clipboard", tips. Each card **morphs out of the pill**:

- The width, height and radius transition over **420 ms** with the spring easing.
- The background and border transition over 220 ms; the shadow and opacity over 300 ms.
- Transform stages:

| Stage | Transform |
|---|---|
| entering | `translateY(−1) scale(1.015)` |
| visible | `0 / 1` |
| exiting | `scale(1.015)` |
| collapsing | back to the resting look, opacity 0 |

- When the morph is not used, cards sit 32 pt above the bar: `translateY(−32)`, or ±X on the side edges.

| Variant | Geometry | Text |
|---|---|---|
| Container (base) | `--shade-black` fill, **radius 24**, padding 12, gap 12, **max 440 × 294**, shadow xs | title 15/20 **600** `--sand-50`; subtitle 15/20 400 `--vast-300`, pre-wrap |
| **mini** | row, gap 6, padding 12 16, **radius 20**, fit-content up to 440 | 15/20 400, single line, ellipsis. Clickable hover #464544, active #5b5b59. |
| **condensed** | padding 8 16, fill `--vast-950`, shadow lg; actions gap 8. Auto-dismiss progress bar **3 pt** at the bottom (`--lumen` on a `--foreground-tertiary` track, linear). | title 15/20 **550**, up to 2 lines |
| standard | padding 20, min-width 340; badge 22 tall, radius 6, `--dawn-500`; status icons: error #ee6a6a, alert #ffd467 | — |
| showcase / splash / card | min 380 / min 380 / 250 wide; thumbnail 152 or 108 square radius 16; splash image 136 tall radius 14 | marketing; drop |

Buttons in cards:

| Button | Style |
|---|---|
| Ghost | white 15/20 600 |
| Soft-dark | radius 8, padding 6 12, `--foreground-tertiary` fill, sand-50 text 15/24 600; hover #5b5b59 |
| Condensed action | radius 8, padding 6 10, `rgba(255,255,255,.08)` fill (hover .12, active .16), 15/20 400 |
| Close (×) | top-right, 16 from the edges |

Sounds: error → `notificationError`, alert → `notificationAlert`, success → `notificationSuccess`, at **volume 0.5** (UI §8). Auto-dismiss times vary per notification (3–15 s; see `behaviour.md`).

### 2.13 Small pills near the bar [C 31201][C 65693][C 78548][C 84794]

| Pill | Style |
|---|---|
| **Hotkey reminder** (`hotkey_reminder`) | 32 tall. Text 12/20 **550** in `--lumen` #ffffeb. Key chips: 10/18 550, `--lumen` fill, black text, height 16, padding 1 3, `box-shadow: −1.5px 1.5px 0 #646464`. Optional rotating glow ring (`conic-gradient` from transparent to `--lumen` 10 % to transparent 20 %, 3 s linear). Three 3 × 3 "more" dots at opacity .6. |
| "Voice-to-text disabled" (admin policy) | 12/20 550, padding 4 10, radius 22.5, warning icon `--warning-400`. Drop with orgs. |
| Undo / applied pills | 208 × 30 or fit-content, rainbow ring, label 12/20 white, "Undo" `--vast-600` → hover sand-50 |
| **Live streaming text** (hands-free, `streamAudio`) | panel **400 × 200** (min = max = 200 tall), 40 above the bar, padding 20, black, **radius 11**, 1 px #30302f border, white glow `0 3px 30px -6px rgba(255,255,255,.2), 0 0 20px rgba(255,255,255,.15)`. Text 16/24 (line-height 1.5) white, auto-scrolls; fade-in .2 s. |

### 2.14 Drag to move (feature flag `CanDragFlowBar`) [C 29][M]

Dragging the bar dims the screen and shows drop zones:

| Element | Style |
|---|---|
| Drag overlay | `--neutral-900` at opacity .6. Fade in 120 ms, out 200 ms. |
| Drop zones | `rgba(255,255,255,.4)` (hovered .8 and scale 1.08, 150 ms), radius 999 |
| Bottom drop zone | **124 × 86**, 10 above the work-area bottom, centred |
| Left / right drop zones | **86 × 124**, 10 in from the edge, vertically centred |
| Ghost | **30 × 30** black circle, 1 px #30302f border, shadow `0 2px 12px rgba(0,0,0,.4)`, logo 16 wide. Returns to the pill over **300 ms** `cubic-bezier(0.2,0.9,0.3,1)` when dropped outside a zone. |

- Dropping saves `statusDockEdge` (`bottom` | `left` | `right`).
- A one-time hint modal reads "You can now move the Flow Bar!".

### 2.15 Visibility rules [M][J]

- The idle bar is **hidden until onboarding completes**. The default `clickableBubbleSnoozeUntil` is now + 1 year; finishing onboarding sets it to now.
- **"Hide for 1 hour"** (bar menu) snoozes the resting bar. `hideFlowBarPermanently` hides it until it is turned back on. Active states (listening, processing, error, notifications) **always show**.
- The resting bar appears or disappears by fading (`hidden` state = opacity 0, 100 ms).
- **Blackout overlay** (onboarding emphasis):
  - Dims the rest of the screen with `--neutral-900`.
  - Leaves a **180 pt-radius hole** centred 50 pt in from the bar's edge.
  - Fades in .3 s; fades out at 5.7 s; clicks pass through after 6 s.

### 2.16 Reference images

| File | Note |
|---|---|
| `scratchpad/flow/assets/images/flow-bar-listening.png` (205×60) | Illustration used on the onboarding "try it" pages (`tiy_gmail_*`). Shows an older hands-free style: grey ✕ circle, white waveform, red ■ stop. **The live bar uses the 18 pt cancel/check buttons of UI §2.5.** |
| `scratchpad/flow/assets/onboarding/waveform-mp4-3s.png` | Frame of the listening pill (UI §2.6) |

---

## 3. Hub (main window)

### 3.1 Window [M]

| Option | Value |
|---|---|
| Title | "Flow Hub" |
| Default size | **1350 × 850**, clamped to (primary workArea − 20) on each axis; `center: true` |
| Minimum size | **1140 × 750** |
| Frame | macOS: `frame:false`, `titleBarStyle:"hidden"`, **traffic lights at (16, 19)**, `transparent:true`, `backgroundColor:#00000000`, `hasShadow:true` |
| Other | resizable, movable, maximizable, fullscreenable; created hidden, then shown |

### 3.2 Layout [C 25412][C 32437][C 3366][C 81370]

```
window (100vw × 100vh, background --background-tertiary #f5f4f0)
├ header bar (≈ 52–60 tall, drag region)
│   traffic lights · sidebar toggle (32 × 32, radius 6, hover --neutral-200) · back/forward arrows (36 × 36)
└ container (row)
    ├ sidebar (width 216 · collapsed 60 · full-screen 256; padding 12; gap 10; width transition 150 ms spring)
    └ page card (flex 1; height calc(100vh − 60); radius 24 24 16 16; 1 px --border; background --background;
                margin 0 8 8 0; padding 40 40 0)
          title row (max-width 1046, margin-bottom 24; page title 24/32 600)
          content (max-width 1046, centred, gap 32, bottom padding 48)
```

**Sidebar** [C 3366]:

- **Flow section** (top): logo 25 tall, padding 4 5, margin-bottom 16.
- **Nav item:**
  - Padding 8, radius 6, gap 8, text 15/20 **550**, icon 20 × 20, minimum width 192.
  - Background `--background-tertiary`; hover or active `--neutral-200` (#eeebe3); the background-colour transition uses the spring.
- Items are 4 apart. A divider (1 pt `--border`) sits above the bottom group.
- **Collapsed hover hint:** `--neutral-800` fill, white 12/20 text, radius 8, padding 6 8. It scales .9 → 1 over 150 ms spring and sits 4 pt to the right of the item.
- **Nav anchors**, in code order: Dictation (home), My Voice, Dictionary, Notes, Settings, Referral, Team, Snippets, Style, Transforms, Insights, Notetaker, Tasks, Extensions.
- **Rebuild keeps:** Home/History, Notetaker (meetings library), Tasks, Dictionary, Snippets, Style, Transforms (optional), Notes/Scratchpad (optional), Settings.

### 3.3 Components

| Component | Spec |
|---|---|
| **Button** [C 82099] | Base: padding 8 16, **radius 8**, gap 8, 15/20 **550**; width transition 200 ms snap; focus ring 2 pt `--foreground`, offset 2; disabled opacity .5 |
| Button sizes | xs: height 32, padding 0 12, 12/20 550, gap 6. sm: padding 6 12. md: 8 16. lg: 10 24. `rounded`: radius 9999. Spinner 14 pt conic ring, 1 s. |
| Button variants | **primary**: `--primary` fill (#1a1a1a), `--primary-foreground` text; hover mixes 10 % background in. **secondary**: `--background-secondary`, 600 weight; hover mixes 6 % foreground in. **outline**: background fill, 1 pt `--border`; hover tertiary. **ghost**: transparent; hover `rgba(197,192,179,.2)`. **destructive**: `--destructive-500` fill, white text; hover `-400`. **dawn**: dawn-300 fill, 1 pt dawn-500 border; hover dawn-400. **lumen**: lumen-400. **embossed**: glow-300, radius 6, hard shadow `−0.8px .8px 0 glow-500`, presses in on :active. **link**: padding 4, underline on hover. |
| **IconButton** [C 70809] | sm 24 (radius 6) · md 28 (radius 8) · lg 32 (radius 8) · xl 56. Variants: `circle`; `toolbar` (28 × 28, radius 6, `--neutral-600` icon, hover tertiary fill); `frosted` (24, `rgba(255,255,255,.15)` + 8 pt blur); `primary` (32 × 32, radius 20, black). Hover opacity .8; disabled .3. |
| **Switch** [C 86115] | regular **42 × 25**, thumb 21, travel 17. small 24 × 16, thumb 12, travel 8. Off track `--vast-700` #5b5b59; on track `--primary` (regular) or `--dawn-600` (small/purple); thumb white (on: `--background`); thumb slide 150 ms spring; focus 2 pt `--vast-300` |
| **Text input** [C 1013] | height 36, width 200, padding 10 12, radius 8, `--shade-white` fill, outline 1 pt `--neutral-300` (hover, focus or active: 2 pt `--neutral-500`), text 16/24, placeholder 15/20 `--foreground-tertiary` |
| Settings inline input [C 31211] | 1 pt `--border`, radius 6, padding 4 8, min-width 160, 15/20; focus border `--neutral-500` |
| **Modal** [C 93976] | overlay `rgba(0,0,0,.55)`, z 700, fade 150 ms spring. Content: `--background`, 1 pt `--border`, **radius 12**, shadow xl, gap 32, min-width 200; enters from scale .9 / opacity 0. |
| Blur dialog overlay [C 27941] | vast-950 at 30 % + `backdrop-filter: blur(8px)`, padding 24, z 800 |
| **Toast** (hub) [C 11102] | fixed bottom-right (right 16), **300 wide**, padding 8 12, gap 8, radius 6, 1 pt `--neutral-600` border, `--neutral-800` fill; message 15/20 white; with title: title 15/20 600, message 12/20 `--vast-300`. Enter `translateY(−16)` 150 ms toast easing; exit `translateY(−32)` + fade 800 ms. Icon 20 pt. Action 15/20 550, padding 3 8, radius 4. |
| **Menu** [C 15245] | min-width 160, padding 6, **radius 10**, `--background`, 1 pt `--border`, shadow lg, gap 2. Items padding 8 10, radius 6, 15/20 400 `--neutral-800`; highlight `--background-tertiary`; destructive `--destructive-500` (hover 10 % tint). Divider 1 pt, margin 4 6. Enter/exit: 4 pt slide + fade, 80 ms ease-out. |
| **Key pill** (shortcut display) [C 73115] | height **22**, padding 2 8, radius 4, 1 pt `--border`, white fill, hard drop `0 2px 0 0 #d3ced6`, Figtree 14, ink `--vast-900`; separator " + " with 6 pt margins in `--neutral-600`. Dark: fill vast-800, edge vast-700, drop bg-tertiary. Onboarding variant: sand-50 fill, 1 pt vast-300, shadow md, inherits font size. |
| Small key chips (menus, bar) [C 11075] | height 18, padding 0 4, radius 4, 10 pt 550, lowercase, `--vast-900` fill, `--vast-500` text |

### 3.4 Dark mode

- Driven by the `theme` preference and `data-theme` (UI §1.2).
- The hub supports it. The Flow Bar ignores it. Onboarding forces light.

---

## 4. Settings (modal inside the hub)

### 4.1 Frame [C 58560]

| Part | Spec |
|---|---|
| Modal | **960 × 640**, `--shade-white` fill, **radius 12**, shadow xl |
| Sidebar | padding 8, column; content width **192**; right border 1 pt `--border`; radius 12 0 0 12; `--background-tertiary` fill |
| Section title | uppercase 12/20 600, tracking .075em, `--neutral-500`, padding 8 |
| Items | min-height **36**, padding 8, gap 8, radius **8**, icon 20 × 20, label 15/20 **550**; hover or active `--neutral-200` |
| Footer row | version text 12/20 `--neutral-400`, padding 6 8; update button 28 × 28, radius 4. Error icon `--destructive-500`. |

Sidebar pages in the original:

- There are two section labels: "SETTINGS" and "Account".
- The page labels are General, System, Vibe coding, Experimental, Account, Team, Organization, Plans and Billing, Data and Privacy, Connectors, MCP, Notetaker, Extensions, Testing and Internal.
- Which page sits under which label, and in what order, was not resolved from the CSS [U].

The rebuild keeps **General, System, Notetaker, Vibe coding (optional), Experimental (optional), Models (new), Data and Privacy (local only)**. That list is a recommendation; the final list is a product decision.

### 4.2 Page layout [C 31211]

| Part | Spec |
|---|---|
| Page | padding **48**, gap 36; content gap 24, scrolls without a visible scrollbar |
| Header | gap 12. **Title EB Garamond 28/28**, tracking −0.04em. Description 15/20 `--neutral-600`. |
| Section | gap 16; title 15/20 **600** |
| **Card** | padding **20**, gap 20, **radius 12**, `--background-tertiary` fill; card heading 12/20 600 `--vast-900` |
| Row (`item`) | space-between, centred; margin −8 −12 with padding 8 12, so the hover area bleeds; radius 8 |
| Row text | label 15/20 **550** `--foreground`; description 15/20 400 `--neutral-600`, gap 6 |
| Controls column | width **164** (account rows 220); margin-left 12; right-aligned |
| Divider | 1 pt `--border` |
| Highlight | `--dawn-100` background when deep-linked to a setting; coach-mark nudge 0.8 s × 3 |

### 4.3 Shortcut rows

- Shortcuts are shown as key pills (UI §3.3).
- The General row hint reads "Hold [fn] and speak."
- The shortcut editor dialog lists each action (Push to talk, Hands-free mode, Command Mode, Paste last transcript, Cancel, …) with key pills, "Add another" and "Reset to default". Layout is [U]: built from the shared row and card styles.

---

## 5. Onboarding (inside the hub window, forced light)

### 5.1 Frame [C 70196][C 32437]

| Part | Spec |
|---|---|
| Background | light: `--sand-600` #eeebe3 with `--vast-950` text. Dark variant (some steps): `--vast-950` with white text. |
| Content | padding **40 108**; inner content gap **40**, top margin 32, fade-in .2 s |
| Header group | min-height 112, gap 16; **header 32/40 600**, centred; subheading **18/28 400**, max-width **520** |
| Main | max-width **560** |
| Footer | max-width 500, gap 24, pinned to the bottom; buttons up to **300** wide |
| Title bar | drag region with progress tracker: step labels uppercase 12/20 600 tracking .075em, `--neutral-400` (active: `--foreground`); arrows 16 pt; progress bar **2 pt** `--dawn-700` on `--neutral-200` |
| Back / Skip | top-left / top-right |
| Serif hero lines | some steps use EB Garamond 36–72 with an italic accent word in `--dawn-700` #a26ec1 |

### 5.2 Step media [R hashed-asset ↔ `Resources/assets` md5 map][J]

| Step (i18n prefix) | Media (`Resources/assets/…`) |
|---|---|
| Sign-in carousel (`login_*`) | `videos/login_videos/stop_typing_start_doing.webm`, `works_wherever_you_do.webm`, `notetaker_meetings.webm` (1552×1604, 5–14 s) |
| Product intent (`product_intent_*`) | `illustrations/product_intent_polaroid_{dictation,notetaker,frame}.svg` |
| About yourself (`about_yourself_*`) | `images/tell_us_aboutyourself.png`, `illustrations/underline.svg` |
| Where you spend time typing (`spend_time_typing_*`) | `illustrations/spend_time_typing.svg` |
| Speed comparison (`speed_comparison_*`) | `illustrations/keyboard-rollerskate.gif` (680×400), `illustrations/curved-arrow.svg` |
| Microphone test (`microphone_test_*`) | `illustrations/voice-dictator.svg`; mic picker images `images/{headphones,gooseneckMic,podcastMic,headsetWithMic,bluetoothEarbuds}.png` |
| Permissions | animated mock of System Settings (UI §5.3); `images/privacy.svg` |
| Try it yourself (`tiy_*`) | `videos/onboarding_gifs/ptt.gif`, `popo.gif` (1600×1000), `speak.gif`, `whisper.gif` (1600×1200); `images/flow-bar-listening.png`; `videos/login_videos/Mac/{ai_auto_edit,works_in_any_app,many_languages}.webm` (1416×936) |
| Personalize (`personalize_*`) | `illustrations/girl_mirror.svg` |
| Social proof / speedy (`social_proof_*`) | `illustrations/speedyOnboarding.png` |
| Notetaker steps (`how_do_you_record_*`, `what_kinds_of_meetings_*`, `connect_calendar_*`) | `illustrations/how_do_you_record.svg`, `what_would_make_meetings_better.svg`, `what_do_you_do_notetaker.svg`, `connect_calendar.svg`. Keep. |
| Team / referral / trial steps | `teamInvite.svg`, `create-team.svg`, `user_group.svg`, `juggling_mails.png`. **Drop.** |

Illustration style: flat cartoon with thick black outlines and the brand palette (coral, amber, pink, deep green). Example: `scratchpad/flow/assets/onboarding/popo-frame40.png`. The rebuild must use **its own artwork**; these files are reference only.

### 5.3 Permission illustration [C 67666]

An HTML/CSS mock of macOS System Settings is animated to show the user what to click.

| Part | Spec |
|---|---|
| Stage | **900 × 540** (drag variant 900 × 680), `--sand-600` fill, system font |
| Window | 780 × 480, radius 26, `#f4f3f1`, shadow `0 26px 70px rgba(0,0,0,.24)` |
| Sidebar | 236 wide; rows 36 tall, radius 11; active row `#a550a7`; tiles 23 pt |
| Loop length | TCC prompt **7.2 s**, auth **8 s**, drag-in **7 s** |

### 5.4 Accessibility drop panel (window `accessibility_drop`) [M][C 22934]

| Part | Spec |
|---|---|
| Size | **560 × 144** |
| Window | `type:"panel"`, transparent, non-focusable, `acceptFirstMouse`, floating level, all spaces |
| Position | centred under the System Settings window (12 below it; shifted 215 right when that window is wider than 430, to clear its sidebar), clamped to the work area. Otherwise bottom-centre, 24 above the bottom. |
| Panel | padding 8, 1 pt `--border`, **radius 16**, background `--card` mixed 3.5 % with foreground, shadow `0 4px 8px rgba(26,26,26,.25)` |
| App row (drag source) | min-height 40, padding 4 8, 1 pt border, radius 12, cursor grab; icon 24, radius 6 |
| Arrow | system blue **#007aff** with a drop shadow; `guidance-arrow-bounce` 1.6 s ease-in-out, infinite (off under reduced motion; paused while the window is blurred) |
| Dismiss | 32 × 32 circle, tertiary fill |

### 5.5 Native permission guide (macOS 26+) [R]

`FlowPermissionGuide.app` (`com.electron.wispr-flow.permission-guide`, LSMinimumSystemVersion 26.0):

- Uses the Permiso library: `OverlayWindowController`, `PassiveOverlayPanel`, `AppDragSourceView`, an arrow view, and a `SettingsWindowSnapshot`.
- Opens `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` (also `Privacy_ScreenCapture`, `Privacy_AppBundles`).
- Geometry constants were not recovered [U].
- For the rebuild, a single native panel modelled on UI §5.4 covers both OS versions.

---

## 6. Other windows

### 6.1 Context-menu window (`contextMenu`) [M][C 15245]

| Property | Value |
|---|---|
| Size | the whole work area of the cursor's display |
| Window | transparent, `type:"panel"`, non-focusable, level `"screen-saver"`, ignores mouse events until a menu is open |
| Content | the Flow Bar's right-click menu, drawn with the Menu style of UI §3.3: Paste last transcript, Microphone ▸, Languages ▸, Formatting options, Hide for 1 hour, Settings, Transcript history, … (wording in `strings.md`) |
| Rebuild | use a native `NSMenu` popped up from the panel |

### 6.2 Scratchpad (`scratchpad`) [M][C 22383]

| Property | Value |
|---|---|
| Default size | **500 × 420** |
| Minimum size | **300 × 200** |
| Expanded size | **920 × 660** |
| Window | transparent, frameless, `type:"panel"` on macOS, `visualEffectState:"active"`, shadow, resizable, all spaces; opens near the cursor |
| Shell | radius **12**, overflow hidden |
| Top bar | `--background-tertiary`, drag region, padding 8 12 8 0; logo 16 pt in `--neutral-600` |
| Sidebar rail | 48 wide; opens to 48 + clamp(120, 25 % of the container, 200) over 150 ms |
| Content | `--background`, radius 12, margin 0 8 8 0. Tabs, notes list and editor are Figtree. |

### 6.3 Diff view ("See changes" after a Transform or auto-cleanup) [C 40369][C 6212]

**Dark variant** (on black cards):

| Change | Style |
|---|---|
| Added | background **#29504b**, text **#d1f2ee**, radius 2, padding 2 4 |
| Removed | background **#222**, text **#929292**, strikethrough |

**Light variant:**

| Change | Style |
|---|---|
| Added | background #d1f2ee, text `--fathom` #034f46, weight 500 |
| Removed | `rgba(235,233,236,.2)` background, `--neutral-400` text, strikethrough |

Body: Manrope 14, line-height 2, pre-wrap, max height 300, scrolls.

### 6.4 Out of scope

| Window | Spec | Rebuild |
|---|---|---|
| `overlay` | extension iframes in floating, full-screen or corner-anchored panels: floating default is 14 from the bottom-right; level floating or screen-saver | drop |
| `feature_tour` | full-screen transparent window plus a black dim window at opacity .45 | drop |
| `meeting_ax_inspector` | 560 × 760, minimum 360 × 400, traffic lights (12, 16). An internal tool for inspecting meeting-app accessibility trees, opened only for staff accounts. | drop |

The `meeting_recorder` window is in scope: see UI §10.1.

---

## 7. Menu bar item [M][R]

| Property | Value |
|---|---|
| Image | `assets/tray/TrayIconMac@2x.png`, **32 × 32 px**, loaded as a **template image** (16 × 16 pt). Bilevel alpha. |
| Glyph | five rounded vertical bars, each 2 pt wide: the outer pair full height (≈ 15 pt), the inner pair short (≈ 6.5 pt, bottom-aligned), the centre bar medium (≈ 10.5 pt). The app icon's "W" in silhouette. |
| Tooltip | "Wispr Flow" |
| Preferred position | on first run the app writes `NSStatusItem Preferred Position Item-0 = 40` to its defaults |
| Menu | a native menu (wording in `strings.md`). Its item icons `MenuEyeTemplate.png` / `MenuEyeOffTemplate.png` (16 px, @2x 32 px, eye / eye-slash) belong to the "Show/Hide next meeting in menu bar" item. Keep with the Notetaker. |
| Title (next meeting) | see UI §10.6 |

References: `scratchpad/flow/assets/tray/*` and `tray-icon-preview.png` (alpha rendered 8×).

---

## 8. Sounds [J][R]

- Sounds play only when `enableSounds` is on (default **on**).
- The set comes from `selectedSoundFolder` (default `null` → **"default"**). The other sets (`v1`…`v12`, `t1`, `notifv2`) are experiment variants. The rebuild ships one set.
- Dictation sounds play at **volume 1.0** through the hub renderer. Notification sounds play at **0.5** in the bar.

| Event | File (`Resources/assets/sounds/`) | Format | Duration |
|---|---|---|---|
| Dictation start | `dictation-start.wav` | 2 ch, 44.1 kHz, 16-bit | **0.180 s** |
| Dictation stop | `dictation-stop.wav` | 2 ch, 44.1 kHz, 16-bit | **0.219 s** |
| Hands-free lock (double-tap engaged) | `popo-lock.wav` | 2 ch, 48 kHz, 24-bit | 0.165 s |
| Paste | `paste.wav` | 1 ch, 48 kHz, 16-bit | 0.619 s |
| Achievement | `achievement.wav` | 2 ch, 44.1 kHz, 24-bit | 1.445 s |
| Notification success | `notifv1/success.wav` | 2 ch, 48 kHz | 0.978 s |
| Notification error | `notifv1/error.wav` | 2 ch, 48 kHz | 0.468 s |
| Notification alert | `notifv1/alert.wav` | 2 ch, 48 kHz | 0.978 s |

Notes:

- `Notification.wav` (unused by the default set) and `t1/dictation-start.wav` are alternates.
- The start sound records whether media was playing before it, to support the pause-media feature (`behaviour.md`).
- These files are the original product's audio. The rebuild needs its **own** sounds with similar character: very short (≈ 0.2 s) soft clicks for start and stop. Copies for listening are in `scratchpad/flow/assets/sounds/`.

---

## 9. Icons, illustrations, animations

### 9.1 Icon sets

| Set | Contents |
|---|---|
| **UI glyphs in code** [J] | A Lucide-style set compiled into the bundle (`{name, size: 24, node: [...]}`: "x", "check", "chevron-down", "zap", …) drawn with a 2 stroke at 24, often re-stroked (e.g. 12 pt with stroke 3 on the bar). The rebuild can use SF Symbols equivalents (`xmark`, `checkmark`, `mic.fill`, `chevron.down`, `sparkles`, `globe`, `wand.and.stars`). |
| **Microphone glyph** (ready state) [J] | custom 12 × 16 path: a filled capsule with a stand |
| **Asset icons** `Resources/assets/icons/*.svg` (84) [R] | account, achievement, alert, archive, arrows, article, attach, bell, check, check-success, chevrons, close, code-2, dataAndPrivacy, defaults, dictionary_file, double-check, draft, email-open, error, external-link, filter, gift, help-*, inbox, info, insights, keyboard, labs, language, language-search, link, loud-speaker, medical, messages, mic-outline, notes, numbers, party-popper, phone, plansAndBilling, plus, polish_wand, qr-code, referral, refresh, restart, search, send, settings, snippet, sparkle, speaker-on/off, style2, support, system, team, toast-error, toast-progress, toast-success, tooltip-alert, triple-dot, upload, wand-stars, x. Rendered sheet: `scratchpad/flow/assets/icons-contact-sheet.png`; some stroke-only icons render blank with the converter. |
| **App logos** (`appLogos/`, `transparentLogos/`, `logos/`) | third-party brand logos (Slack, Gmail, Cursor, AI chat apps, …) shown in onboarding and Style. **Do not reuse.** Show the running app's own icon (`NSWorkspace.icon(forFile:)`) instead. |

### 9.2 Lottie [R]

| File | Canvas | Frame rate | Length | Colours | Use |
|---|---|---|---|---|---|
| `pulsing_circle.json` | 1080 × 1080 | 29.97 fps | 85 frames (2.84 s) | single colour #ffa946, 5 layers | attention pulse [U] |
| `celebration.json` | 400 × 400 | 30 fps | 121 frames (4.03 s) | confetti in #3497fd, #7fd04f, #bd75ee, #ee75ca, #f94eff, #fb174c, #fbc817, #fe8c01, #fec456, #ff4242 | milestone celebration |

### 9.3 CSS "pulsar" coach-mark [C 22113]

| Part | Spec |
|---|---|
| Core | default `#7232A6` |
| Halo | default `#B282FF` |
| Size large | core 16, inner 48, outer 54 |
| Size medium | core 10, inner 28, outer 31 |
| Size small | core 6, inner 17, outer 20 |
| Animation | the outer ring scales 1 → 1.63 and fades, 2 s ease-out (0–35 % hidden, 36 % at .8); the inner ring breathes 1 → 1.125 → 1, 2 s |

### 9.4 Reference copies in the scratchpad (not in the repo)

`/private/tmp/…/scratchpad/flow/assets/`:

| Path | Contents |
|---|---|
| `tray/` | 6 PNGs |
| `tray-icon-preview.png`, `menu-eye-preview.png` | renders |
| `sounds/` | default set + `notifv1/` |
| `lottie/` | 2 JSON |
| `icons-svg/`, `icons-png/` (96 px), `icons-contact-sheet.png` | icons |
| `images/` | `app-icon-256.png`, `app.iconset/`, `flowLogo.png`, `flow-bar-listening.png`, `privacy.svg`, `keyboard.svg` |
| `illustrations/` | onboarding SVG/PNG |
| `onboarding/` | the 4 onboarding GIFs, a frame of each, `waveform-mp4-3s.png` |
| `meetings/` | Notetaker reference images (UI §10.7) |

---

## 10. Notetaker (meetings)

The Notetaker records a meeting, shows a live transcript beside the user's own notes, then produces a summary and tasks. Its UI spans:

- the **notepad** window (`meeting_recorder`)
- a **meeting state of the Flow Bar**, plus meeting cards on the bar
- **hub pages**: library, meeting detail, My Tasks, folders, calendar widgets
- the **menu-bar title** that counts down to the next meeting

Shared tokens and components are those of UI §1 and §3.3. The readable CSS is in `scratchpad/flow/css/meeting_recorder.css`, plus the `hub.css` modules cited below.

### 10.1 Notepad window (`meeting_recorder`) [M][C 87448][C 24073]

**Window options:**

| Option | Value |
|---|---|
| Title | "Meeting Recorder" |
| Default bounds | **docked to the right of the work area**: width = min(W, max(**500**, round(**0.3** × W))), full work-area height, x = right edge − width (W = work-area width) [M `v()`] |
| Minimum size | **500 × 600** |
| Frame (macOS) | `frame:false`, `titleBarStyle:"hidden"`, **traffic lights at (16, 20)**, `transparent:true`, `backgroundColor:#00000000`, `hasShadow:true` |
| Behaviour | resizable, movable, minimizable, maximizable, fullscreenable, closable, focusable; spellcheck on; background throttling off. Shown on all Spaces when docked. If it ends up off-screen it is moved back flush to the top-right of the work area. |
| Root | `--background` fill, **radius 12** on macOS, overflow hidden |
| Content protection | on while recording when "hide in screen share" is set, the same as the bar |
| Remote-config default | `{default_width:720, default_height:760, min_width:500, min_height:600}`. A config object; the docked bounds above are what the code uses to open the window [U]. |

**Split-screen join** ("Split screen" header button, and joining from a calendar card) [M]:

1. The **notepad width** is `clamp(current width, 500, round(0.5 × W))`.
2. The **meeting app** is chosen as the app currently holding the microphone (ranked by platform). If none holds it, the last frontmost app is used.
3. The native helper places the meeting app in the **left** part (W − notepad − 1 wide, full height). The notepad docks on the **right**.
4. This needs Accessibility permission; without it the app prompts for it. If the meeting app cannot be anchored, only the notepad docks.

**Layout, top to bottom** [C 24073][C 54408][C 24323][C 57526]:

| Part | Spec |
|---|---|
| Window header | **52 tall**, absolute, padding 0 12, drag region; traffic-light spacer 52 × 12 (margin 0 16 0 4); right-side actions gap 4 |
| Home ("All notes") button | 32 × 32, radius 8 |
| Calendar-connect pill (warm) | `--orange-500` 8 % over background, inset 1 pt ring at 20 % |
| Body | padding-top 52; width `calc(100% − 40px)` |
| **Meeting title** | **EB Garamond 36**, line-height 1.25, tracking −0.04em, padding 8 12, top margin 12 |
| Attendee strip | padding 0 12 12; facepile (below) |
| **Tab bar** (`pillRowHeader`, padding 0 12) | tabs **15/20 600**, padding 12; `--neutral-500` (hover `--neutral-600`, selected `--foreground`); 1 pt `--border` bottom line; **2 pt `--neutral-800` underline** slides between tabs over 150 ms spring. Tabs: **Notes, Transcript, Summary, Tasks, Docs**, plus **Brief** (pre-read). |
| Transcript tab live indicator | green mini waveform (`--accent: --green-500`, bar width 2.5, height 16 scaled to 0.792 / 0.9) followed by a word count in `--vast-400` |
| Tab content | fades in over **180 ms**; padding 24 12; scrollbar 8 wide, thumb `--neutral-200` radius 4 |
| Footer fade | 150 tall gradient to `--background` over the bottom |

**Notes editor** (rich text, shared with Scratchpad) [C 88707]:

| Element | Spec |
|---|---|
| Body | **15 / 28, weight 550** (a "regular" option uses 400), padding 12 16, caret colour **`--glow-300` #ffa946** |
| Placeholder | `--neutral-400` |
| Paragraph hover | `--neutral-100` fill, radius 6, bleeding 12 to each side |
| Headings h1–h6 | all **15 / 28 weight 700** (no size change) |
| Lists | 24 indent |
| Checklists | 16 × 16 box, 1.5 pt `--neutral-300` border, radius 4 |
| Quote | 4 pt `--border` left rule, padding-left 16, `--neutral-600` |
| Link | `--chord-600` #7232a6 |
| Inline code | `--neutral-200` fill, `--orange-700` text, menlo 94 %, radius 3 |

**Live transcript** [C 85550]:

| Element | Spec |
|---|---|
| List | padding-left 16; 16 between speaker groups; 6 between a speaker label and its bubbles; consecutive bubbles overlap by −4 |
| **Speaker label** | 15 pt **550**. Colour comes from a **15-colour palette** indexed by speaker ordinal ((n − 1) mod 15), or by a hash of the name ×31: `#E89F4D, #6B3FAB, #3F9970, #3D5FE0, #C0392B, #1ABC9C, #D68A2D, #8E44AD, #2980B9, #27AE60, #E67E22, #16A085, #9B59B6, #34495E, #D35400` [J]. A caret appears on hover (120 ms) to rename. |
| **Bubble** | `--background-tertiary` fill, padding 8 12, **radius 12**, 15 pt **500**, line-height 1.5. Grouped bubbles square their inner corners to **4**: first bottom-start, middle both start corners, last top-start. |
| Interim (not yet final) text | bubble opacity .5, or inline `--neutral-500` |
| Translated line | `--success-700` mixed 85 % with foreground |
| Markers (pause, resume) | italic `--neutral-500`, or a dashed 1 pt `--border` divider with a centred chip |
| Search | match `--yellow-200`, current match `--orange-300` with a 1 pt `--orange-500` ring |
| Row actions | appear on hover (120 ms) at the right: report, edit. "Edited" link 12/20. Editor box up to 504 wide, focus ring 2 pt `--dawn-500`. |
| Jump-to-bottom button | 16 from the right, above the footer |

**Floating footer** (recording controls and the "Ask anything" composer) [C 75192][C 19146][C 92536][C 92724]:

| Element | Spec |
|---|---|
| Footer | anchored 8 below the tab bar, content aligned bottom, padding-bottom 16, z 3 |
| Composer capsule | `--background`, **radius 32**, padding 10, gap 8. Elevated: `0 0 0 1px var(--neutral-200), 0 4px 16px rgba(0,0,0,.1), 0 1px 4px rgba(0,0,0,.06)`, 200 ms. |
| **Record toggle pill** (Start / Stop / Resume) | min-width 48, padding 15, radius 9999, 1 pt `--border`, `--shade-white` fill, Figtree 15 **600** `--neutral-800`, gap 8, all transitions 100 ms linear. Hover: `--recording-background` (green-50) with a `--recording-foreground` (green-600) border. |
| Record toggle icons and label | record icon in green-600; **stop square 13 × 13, radius 2, green-600**; label max 96 wide (finishing label up to 144, ellipsis). Collapses to a circle with the label at width 0. |
| **Elapsed timer** | 15/20 **#18a558**, tabular numerals, inside a 70 × 30 capsule (radius 60; hover `rgba(0,0,0,.06)`) |
| Timer waveform | **41.4 × 14.1**, bars **2.35** wide, radius 36.7, **#3cbb77**, `scaleY(min(1.9, waveMult × audioScale))` |
| Mic level meter (setup and mic check) [C 91433] | segments 12 tall, radius 2, gap 2; inactive `--sand-600`, active `--success-500`, 80 ms |

**Summary tab** [C 73284][C 48602][C 48720][C 22722][C 59526]:

| Element | Spec |
|---|---|
| Panel | padding-top 24; the same editor typography as Notes (body 15/28) |
| Reveal | a **mask sweep**: the editor shows from top to bottom behind a 32 pt soft edge (`--sweep-y`), then settles |
| Loading | skeleton bars with a shimmer |
| **Generation-stage card** | min-height 48, padding 10 14, **radius 12**, `--background-tertiary`. Done: `--green-50` with `--green-800` text and icon. Error: `--orange-50` with `--orange-700`. Title 15/20 550 with a 6 s shimmer (off under reduced motion). Inline variant: padding 12, radius 8, 12/20. |
| Pipeline status dot | 10 pt. Uploading, transcribing and summarising: `--blue-500`. Complete: `--green-500`. Failed: `--red-500`. Label 15/20 `--neutral-800`. |

**Tasks tab and My Tasks page** [C 38116][C 34141]:

| Element | Spec |
|---|---|
| Row | padding 8 10, **radius 8**, gap 12, items 2 apart. Hover `--sand-200`; selected `--dawn-100`; keyboard cursor `--dawn-200`; done rows at opacity .35. |
| Title | 16 / 24 editable; placeholder `--neutral-400` |
| Checkbox | 16 × 16, 1.5 pt `--border`, radius 4, white. In progress: `--dawn-700` border with a 6 pt dot. Done: `--dawn-700` fill with a white 12 pt check, stroke 3. Focus ring 2 pt `--dawn-400`. |
| Meta | right-aligned, gap 8 (due date, source note, assignee) |

**Speaker-naming modal** [C 65560]:

| Element | Spec |
|---|---|
| Modal | up to **600** wide × min(680, 85vh) tall, radius 12, white, shadow xl, backdrop `rgba(0,0,0,.55)` |
| Header | padding 32 32 0; title **EB Garamond 28/28**; subtitle 15/20 `--neutral-500` |
| Speaker rows | 24 apart. Header: a 9 pt colour dot and a label in uppercase 12/20 550, tracking .04em. Sample quotes: 15/20 `--neutral-500` with a 2 pt `--border` left rule. |
| Footer | padding 16 32, top border, buttons right-aligned |

**Other notepad pieces:**

- **Facepiles** [C 66313][C 26753]:
  - Meeting avatar tile: 20 / 22 / 24 / 32 / 36 square, radius 6–8. It packs 1–4 faces in a grid with 1 pt gaps; faces are 10 pt type when small.
  - Attendee row: overlapping circles (−30 % overlap) cut with a radial mask; overflow chip `--sand-300`.
- **First-recording consent card** [C 44688]:
  - Radius 12, padding 16 24 16 16, split fill `--dawn-400` / `--dawn-200`; collapsed `--dawn-500`.
  - Media tile 243:124, radius 8. Progress ring 16 pt, stroke 2.

### 10.2 Flow Bar meeting state [C 31201][C 60666][J]

While a meeting records, the bar shows **meeting chrome**. It applies whenever the meeting phase is not idle or compressing, unless a dictation is active, in which case the dictation state wins.

| Property | Value |
|---|---|
| Pill (bottom edge) | `--shade-black` fill, **2 pt `--green-500` #10b981 border**, radius 22.5, **fit-content × 30**, padding 0 5, row gap **12**, cursor pointer |
| Pill (left / right edge) | 30 × fit-content, padding 5 0, column gap 12 |
| Hover | `--vast-900` #30302f fill, `--vast-700` #5b5b59 border |
| Content, in order | **[5-bar waveform] [stop button]**. Clicking the waveform area opens the notepad. Hovering it can show a live preview. |
| Size transitions | width / height **160 ms** snap curve; border colour and width 130 ms; content opacity 60 ms; none under reduced motion |
| **Stop button** | 19 × 19 circle, `--sand-950` #4d4a42, with a **7.5 × 7.5 square, radius 2**, in `--accent` (white in the bar window). Tooltip "Stop Notetaker". Keyboard focusable. |
| **Meeting waveform** | 5 bars, box 24 × 24 (bottom padding 0 1.5 0 4.5). Bar height weights **0.25, 0.625, 1, 0.625, 0.25** (linear bulge, coefficient 18). Bar length = 6 × audioScale × weight × waveMult, capped at **18**, drawn as a rounded clip of an 18-tall bar. Colour `--accent` (white). |
| Level and motion | audio gain **2** (dictation uses 5). `waveMult` comes from a per-bar 1 s ticker over keyframes (0 → 1, .2 → 1.2, .4 → 1.5, .8 → 1.1, .9 → 1.3, 1 → 1) with smoothstep easing. Phase offsets 0, .1, .2, −.2, −.1 s. **Collapsed** (silence) bars are 2 long. |
| Pending (recorder starting) | border `--vast-700` |
| **Reconnecting** | border `--green-700` #047857; the whole pill pulses opacity 1 ↔ .6 over 1.4 s. Tooltip "Still listening · Reconnecting…". |
| **Flushing** (stop pressed; uploading the tail) | row at opacity .4; the stop button is replaced by the 8-spoke spinner (UI §2.8) in meeting tint, scaled .76 in an 18 pt slot |
| Notepad focused | pill greyscale at opacity .5, not clickable (the notepad is already in front) |
| Tooltip | meeting title (max 300 wide, single line with a 20 pt end fade), then "• N words" with the bullet in white at .4 and the count in `--green-500`. Offset 4 from the pill; the stop button's own tooltip sits 9 away. |
| Hands-free → note morph | when a hands-free dictation hands off to the Notetaker, the bar holds meeting chrome (`popoToMeetingMorphHold`) for up to **10 s** while the recorder starts. The pill animates from the hands-free capsule (102.5 × 30, 1 pt #30302f) to the meeting capsule (2 pt green) using the 160 ms / 130 ms transitions above. |

**"Take notes" picker** (beside the bar on hover; `startMeetingContainer`) [C 36808]:

| Element | Spec |
|---|---|
| Button | 30 × 30 circle, black, 1.5 pt `--vast-900`; record glyph (ring plus filled dot); hover `--vast-900` fill, icon in `--accent` |
| Expanded | 54 wide with a 22 × 22 caret tab (`--vast-500` → white), spring 0.2 s. The caret opens the join menu (UI §10.3). |
| **Imminence dot** | 5 × 5, `--green-500`, 1 pt `--vast-950` ring, top-right, when a calendar meeting is about to start |
| **Nudge** | 3.2 s `cubic-bezier(0.34,1.4,0.64,1)`: the circle hops and squashes over a blurred 20 × 4 shadow, then a dot pops in (8 pt, `--fathom-500`, 1.5 pt `--lumen` border; or `--glow-300` variant). Off under reduced motion. |
| Tooltips | "Take notes", or "Start note" plus a triple-tap keytip |

Reference image: `scratchpad/flow/assets/meetings/longDictationNotetakerFlowBarPoster.jpg` shows the ready bar (mic) beside the expanded picker (record glyph and caret) on a #e4e4d0-like ground.

### 10.3 Upcoming-meeting pill and meeting cards on the bar [C 60315][C 98837][C 20321][C 64985][C 72197]

**Upcoming-meeting reminder pill** (`reminderLayer`, 14 above the bar). It morphs between levels over **420 ms** with the spring easing:

| Level | Size | Look |
|---|---|---|
| rest | **30 × 6**, radius 6 | `rgba(0,0,0,.5)`, 1 pt white at 50 % (a mini resting bar) |
| mini | **416 × 48**, radius **16** | **#1f1f1f** fill, **1.5 pt #30302f** border, shadow `0 8px 32px rgba(0,0,0,.38)`. One line: platform badge (24 pt), title (end-faded), meta 12/18 `#71716e`. |
| card | **416 × 80** | adds a subtitle row: 6 × 6 status square **#10b981** (radius 2), time, and a "brief" toggle (12/18 `#71716e` → hover `#deddd7`) |
| l4 (brief open) | 416 × **322** | scrollable pre-read: markdown 12.5/18 `#fcfcfb` at .92, headings 13/18 600, list markers `#878683`; fades in over 320 ms after 120 ms |

The pill's other parts:

- **Hot zone:** 428 × 54.
- **Stacking:** several meetings stack like cards (slot y, scale and z per level). A **corner badge** shows the count: 20 tall, `#2a2a29` fill, 1 pt `#343432` border, 12 pt 600 `#deddd7`.
- **Dismiss (×):** 24 pt circle at the top-left (−10, −8); `rgba(26,26,26,.9)` with 2 pt blur; hover `#3a3a3a`.
- **Join split button:**
  - Radius 8, 1 pt `#eeebe3` border.
  - Main part: **`--lumen-400` #ffffeb** fill, `#1a1a1a` text 12/18 600, padding 8 16 8 8. A 24 × 24 icon tile (radius 5, `#1a1a1a`) sits on the left. Two-line labels use 12/18 600 over 10/14 500 at .8.
  - Caret segment: padding 0 6, `#c8c8c2` divider. Hover: `--lumen-500`.
- **Auto-start countdown:** when "Start Notetaker automatically" is armed, a `--lumen-600` fill sweeps left to right inside the button (`--auto-start-progress` 0 → 1) with a 2 pt `--lumen-950` leading edge.
- **Join menu:** `#1a1a1a` fill, 1 pt `#343432`, radius 8, padding 4; items 12/18 500 `#deddd7`, padding 6 8, radius 6; hover white at 8 %.

**Meeting cards in the notification layer** (base style UI §2.12):

| Card | Spec | Purpose |
|---|---|---|
| Recording check-in [C 98837] | **250 wide**, padding 12, `--vast-950`. Countdown tile **100 tall, radius 16, `--lumen`**, number **32/40 600 `--vast-950`**, tabular. Title 15/20 600 sand-50; body vast-300. Full-width buttons 36 tall (End: `--vast-900` fill, `--sand-600` text). | max-length check-in ("End recording" / "Save") |
| Switch meeting [C 20321] | 320–440 wide, padding 16 16 18, **radius 24**, 1 pt `--vast-900`; list of meetings (rows 15/20, 6 apart, max 240 tall) | "Switch to another meeting?" |
| New note? [C 64985] | 380–440 wide, radius 24; text 15/20 `--vast-300`; actions right-aligned, 600 weight | "Start a new meeting note?" (No / Start) |
| Summary ready [C 72197] | 250 wide, black; illustration tile 116 tall, radius 16, `#e4e4d0`, holding a 193 × 85 mini summary card; body 15/20 vast-300; full-width view button 36 tall, `--sand-600`, radius 8 [U on trigger] | summary finished |
| Condensed status | the condensed variant (UI §2.12) with a record-dot badge glyph and a 3 pt `--lumen` progress bar | meeting detected, starting, uploading |

### 10.4 Hub Notetaker pages [C 81370][C 64204][C 20764][C 6812][C 6430][C 30004][C 64467]

| Surface | Spec |
|---|---|
| Sidebar item | "Notetaker" (record-dot icon, inner circle filled), plus "Tasks" (UI §3.2) |
| **Meetings library** (list page) | standard page card (UI §3.2). Rows grouped under sticky date headers (12/20 600 uppercase, tracking .075em, `--foreground-tertiary`). |
| Library row [C 64204] | min-height **60**, padding 12, **radius 12**; leading facepile tile (UI §10.1); text block at opacity **.7** → 1 on hover or selection (150 ms); title 15/20 400; time line 15/20 (hover `--neutral-500`); selected `--background-tertiary` |
| Row trailing slot | folder chips and labels (opacity .7); a 28 pt "…" menu revealed on hover (width 0 → 28, 200 ms); in-progress glyph is a 14 pt rounded square outline with a 5 pt centre dot |
| **Meeting detail** | opens as an **L2 page** in the hub: page card with a **4 pt** border and a 24 gutter (`pageL2`). It reuses the notepad components of UI §10.1: title, tabs, transcript, summary, tasks, footer composer. |
| **My Tasks** | the task rows and checkboxes of UI §10.1 at full page width |
| **Folders** [C 30004] | folder chips 32 tall, padding 0 12, radius 8, 1 pt `--border`, text `--vast-500`, max 220 wide; compact 26 / radius 6; "add" chip dashed; clickable hover `--muted-hover`. Folder pages list meetings with the library row. Shared folders show a facepile. |
| Generic chip [C 64467] | 12/20 550, padding 3 8, radius 8. Fill variant `--background-secondary`; outline variant 600 weight on background with a border. |
| **Home Notetaker widget** [C 6812] | full width, `--background-tertiary`, **radius 16**, padding 16 0 (24 bottom when expanded); menu row padding 0 12; holds the calendar list below |
| **Calendar list** [C 20764] | Section label: black pill, white 12/20 600 uppercase, padding 3 8, radius 6. Event card: padding 8 12, **radius 12**, hover and selected `--background-secondary`. **Accent bar 4 × 36**, radius 4, in the event's calendar colour. Declined events use a dotted bar; dimmed rows sit at .7. "Last meeting" chip `#3cbb77`. |
| Calendar colours (Google Calendar event palette) | lavender #7986cb, sage #33b679, grape #8e24aa, flamingo #e67c73, banana #f6bf26, tangerine #f4511e, peacock #039be5, blueberry #3f51b5, basil #0b8043, graphite #616161 |
| Event popover [C 6430] | min 240 wide; event box `--background-secondary`, 1 pt border, radius 12, padding 12; calendar swatch 12 × 12 radius 2 (default `--blue-500`); divider 1 pt `--vast-200` |

### 10.5 Notetaker onboarding and settings

- **Onboarding steps:** product intent (dictation vs Notetaker polaroids), "how do you record meetings", "what kinds of meetings", and connect calendar. They use the onboarding frame of UI §5.1; media is listed in UI §5.2.
- **Settings › Notetaker:** uses the settings card and row layout of UI §4.2. Controls include auto-start, meeting detection, menu-bar meeting title, hide in screen share, the consent message and the join shortcut. Wording is in `strings.md`.

### 10.6 Menu-bar next-meeting title [M module 63830]

On macOS the status item shows a **text title** after the icon, set with `tray.setTitle`. It is prefixed with two spaces and capped at **30 characters**. It is on by default (`notetakerMenuBarMeetingEnabled`) and toggled with the eye / eye-slash menu item. It reads active, non-declined calendar events from now until the end of tomorrow.

| Situation | Title |
|---|---|
| Next meeting starts within **10 min** | "`<title>` • in N min" ("now" under a minute). Several meetings at that time: "N meetings • …". |
| No meeting now; next is more than **1 h** away | "Free until 3pm" / "Free until 3:30pm"; a weekday prefix ("Tue 9am") when the meeting is more than a day away [U] |
| No meeting now; next within the hour | "`<title>` • in N min" |
| In a meeting, before its **midpoint** | "`<title>` • 25m left" (or "1h 5m left") |
| In a meeting, after its midpoint | the next meeting if it starts within 1 min of the current one ending. Otherwise "Free from `<range>`" if the next is the same day, or "Free after `<time>`". |
| Nothing upcoming | no title |

- **Truncation:** the title part is cut so that "title • suffix" fits 30 characters, with "…".
- **Menu:** a "Join meeting" item (when the current meeting has a conference URL), then **Now / Today / Tomorrow** sections. Each event item shows the title with a time-range sublabel. Meetings happening now are all listed; Today and Tomorrow together fill up to 3 items in total. Then past notes and "See all upcoming meetings".

### 10.7 Reference images (scratchpad, not in the repo)

`scratchpad/flow/assets/meetings/` holds:

- `notetaker_meetings-4s.png`: a frame of the sign-in video. It shows the notepad: serif title, tabs with an underline, speaker labels in colour over tertiary bubbles, and the footer with a "Stop" pill (green square) and an "Ask anything" capsule.
- `longDictationNotetakerFlowBarPoster.jpg`: the Flow Bar beside the expanded "Take notes" picker.
- Notetaker notification posters: `meetingRecorderNudge*`, `firstMeetingCompleteWithIncomingSummaryPoster.jpg`, `notetakerWelcomeModal.webp`, `notetakerLiveTranslationModal.webp`.
- Calendar and consent heroes: `calendar_connect_waiting_hero.png`, `calendar_incomplete_*`, `outlook_incomplete_consent.png`.
- Notetaker gate and offer art; `firstSummaryCelebration.png`; summary connect-app banner previews.
- `homepage-notetaker-empty-state.png`; the coach-mark SVGs; the onboarding meeting illustrations; the `meeting-recorder.svg` icon.

All of it is the original product's artwork, for reference only.

---

## 11. Gaps and open questions

| # | Gap | Note |
|---|---|---|
| 1 | Exact pixel layout of each hub page (Home/History rows, Dictionary, Snippets, Style, Insights) | Only the shared page/card/row metrics are documented. The per-page rules are in `scratchpad/flow/css/hub.css`, by module id. The dictation History list is module 66529: bordered sections with radius 16, a 98 pt time column, rows padded 16. |
| 9 | Notetaker: when the reminder pill moves between rest, mini, card and l4; which notification carries the summary-ready card; where `recording_pill_label` ("Listening") is shown | Levels and geometry are recovered (UI §10.3); the triggers live in JS state machines that were not traced [U] |
| 10 | Notepad dark mode | The notepad uses the shared tokens, so it presumably follows `theme` like the hub; not verified [U] |
| 2 | Hover-tooltip text on the resting bar and the exact click/hold mapping on the pill | Click on `ready` starts hands-free (`ACTIVE_POPO`) [J]; wording in `strings.md` |
| 3 | Visual geometry of the macOS 26 permission guide (Permiso) | Not recovered; recommend one native panel modelled on UI §5.4 |
| 4 | The Lottie `pulsing_circle` use site | Not traced |
| 5 | Fonts | Figtree, EB Garamond, Manrope and Google Sans Code are all SIL OFL fonts [U, verify]; they could be bundled. Whether the rebuild keeps this typography or uses SF Pro is a **design decision for the orchestrator**, not settled here. |
| 6 | Brand assets (icon, sounds, illustrations, logos) | Reference only. The rebuild needs its own icon, sounds and artwork. |
| 7 | Settings sidebar order in the rebuild | Original order recorded; final list is a product decision |
| 8 | Windows-only values (taskbar inset `DR`, `setShape`, Win32 caption buttons) | Ignored: the rebuild is macOS-only |
