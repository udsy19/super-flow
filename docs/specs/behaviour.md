# Wispr Flow 1.6.1147 — Behaviour specification (reference for the rebuild)

What the installed **Wispr Flow 1.6.1147** (`/Applications/Wispr Flow.app`, bundle id `com.electron.wispr-flow`, LSMinimumSystemVersion 12.0) does on the Mac, reconstructed only from the shipped bundle. The rebuild reimplements this behaviour from scratch as a native Swift app with **one deliberate change: speech-to-text, speaker diarization, text cleanup and meeting summaries run on-device** (see `local-models.md`). Scope is **all of Wispr Flow's user-facing features** — dictation (transcriber, cleanup/autocorrect, dictionary, snippets, styles, transforms, command mode) and the **meeting Notetaker** (meeting detection pop-up, recording, live transcript, speakers, summaries, action items) — minus what only exists because of the cloud, accounts or billing. It does not copy Wispr Flow's code, prompts or assets.

Companion documents: `ui-reference.md` (look), `strings.md` (wording), `local-models.md` (on-device models), `oss-survey.md` (open-source projects and libraries to depend on or learn from).

## 0. Evidence legend and method

| Tag | Meaning |
|---|---|
| **[S]** | String evidence: the English i18next namespaces bundled in the renderer (`menus`, `settings`, `onboarding`, `notifications`, `hub`, `insights`, `emails`; 6,128 keys), and literals in the main-process bundle or the Swift helper. |
| **[B]** | Code evidence: the webpack bundles in `Contents/Resources/app.asar` (main process `.webpack/main/index.js`, renderer windows `.webpack/renderer/*`), the helper IPC schema compiled into the main bundle, and the Swift helper's ObjC/Swift metadata (`rea inspect-native-dispatch-metadata`). Minified identifiers are not quoted; enum string values and constants are. |
| **[R]** | Resource evidence: `Info.plist` files, entitlements, `Resources/migrations/*.js` (the SQLite schema), `Resources/assets/*`. |
| **[U]** | Unverified: inferred from naming or partial code. Treat as a design decision to make, not a fact. |

Method and limits:

- The app was **never launched**, the screen was never captured, and nothing under `~/Library/Application Support/Wispr Flow/` (history DB `flow.sqlite`, audio) was read. Only the bundle was inspected; `app.asar` was extracted read-only into a scratch folder.
- Wispr Flow is cross-platform (macOS + Windows). Only the macOS branch is described. In code, `process.platform === "darwin"` selects the Mac values.
- **In scope:** dictation (§2–§11) and the **meeting Notetaker** (§20), which Wispr Flow ships as a first-class feature (`[MeetingAutoDetect]`, `[MeetingRecorder]`, `[ActiveMeetingSession]` subsystems; `meeting_recorder` window; 74+46 notification keys; `Meetings`/`CalendarEvents`/`Todos`/`Folders` tables).
- **Out of scope** (dropped, §21): teams/organisations, billing/trials/referrals/students, HIPAA, cloud sync and sharing links, mobile hand-off, server-side connectors/briefs, telemetry, and Windows code paths.

---

## 1. App shell and processes

1. **Two processes** [R][B]:
   - **Electron app** (`Wispr Flow.app`, Electron + React, webpack). Main process owns state, preferences, the dictation state machine, network calls, the SQLite store (Sequelize + migrations), the tray item and all windows.
   - **Native Swift helper** (`Contents/Resources/swift-helper-app-dist/Wispr Flow.app`, bundle id `com.electron.wispr-flow.accessibility-mac-app`, `LSUIElement = true`, built with Xcode 26.5 / SDK macOS 26.5, arm64). It owns everything that needs native APIs: the keyboard/mouse event tap, Accessibility (AX) reads and writes, pasteboard + synthetic ⌘V, clipboard restore, secure-input detection, audio interruption and system volume, media pause (`MediaRemoteAdapter.framework`), hardware/keyboard detection, Bluetooth mic ring (`BLEAudioManager`), focus mode, and floating web panels. A nested `Helpers/FlowPermissionGuide.app` shows the "drag the icon into the Accessibility list" guide [R][B].
   - IPC is newline-delimited JSON over the helper's stdin/stdout, typed by a generated schema `HelperAPI { HelperAPIRequest | HelperAPIResponse }` (Swift, TypeScript and C# models generated from one JSON Schema) [B]. The message catalogue is in §1.6.
   - **The rebuild is one native process** (Swift, AppKit/SwiftUI). The helper/IPC split disappears; the message catalogue below becomes in-process service calls.
2. **Dock and login.** The Electron app shows a Dock icon by default (`hideAppInDock = false`; Settings › System "Show app in dock") and opens at login by default (`openAtLogin = true`; "Launch app at login") [B][S].
3. **URL scheme** `wispr-flow://` [R][B]: `open`, `open/<page>`, `start-hands-free`, `stop-hands-free` (ignored unless dictation is idle/dismissed, resp. running), `switch-mic`, plus account/billing/LinkedIn callbacks (drop). The rebuild keeps `start-hands-free`, `stop-hands-free`, `open/<page>` under its own scheme.
4. **Data location** `~/Library/Application Support/Wispr Flow/` with `flow.sqlite` [B: `reset-profile` script]. Rebuild: `~/Library/Application Support/<App>/` (`store.sqlite`, `Models/`, `Audio/`).
5. **Updates.** Squirrel auto-update with tray/sidebar status rows ("Checking for updates...", "Update downloading...", "Update ready, restart now?", "Error updating, please restart", "Check for updates...", "Next update check: {{date}}"), and an "Update ready" ceiling dialog (Later / Restart now; "Choose Later and Flow will install it the next time you step away") [S]. Rebuild: GitHub-Releases updater like the sister apps (UpdateKit).
6. **Helper IPC catalogue** (requests sent between the two processes; names exact) [B]. What each does in the rebuild is noted where non-obvious.

   | Area | Messages |
   |---|---|
   | Lifecycle | `IsReady`, `StartAccessibilityServices`, `StartAllIntervals`/`StopAllIntervals`, `HelperAppShutdown`, `UpdateFeatureFlags` (drop) |
   | Keyboard | `UpdateShortcuts`, `KeypressEvent {eventType: key_event_press/key_event_release/mouse_event_*, key, index, inputType}`, `CheckStaleKeys → StaleKeysResponse`, `SetInputEventCapture`, `InputEvent`, `TapRecoveryEvent`, `TapState`, `SecureInputStatus {blocked, ownerAppName, ownerBundleId, secondsBlocked}`, `SimulateKeyPress {keycode, flags}` |
   | Dictation | `DictationStart {captureMarkerContext, includeOffscreen}`, `DictationStop`, `RecordingStarted`, `PlayDictationStartSound`, `PlayDictationStopSound` |
   | Context | `GetActiveAppInfo → ActiveAppInfo {appName, bundleId, url, windowTitle, codingCliAgent, codingCliAgentConfidence}`, `AppInfoUpdate`, `AppContextUpdate {nearestTexts, elementDescription, markerRange…}`, `CursorContextUpdate {fileNames, screenReaderMode, textAreaContents}`, `GetTextBoxInfo → TextBoxInfo {contents, beforeText, afterText, selectedText, isEditable, focusedElementHash, accessibilityIsFunctioning}`, `GetSelectedTextViaCopy {copyMode}`, `AccessibilityTreeHTML`, `AppContextHTML`, `SetAccessibilityTreeCapture` |
   | Insertion | `PasteText {pasteId, text, htmlText, captureKeystrokeTrace}`, `PasteOutcome {pasteId, success, reason, timeElapsedMs}`, `PasteBlocked {reason}`, `CancelPaste`, `DictatedTextVerification {verdict: verified/verified_before_after/not_found/skipped, reason}`, `GetDictatedTextPosition`, `UpdateEditedText {pastedText, editedText, editDistanceToDictated, keystrokeTrace…}`, `ClipboardChanged`, `StoreFocusedAppAndElement` / `FocusStoredAppAndElement`, `SuggestSelectTextbox` |
   | Permissions | `GetAccessibilityStatus → AccessibilityStatus`, `RequestAccessibilityPermission`, `SetAccessibilityGuidance {visible, appBundlePath, displayName}`, `GetMicrophonePrivacyStatus`, `GetSystemSettingsWindowBounds` |
   | Audio | `AudioInterruptionEvent {began/ended}`, `IsMediaPlayingUpdate {isMediaPlaying, isMediaPausable}`, `AudioCodecChanged`, `GetMicrophoneHolders`/`MicrophoneHoldersChanged`, `GetSystemAudioStatus`, `RequestSystemAudioPermission` (Notetaker system audio, §20.4) |
   | Misc | `GetHardwareInfo`, `GetDeviceInfo`, `FireHaptic {bubbleHover/bubbleUnhover}`, `SetFocusMode`, `FocusModeBlocked`, `ShowFloatingWebPanel`/`HideFloatingWebPanel`, `ActivateRunningApp`, `GetRunningApps`, `TrackAnalyticsEvent` (drop), BLE ring messages (drop) |
   | Meetings | ~25 messages: `GetMeetingTabScan`, `SetTabStripMonitor`/`TabStripRowChanged`, `GetConferenceEndState`, `GetNativeCallSnapshot`, `MeetingSpeakerChange`/`StartSpeakerPolling` (active-speaker and participant names read from Zoom/Meet/Teams UI via AX), `MeetingWindowBindReport`, `PositionBrowserWindow` (split screen), `PostConsentChatMessage`, `ZoomMeetingAudioChanged`/`TeamsMeetingAudioChanged`/`GoogleMeetMicrophoneMuteChanged`, `BrowserLeaveProof`, `HolderClickObserved` — see §20.3 |

---

## 2. Dictation model

### 2.1 Modes

| Mode (code name) | Trigger (Mac default) | Behaviour |
|---|---|---|
| **Push-to-talk** (`ptt`) | Hold **Fn** | Recording runs while the shortcut is held; release stops, processes and inserts [B][S "Hold to say something short"]. |
| **Hands-free** (`popo`, "locked") | **Fn + Space**, or **double-tap Fn** | Toggle: first press starts a locked session, the next press of the hands-free shortcut — or of the push-to-talk shortcut — finishes and inserts [B][S "Dictate hands-free by pressing this hotkey to start and stop", "Double tap <keys></keys>"]. |
| **Command mode** (`lens` / `command`) | **Fn + Control** (hold) | "Select text and ask Flow or [web answer engine]" [S, product name redacted]: speak an instruction that rewrites the selected text or answers a question. Paid feature; off by default (`commandModeEnabled = false`) [B][S]. |
| **Instruct mode** | same shortcut while an experiment flag is on | "Dictate instructions to draft replies using screen context" [S]. Experimental; rebuild defers. |
| **Transform** (`polish`, `polish_prompt_1…9`, `learned_voice`…) | **⌥1** (Polish), **⌥2**, **⌥3** | Rewrites the *selected* text with a saved prompt (§10). Not a dictation. |
| **Notetaker** (`open_meeting_recorder`) | **⌥M**, or **triple-tap** the dictation key within the debounce window | Starts or joins the meeting Notetaker (§20) [B][S "Press your dictation key three times quickly to join a meeting or start a new note"]. |
| **Scratchpad dictation** | Open-Scratchpad shortcut (none by default) | Tap opens the Scratchpad; hold > **350 ms** starts push-to-talk into it; double-tap within **500 ms** starts hands-free [B]. |

Sources recorded per dictation (`keyboard`, `mouse`, `status_indicator` = click on the Flow Bar, `deeplink`, `ble`, `error`) [B].

### 2.2 Dictation status machine [B]

`initializing → listening → stopping → processing → idle`, plus `retrying`, `error`, `dismissed`, `testing` (onboarding mic test).

- "Recording" = `initializing` or `listening`. "Busy" = `initializing`, `stopping`, `processing`, `retrying`.
- A new dictation may start only from `idle`, `dismissed` or `error`.
- `isLocked` marks hands-free; `isCommandMode` / `isInstructMode` mark the other modes.
- Dismiss reasons (exact values): `user_action_escape`, `user_action_cancel_button`, `user_action_settings_button`, `other_shortcut`, `debounce_ptt`, `debounce_popo`, `debounce_triple_press`, `no_internet`, `long_initialization`, `notification_callback`, `excessive_duration_error`, `no_audio_during_dictation_error`, `get_user_media_abort`, `mic_acquisition_failed`, `audio_context_recovery`, `admin_policy_blocked`, `onboarding_exited`, `force_reauth`.
- Outcome of a dictation (`history.status`-like): `empty`, `error`, `raw_transcript`, `formatted`, `fallback`, `verification_failed`, `no_audio`, `dismissed`, `processing`, `timeout`.

### 2.3 Limits and timings [B]

| Constant | Value |
|---|---|
| Double-tap / debounce window (`DICTATION_DEBOUNCE_DELAY`) | 500 ms |
| Scratchpad hold → push-to-talk (`SCRATCHPAD_PTT_DELAY_MS`) | 350 ms |
| Max session (`DICTATION_DURATION_TIMEOUT`) | 20 min ("Flow supports up to 20 minutes per session.") |
| Warning (`DICTATION_DURATION_WARNING_TIMEOUT`) | 19 min ("You have <1 minute left before you reach the 20 minute limit!") |
| Other-key cancel window | PTT started < 1 s ago and another shortcut chord begins → dismiss with `other_shortcut` ("Another key was pressed while starting. Hold only {{shortcut}} to dictate.") |
| Triple-tap of PTT within the debounce window | Notetaker shortcut (§20.2); disabled while a hands-free session is locked |
| Textbox context sent to the formatter | 500 chars (`MAX_TEXTBOX_CONTENTS_LENGTH`) |
| Audio | 16 kHz mono, Opus 20 ms frames for upload; server chunks of 28 s [B] |
| Stale-key sweep | every 5 s; a key held > 10 s that the OS reports as up is dropped |
| Transform max input | 1000 words ("Try again with under 1000 words") |
| Audio kept for retry/playback | 14 days ("no longer available (older than 14 days)") [S] |

---

## 3. Shortcuts

### 3.1 Defaults (macOS) [B]

| Action (code value) | Default | Settings label [S] |
|---|---|---|
| `ptt` | Fn | Push to talk — "Hold to say something short" |
| `popo` | Fn + Space (and double-tap Fn, keycode alias `doubleFn`) | Hands-free mode |
| `lens` | Fn + Control | Command Mode |
| `paste_last_text` | ⌃⌘V | Paste last transcript |
| `copy_last_text` | ⌃⌘C | Copy last transcript |
| `dismiss` | Esc | Cancel — "Dismiss dictation and notifications" |
| `polish` | ⌥1 | Transform |
| `polish_prompt_1`, `polish_prompt_2` | ⌥2, ⌥3 | custom Transforms |
| `open_meeting_recorder` | ⌥M | Join meeting / start Notetaker — "Open the Notetaker and start a new note" |
| `toggle_focus_mode` | ⌥F (only when Focus Mode is enabled) | Focus Mode |
| `open_scratchpad` | none | Open Scratchpad |
| `view_diff` | none | Transform view changes |
| `enter_rebind` | none (mouse button suggested) | Press Enter — "Trigger enter with a mouse shortcut (or another key) to send messages faster" |
| Internal | ⌘Z = `undo` (undo last Transform), ⌘V = `paste_event` | — |

Alternative suggestion when Fn is unavailable: "We recommend <pill>control</pill> + <pill>space</pill>" [S]; a historical Mac alternative set is ⌃⌥ (PTT), ⌃⌥Space (hands-free), ⌃⌥⌘ (command) [B]. The helper detects whether the keyboard has an Fn key ("Found an external non-Apple keyboard. Assuming no Fn key available.", known Apple keyboard models list) [S] → the rebuild proposes ⌃Space when no Apple keyboard is connected [U].

Several shortcuts may map to one action ("Add another"); each action can be "Reset to default" [S].

### 3.2 Key model [B]

- Shortcuts are sets of macOS virtual keycodes, stored as the sorted codes joined with `+` (e.g. `"63"` = Fn, `"49+63"` = Fn+Space) in a map `shortcut → action`.
- Left and right modifiers are distinct (`cmd` 55 / `cmd_r` 54, `opt` 58 / `opt_r` 61, `ctrl` 59 / `ctrl_r` 62, `shift` 56 / `shift_r` 60, `fn` 63, `caps_lock` 57). Mouse buttons are pseudo-keycodes: middle 4098, buttons 4–10 = 4099–4105, aux 65535.
- Display order inside a chord: Fn, Control, Command, Option, Shift, then others; labels `⌃ Ctrl`, `⌘ Cmd`, `⌥ Opt`, `⇧ Shift`, right-hand variants suffixed `→`, `Space`, mouse "Middle Click", "Mouse 4"…
- **Validation** (exact messages [S]):
  - must include a modifier (incl. Fn) or a mouse button — "Shortcut must include a modifier key or a valid mouse button";
  - at most 3 keys — "Shortcut must contain 3 or fewer keys";
  - not both left and right of one modifier — "Shortcut cannot contain both left and right version of the same key";
  - not already used — "This shortcut is already in use";
  - not in the blocked list — "This shortcut is not allowed: {{keyString}}". Blocked on Mac: every bare letter/digit/punctuation key, and ⌘C ⌘V ⌘X ⌘Z ⇧⌘Z ⌘R ⇧⌘R ⌘A ⌘F ⌘G ⇧⌘G ⌘H ⌘M ⌘N ⌘O ⌘P ⌘S ⌘T ⌘W ⌘Q ⌘, ⌘←→↑↓ ⇧⌘←→↑↓ ⌘Space ⌘Tab ⇧⌘3 ⇧⌘4 ⇧⌘5 ⌥⌘Esc ⌃⌘F ⌥⌘D Fn+F11 Fn+F12 ⇧⌘Q ⌥⌘Space ⌥⌘P ⌃↑↓←→ ⌘B ⌘I ⌘U ⌃A ⌃E ⌃K ⌘⌫ ⌥⌫ ⌥⌦ ⇧⌘T ⌥⌘← ⌥⌘→ ⌘= ⌘- ⌘⌦ ⇧⌘⌦ ⇧⌘F ⌥⌘F.
- Warning (non-blocking): "Warning: Your Hands-free mode shortcut is a part of a Push-to-talk shortcut. This may lead to conflicts." [S]

### 3.3 Matching engine [B]

The helper's event tap forwards every key-down/up and mouse button event (with a monotonically increasing index; a gap is logged). The main process keeps the set of keys currently down and runs:

1. **Press**: when the set of held keys equals a registered chord exactly, that action fires (`isRelease = false`).
2. **Release**: releasing any key of the active chord fires the same action with `isRelease = true`. If nothing is recording, a release is ignored. While recording, the release is routed to the running mode (locked → `popo`, command → `lens`, else `ptt`).
3. **Chord upgrade**: if the held chord was a strict subset of a larger chord bound to the *same* action, pressing the extra key "upgrades" without restarting (logged "Shortcut upgrade").
4. **Lock and finish**: while a hands-free session runs, pressing PTT or hands-free ends it and inserts.
5. **Esc** (`dismiss`): cancels a recording/processing dictation, cancels a running Transform, closes the diff view, or dismisses the visible notification — in that priority. Esc pressed while other keys are held also dismisses.
6. **Other-shortcut cancel**: if PTT has run < 1 s and the user goes on to press another chord, PTT is dismissed (§2.3).
7. **Paste-last** is fired on *release* of all its keys (+25 ms), so the synthetic ⌘V does not collide with held ⌃⌘.
8. **Stale/phantom keys**: a sweep asks the helper which "down" keys are actually up (`CheckStaleKeys`); chords involving keys held > 2.5 s are verified before firing; keys held > 10 s are dropped. After the event tap is re-enabled (macOS disables taps on timeout), held keys are re-validated.
9. While a Transform runs, starting a dictation is refused with "PolishRunningWarning".
10. While the Settings shortcut recorder is open, key events go to the recorder instead of actions ("Press key or mouse button", "Enter new hotkey").
11. **Secure input**: if another app enables Secure Keyboard Entry, the tap stops receiving keys; the helper reports the owner app and the bar shows "Flow's shortcuts are blocked — {{appName}} has Secure Keyboard Entry turned on…" [S].
12. **Caps Lock** can be a shortcut; the helper reads it through HID so the OS caps toggle does not fire ("Caps Lock now starts dictation instead of turning on all caps") [S][B].

Rebuild: a `CGEventTap` (session, head-insert, default/active so Fn and chosen chords can be swallowed) plus IOHID for Caps Lock; same rules and constants.

---

## 4. Audio capture

1. **Device selection** [S][B]:
   - "Microphone" picker with "Auto-detect"-style ranking: a user-ordered ranking list (`rankedAudioDevices`, "Drag to reorder microphone preference ranking", "Edit Ranking", "Forget device", "Done Editing") and an explicit override (`overrideAudioDeviceId`).
   - "Built-in mic (recommended)"; "From computer settings" (system default); virtual devices hidden behind "Show other devices ({{count}})".
   - Unavailable reasons: "Laptop lid is closed" (clamshell), "Put on your headset to use it" (Jabra wear sensor).
   - AirPods warning: "AirPods may be slow to start and have more errors in dictation. We recommend the built in microphone."
   - Mic changes are announced (`MicSwitched`, `NewMicDetected`, `MicDisconnected`, `MicNotFound`, `MicDeviceUnavailable`).
2. **Format**: 16 kHz mono PCM captured in an AudioWorklet (`recorderWorklet.js`), Opus-encoded in worker threads for upload [B]. Rebuild: `AVAudioEngine` input tap → 16 kHz Float32 ring buffer for the local engine; no encoding (optional local compressed copy only for history playback, §11).
3. **Level**: the live input level drives the Flow Bar waveform and the onboarding "Do you see purple bars while you speak?" test [S].
4. **No-audio detection** [S]: before/while recording — "No audio received / We're not hearing anything. There may be an issue with your mic or permissions." escalating to "Microphone is not working"; after recording — "Is your microphone muted? We didn't pick up any audio from {{micLabel}}" and "We couldn't hear you".
5. **Mic held by another app** ("Microphone is in use", "Mic in use:") via the helper's `MicrophoneHoldersMonitor` [S][B].
6. **System audio while dictating** [B][S]:
   - "Mute all audio while dictating" (`shouldMuteAudio`, default **off** on Mac) — the helper lowers output volume to 0 and restores it afterwards (with owed-restore bookkeeping across device changes).
   - "Pause music while dictating" (`shouldPauseAudio`, default off, Experimental) — pauses Now Playing media through MediaRemote and resumes it. Rebuild: MediaRemote is private and restricted since macOS 15.4, so pausing is best-effort (or dropped) and muting is the supported option (`oss-survey.md` §8.1) [U].
   - Audio interruptions (`began`/`ended`) are observed.
7. **Sounds**: "Dictation and notification sounds" (`enableSounds`, default on). Start and stop sounds play through the helper; there is a paste sound and versioned sound sets (`selectedSoundFolder`, default null = built-in set). Files and timing in `ui-reference.md` §Sounds [R][B].
8. **Whispering** is marketed and supported ("Flow works even when you whisper") [S] — the rebuild needs input gain normalisation before the model (see `local-models.md`).

---

## 5. The Flow Bar (floating pill)

Visuals, sizes and animations: `ui-reference.md`. Behaviour [S][B]:

1. **Visibility**: "Show Flow Bar at all times" (default **on**; pref `hideFlowBarPermanently = false`). When off, the bar appears only while dictating/processing or showing a notification. "Hide for 1 hour" (right-click menu) → "The Flow Bar will be hidden for an hour".
2. **Position**: docked to the bottom centre of the active screen by default (`statusDockEdge = "bottom"`). It can be dragged to the **left, right or bottom** edge ("Click and drag on the Flow Bar to move it to the left, right, or bottom of your screen", "Click and drag the Flow Bar to move it!"). On the desktop it sits just above the Dock whatever its size; with the Dock on a side or hidden, and in a full-screen space, it sits at the screen's bottom edge (UI §2.2).
3. **States** (driven by §2.2): idle (minimal pill), hover (expands; tooltips and hint copy from the `hub_status_*` strings), listening (waveform from the mic level; hands-free shows **Cancel** ✕ and **Stop / "Finish and paste"** buttons), stopping/processing (loading animation), retrying ("Still listening · Reconnecting…" in the cloud app), error (notification card), "Cleaned up! See what's changed" after auto-cleanup edits, word-count tooltip "{{count}} words".
4. **Hover** turns the thin idle capsule into the `ready` pill with a mic glyph; **click** on it starts a hands-free dictation (source `status_indicator`) [B][U on click vs. press-and-hold]. The idle bar stays hidden until onboarding is completed [B].
5. **Right-click menu** [S]: Paste last transcript · Transcript history · Microphone ▸ (devices; "Show other devices ({{count}})" / "Show fewer devices") · Languages ▸ · Formatting options ▸ · Configure reminder · Mute reminder for 12 hours · Hide for 1 hour · Settings.
6. **Notifications** are in-app cards, never macOS banners: each targets a window (`status` = above the Flow Bar, `hub`, or `contextMenu`) with a variant and a timeout (e.g. 10 s) [B] — §18.
7. **Typing reminder ("pulsar")**: if the user types a lot in a text app, the bar gently pulses with "Try dictating by holding {{shortcut}}" / "by double tapping"; configurable per app category: "Disabled", "All apps", "AI apps", "Documents & notes", "Email", "Personal messaging", "Work messaging", "Specific apps" [S].
8. **Scratchpad button** on the bar (optional, "Add to Flow Bar") opens the Scratchpad [S]. Rebuild: always on the bar as "Quick note", opening Notes with a blank note focused for dictation; no language or "Take notes" button on the bar.
9. **Creator mode**: shows "Dictating with Wispr Flow" while dictating (for screen recordings) [S]. Rebuild: keep as an optional label with the rebuild's name, default off.
10. Admin block: "Voice-to-text disabled" in apps blocked by policy (drop).

---

## 6. Context capture (per-app)

At dictation start the app snapshots the target [B]:

1. **Frontmost app**: name, bundle id, browser URL (for browsers), window title, and a detected coding CLI agent inside terminals (an enum of 8 known agent CLIs, with high/low confidence) [B].
2. **App type** from bundle id / URL / name lists [B]:
   - `personal_messaging`: Messages, WhatsApp, Texts, Messenger, Beeper, Telegram, Signal, Discord, WeChat (+ web URLs `web.whatsapp.com`, `messenger.com`, `web.telegram.org`, `discord.com`, `x.com`, `reddit.com`…);
   - `work` (work messaging): Slack, Teams, Zoom chat, Google Chat, Intercom, LinkedIn…;
   - `email`: Mail, Outlook, Gmail, Superhuman, Mimestream, Spark, Thunderbird, HEY, Front… (+ webmail URLs);
   - `document`: Notion, Google Docs, Word, Pages, Obsidian, Bear, Notes, Linear, Figma, IDEs (Xcode, JetBrains), editors…;
   - `ai`: AI chat apps, AI coding editors (Cursor, Windsurf, VS Code), Warp, Ghostty and ~50 AI app names;
   - `terminal`: Terminal, iTerm2, Warp, Ghostty, kitty, Alacritty, Hyper;
   - `other`.
   These drive Style (§8.4), formatting rules, the typing reminder and email detection. The rebuild ships these lists as data.
3. **Accessibility context** ("Context awareness", `useAxContext`, default **on**: "Allow Flow to use limited, relevant text content from the app you're dictating in to spell names correctly…") [S][B]:
   - the focused text element's value, the text before/after the caret, the selection, `isEditable`;
   - "nearest texts" around the caret and words parsed from the visible AX tree (`ax_context`);
   - the textbox contents, capped at 500 characters.
4. **IDE context** (Settings › Vibe coding): open file names and variable names for VS Code/Cursor/Windsurf when the IDE runs in Screen Reader Optimized mode ("Variable recognition"), and "File Tagging in Chat (Cursor & Windsurf)" (`ideFileTagging`, default on) [S][B].
5. **OCR of the screen** (`shouldOCRScreenCapture`, default off; requires Screen Recording) — cloud OCR. Rebuild: drop, or optional on-device Vision OCR later.
6. **Dictionary context**: starred personal words first, then the rest, sent as a vocabulary hint (cap not recovered [U]).
7. **User name** (first/last) as a spelling hint.
8. **Previous dictation** (`prev_asr_text`, `prev_llm_text`, `prev_detected_language`) for continuity.

---

## 7. Processing pipeline (what the cloud does today)

1. Audio streams during recording over gRPC/WebSocket (`wss://api.wisprflow.ai/`, `api-east`, a Baseten/Modal-hosted model; a server list is fetched from `inference-info.wisprflow.com/dictation_url.txt`); REST fallbacks `POST /llm/asr`, `/llm/asr_audio_chunks` [B].
2. Request payload [B]: `audio_packets`, `pipeline` steps, `context {app {name, bundle_id, type, url}, ax_context, ocr_context, variable_names, file_names, dictionary_context, user_first_name, user_last_name, textbox_contents, content_text}`, `personalization_style_settings`, `language[]`, `prev_asr_text`, `prev_llm_text`, `prev_detected_language`.
3. **Pipeline steps** [B]: `transcribe`, `align`, `format` (omitted when the formatting option is "No AI formatting"), `lowercase_sentences` ("Casual messaging"), `slack_tagging`, `email_signature`.
4. Formatting models: English formatting via fine-tuned Llama 3.1 8B models (one for email, one general); non-English via `/llm/format_non_english`; plus `/llm/detect_formality`, `/llm/check_sensibility`, `/llm/classify_intent`, `/llm/extract_asr_words`, `/llm/extract_edited_words` (auto-learn) [B].
5. Delays: "Taking longer than usual… Your audio is saved for retrying" (`processingDelayNotificationEnabled`, default on). Failures fall back to the raw transcript (`fallback`/`raw_transcript` outcomes) or "Something's not right — Transcript failed to load. You can always recover it from History." [S][B].
6. **Rebuild**: every stage runs locally — VAD + ASR engine → deterministic rules → optional small-LLM cleanup → rules again → insert (`local-models.md` gives engines, budgets and fallbacks). The fallback is always the locally formatted raw transcript; nothing is lost.

---

## 8. Formatting and cleanup features

### 8.1 Always-on basics
Auto-punctuation and capitalisation, number formatting, filler removal ("um", "uh"), and repeated-word cleanup are part of "format" [B][U on exact rule set]. "Smart Formatting — Automatically formats your dictation" (Settings › System; the control now lives in Style › Auto cleanup) [S].

### 8.2 Auto-cleanup level (Style › Auto cleanup) [S][B]

| Level | Description | Example |
|---|---|---|
| None | "Transcribes exactly what you said, including mistakes" | "hey joey, we still on for coffee or? I think we maybe should leave earlier…" |
| **Light** (default) | "Cleans up filler words and grammar" | "Hey Joey, are we still on for coffee? I think we should leave earlier to make it there in time…" |
| Medium | "Edits for clarity and conciseness" | "…We should leave earlier; there might be traffic…" |
| High | "Rewrites for brevity and polish" (not offered in every UI variant) | "Hey Joey, are we still on for coffee? Let's leave early to beat traffic. What do you think?" |

"Note your original dictation is never lost" — each History row offers "Undo AI edit" / "Redo AI edit".

### 8.3 Smart formatting behaviours [B][S]

| Feature | Trigger | Result |
|---|---|---|
| **Backtrack** (self-correction) | phrases `scratch that`, `never mind`, `forget that`, `cancel that`, `strike that`, `actually`, `i mean`, `no wait`, `wait no` | The corrected part replaces the retracted one: "How's 6, no 7?" → "How's 7?" |
| **Lists** | dictated numbers / sequences | Numbered or bulleted list (HTML `<ol>`/`<ul>`; ≥ 3 `<li>` counts as "Listed!") |
| **Email** | "Start with a greeting" in an email app | Greeting line, paragraphs, sign-off; optional signature "Written/Spoken with Flow" (drop) |
| **Press Enter** | dictation ending with "press enter" (Experimental, default **off**; regex `([.!?;])?\s*\bpress enter\s*([.!?,;:-]*)\s*$`, case-insensitive) | The phrase is stripped and Return is sent after the paste. First use shows a prompt explaining it. |
| **File tagging** | speaking a file name in Cursor/Windsurf chat | Inserts `@filename` followed by Tab to accept the IDE's mention |
| **Stacked messages** | Experimental, default off | "Split dictation into separate messages in messaging apps" (multiple sends) |
| **Hinglish** | language option | Hindi written in Latin letters |

### 8.4 Style (per app category) [S][B]

Tabs: **Personal messages**, **Work messages**, **Email**, **Other** (+ Auto cleanup). Options:

| Category | Options |
|---|---|
| Personal messages | Formal. (Caps + Punctuation) · Casual (Caps + Less punctuation) · very casual (No Caps + Less punctuation) |
| Work messages, Email, Other | Formal. · Casual · Excited! (More exclamations) |

Defaults: "default" (formal-like) per category [U]. "Style Detection — Automatically set messaging style" (Experimental, default **on**) infers the style from what the user typed before [S][B]. Separately, per-app **transcription format** (right-click › Formatting options; `defaultTranscriptionFormat` + `appTranscriptionFormats`): "Apply AI formatting" (default), "No AI formatting", "Casual messaging" (only proper nouns capitalised), "All lowercase" [B].

### 8.5 Personal dictionary [S][B][R]

- Words/phrases (`Dictionary.phrase`) used as recognition hints; optional **replacement** rule ("Correct a misspelling": misspelling → correct spelling; `toReplace`/`replacement`, `replacementHtml`).
- Star a word (sent first as context); sort: Newest first (default), Oldest first, Alphabetical (A-Z), Starred first; search; Import (bulk import, Experimental).
- **Auto-add to dictionary** (`shouldAutoLearnWords`, default **on**: "Adds corrected words automatically"): after a paste, the helper watches the focused field; if the user edits the inserted text, changed words are extracted and added ("Added {{terms}} to your Dictionary", tooltip "Flow learned this word automatically ✨"). Rebuild: same, with a local diff (token-level edit distance + capitalised/rare word heuristic; the cloud `/llm/extract_edited_words` is replaced).
- Defaults: a starter set of dictionary items is loaded once (`defaultDictionaryItemsLoaded`) [B]; a stop-word list is fetched from a CDN (rebuild: bundle a list).
- Team dictionaries / sharing / approval: drop.

### 8.6 Snippets [S][R]

- Trigger phrase → expansion ("Snippet" / "Expansion", counter `{{length}}/{{max}}`), stored in the same table (`isSnippet = true`).
- Expansion is applied when the spoken trigger appears in the dictation; similar triggers warn ("…is similar to the existing snippet…"); "This expansion is too long".
- Rebuild: expand deterministically **after** cleanup (exact/normalised match on word boundaries), never via the LLM.

### 8.7 Languages [S][B]

- "Dictation languages": pick one or more, or **Auto-detect (99 languages)**; at least one language or auto-detect required ("Please select at least one language or turn on auto-detect").
- Defaults: `selectedLanguages = [UI locale]` (e.g. `en`).
- A single selected language forces it for the model; otherwise the previous detected language is used as a hint.
- "We auto-detected your language. You can change the output language"; "Speaking a different language?" when detection disagrees with the selection.
- "Hinglish — Hindi in English letters". App UI language is a separate setting ("App Language", "System Default").

---

## 9. Inserting text

1. **Paste** [B][S]:
   - The helper writes the result to the general pasteboard as plain text and HTML (lists and rich text), using a lazy `NSPasteboardItemDataProvider` so it can tell whether the target app actually requested the data.
   - It posts ⌘V via CGEvent and reports `PasteOutcome`. No data request within the timeout means "failed paste likely".
   - The previous clipboard is **restored** shortly afterwards ("Clipboard contents restored and cleared"; a flag can disable restore). Pasteboard items are marked so clipboard managers can ignore them (`org.nspasteboard.ConcealedType` seen) [B][U on the exact marker set].
   - Rebuild: same mechanism, with `org.nspasteboard.TransientType` + `ConcealedType` + an own marker type; restore after ~250–500 ms [U].
2. **No editable target**: if no focused editable element exists, or the paste fails, the text stays on the clipboard. The bar says "Click a textbox and use {{shortcut}} to paste" (`PasteFailed`), and Paste last transcript works later [S].
3. **Verification**: after pasting, the helper reads the focused element to confirm the text appeared (`verified`, `verified_before_after`, `not_found`, `skipped`; reasons `no_focused_element`, `element_not_editable`, `textbox_too_long`…) [B]. Used for telemetry in Flow; the rebuild keeps it only to drive auto-learn and failure toasts.
4. **Edit observation**: for a short window after insertion, edits to the dictated text are captured (`UpdateEditedText`) → auto-learn (§8.5) [B].
5. **Paste last / Copy last transcript** (⌃⌘V / ⌃⌘C; tray "Paste last transcript"; History copy button) [S].
6. **Undo AI edit** in History restores the raw transcript; Transform undo is ⌘Z right after a Transform [S][B].
7. **Enter after paste** for "press enter" and the Press-Enter shortcut: `SimulateKeyPress(return)` [B].
8. **Secure fields**: no insertion into secure text fields (the helper sees `AXSecureTextField` / secure input) [U].

---

## 10. Transforms ("Polish") and Command Mode

1. **Transforms** (hub page "Transforms"; called Polish in code) [S][B]:
   - Select text in any app → press a Transform shortcut → the selection is read (AX, or copy-based fallback `GetSelectedTextViaCopy`) → rewritten → pasted over the selection; "See what's changed" diff window (`view_diff`); ⌘Z undo.
   - Built-in **Polish** with rule checkboxes; defaults on: "Make more concise", "Reword for clarity", "Reorder for readability", "Add structure for readability", "Maintain your tone"; defaults off: "Clarify main point", "Refine phrasing for impact".
   - Custom prompts: "Create your own" with a name ("Boss Mode" placeholder) and a shortcut ⌥2…; built-ins "Prompt Engineer" and "My Voice".
   - "Auto Apply After Dictation": run a chosen transform on every dictation (default off).
   - Writing samples (max 5) for "My Voice".
   - Errors: "Hey, select text first!", "Your text looks good!" (no changes), "Oops, too long to polish" (> 1000 words), "Couldn't detect text in your text box", "Flow can't paste right now. Text saved to clipboard".
   - Rebuild: local LLM, same UX; Polish rules become prompt fragments (`local-models.md` §3).
2. **Command mode** [S][B]: hold Fn+Ctrl with text selected and speak an instruction ("make this shorter", "translate to Spanish", "turn this into bullet points", or a question about the selection); the result replaces the selection (or, with no selection, is inserted at the caret). First use shows "Using Command Mode (beta)". Experimental toggle "Command Mode — Enable advanced voice commands." (default off). The bar uses the orange Command-mode accent (`ui-reference.md`). Rebuild: **in scope** with the local LLM (selection read via AX, else copy-based fallback; ⌘Z-style undo through the Transform undo path); web answers drop.
3. **Instruct mode** (experiment): dictate an instruction and get a drafted reply that uses the visible screen context (AX text of the conversation). Rebuild: later, same local LLM path as Command mode with the app's AX context as input [U].

---

## 11. History, Insights, Scratchpad

1. **History** (hub Home/"Dictation" page) [S][R]:
   - Every dictation is stored locally: transcript id, `asrText`, `formattedText`, `editedText`, timestamp, app, url, language, duration, word count, status, `isArchived`, audio (cloud app: 14-day availability).
   - Grouped by day (Today/"Yesterday"/date). Row actions: Copy transcript, Play/Pause audio, Retry transcript, Undo AI edit / Redo AI edit, Delete transcript (confirm "Are you sure you want to delete this transcript?"), Extract audio, Send feedback (drop). Search "Search past transcripts".
   - Empty state: "No dictations yet".
   - Interrupted/dismissed rows offer "Recover"/retry.
2. **Local data storage** (Settings › Data and Privacy) [S]: "Store data locally" (default) / "Auto-delete local data every 24hrs" / "Never store data locally"; with "Never" the History page shows "History disabled — Data storage is set to never store data…".
3. **Insights / stats** [S]: words dictated, average speed (WPM), streaks, top apps, word milestones (100, 500, 1000, 2000). Rebuild: computed locally from History; leaderboards and team ranks drop.
4. **Scratchpad** (hub page "Scratchpad", code "Notes") [S][R]:
   - A notes list (title, content, created/modified, pinned) and a floating Scratchpad window for dictating into notes.
   - Open behaviour: default / always new tab / last active pinned note.
   - Optional bar button, optional shortcut ("Press to open the scratchpad window").
   - Cloud sync of notes: drop.

---

## 12. Hub (main window)

Sidebar [S]:

- **Primary nav**: Home ("Dictation"), Notetaker (§20.8), Dictionary, Snippets, Style, Transforms, Scratchpad, My Tasks (§20.8), Insights, My Voice (writing samples; optional), Extensions (drop).
- **Secondary nav**: Invite your team (drop), Refer a friend (drop), Settings, Help.
- **Home** header: "Welcome back, {{firstName}}" / "Hey {{firstName}}, get back into the flow with <shortcut>"; banners and CTAs (drop most), History list.
- The hub follows a light/dark theme (`theme`, default `light`; "Dark mode is finally here") [B][S].

---

## 13. Settings (modal over the hub)

Sidebar: **SETTINGS** — General, System, Notetaker, Vibe coding, Experimental (Connectors, MCP, Extensions: drop); **Account** — Account, Team, Plans and Billing, Data and Privacy (Account/Team/Billing drop) [S]. The rebuild adds a **Models** pane (`local-models.md` §5). Controls and defaults [S][B]:

### 13.1 General
| Control | Default |
|---|---|
| Shortcuts — "Hold [Fn] and speak." → Change (opens the Shortcuts dialog, §3) | §3.1 |
| Microphone → Change ("Used for dictation.") | Auto (ranked; built-in recommended) |
| Languages / Dictation Languages → Change | UI locale; auto-detect off |
| App Language ("Select your preferred Wispr Flow Hub language") | System Default |
| Email language | drop |

### 13.2 System (sections in order: App settings, Sound, Notifications, Scratchpad, Extras, Data)
| Control | Default |
|---|---|
| Launch app at login | on |
| Show Flow Bar at all times | on |
| Dictation reminder (typing reminder) → Customize | category-based, enabled after onboarding |
| Show app in dock | on |
| Auto-add to dictionary — "Adds corrected words automatically" | on |
| Email auto signature (Written with Flow / Spoken with Flow) | off — drop |
| Creator mode — Show "Dictating with Wispr Flow" when dictating | off |
| Smart Formatting (moved to Style › Auto cleanup) | Light |
| Add Wispr Flow to LinkedIn | drop |
| Dictation and notification sounds | on |
| Mute all audio while dictating | off (Mac) |
| Notifications: Suggestions / Announcements / Milestones (/ Team updates / Team leaderboard: drop) | on [U] |
| Scratchpad open behavior | Default |
| Notetaker rows (in Flow they sit in System › Notetaker section and the Notetaker pane): see §13.6 | — |
| Restart tutorial — "Walk through the microphone, shortcut, and dictation setup steps again." | — |
| Reset app — "Reset only if advised by Flow support." | — |

### 13.3 Vibe coding
| Control | Default |
|---|---|
| Variable recognition (VS Code, Cursor, Windsurf) → Set up (Screen Reader Optimized instructions) | off (`cursorIdeIntegration`) |
| File Tagging in Chat (Cursor & Windsurf) | on |

### 13.4 Experimental
| Control | Default |
|---|---|
| Command Mode — "Enable advanced voice commands." | off |
| Press Enter command | off |
| Stacked messages | off |
| Style Detection — "Automatically set messaging style" | on |
| Pause music while dictating — "Pauses media instead of muting it." | off |
| Focus Mode — "Block distracting apps and websites with opt+f"; Blocked Apps (Slack, Superhuman) / Blocked URLs (`app.hex.tech`, `app.slack.com`, `mail.google.com`, `mail.superhuman.com`, `x.com`, `twitter.com`) | off — optional |
| Jabra wear detection | off — drop |
| Bulk import (snippets + dictionary from files) | off — keep as plain import |
| Email preferences (learn style from sent Gmail) | drop |

### 13.5 Data and Privacy
| Control | Default | Rebuild |
|---|---|---|
| Context awareness | on | keep (local) |
| Local data storage: Store / Auto-delete every 24h / Never store | Store | keep |
| Notetaker transcript retention: Never delete / 1, 7, 30, 90, 180, 365 days | Never delete | keep (local deletion of transcripts; separate "Keep meeting audio" option, §20.9) |
| Dictation cloud storage, Private Cloud Sync, Data Sharing, "Improve the model for everyone", "Show your public information", Download your data (server export), default Notetaker link visibility | various | drop; replace with "Export history" (local JSON/CSV) and "Delete all history" |

### 13.6 Notetaker [S][B]
| Control | Options | Default |
|---|---|---|
| Meeting detection — "Automatically detect any call" | Notify me / Do nothing | Notify me (`autoDetectMeetingsEnabled = true`) |
| Start Notetaker automatically (needs detection: "Turn on “Automatically detect any call” to use this") | on/off | off |
| Stop Notetaker when a call ends ("Notetaker stops automatically so you don't have to") | on/off | on |
| Notify before scheduled meetings start | Never / Right before the meeting (15 sec) / 1 minute before / 2 minutes before | on [U on timing] |
| Show your next meeting in the menu bar (title + countdown) | on/off | on |
| Show live transcript | on/off | on |
| Speaker names ("Show who said what by labeling each speaker") | on/off | on |
| Auto-detect speaker names ("Read participant names from the meeting") | on/off | on |
| Maximum recording length ("stops automatically at this length, with a warning shortly before") | 30 minutes / 1 hour / 2 hours / 3 hours | 2 hours |
| Long-meeting check-in | on/off | on |
| Open Notepad when Notetaker starts ("Opens your notes when you start the Notetaker") | on/off | on |
| Split screen join ("Puts your meeting on the left and your Notepad on the right") | on/off | off |
| Triple-tap dictation key to join/start | on/off | on |
| Join/start shortcut ("Press ⌥M to join a meeting or start the Notetaker") | shortcut | ⌥M |
| Consent — "Post a consent notice in the meeting chat" + editable message (default: "Hi everyone — quick note that I'm using Wispr Notetaker to transcribe this meeting so I can stay present. Let me know if you'd like me to turn it off.") | on/off + text | off (unset) |
| Don't show Notepad and Flow Bar in screen capture (window sharing type none) | on/off | off |
| Calendar notice in events you organise; auto-share notes with attendees | — | drop (needs calendar write + sharing) |
| Microphone (Notetaker) — "Notetaker always uses {{micName}}" (follows the meeting app's/system mic, auto language detect) | — | system default |

---

## 14. Onboarding

Hub-window flow with a progress header of five sections: **Sign up · Permissions · Set up · Learn · Personalize** [S][B]. Page sequence for a dictation user (exact page ids) [B]:

| # | Page id | Content [S] | Rebuild |
|---|---|---|---|
| 1 | `login` | "Let's get you started", "Sign in via browser", carousel ("4x faster than typing", "Works in any app", "100+ languages") | drop (no account); replace with a local Welcome |
| 2 | `welcome-basic` | Welcome | keep (rewritten) |
| 3 | `product-intent` | dictation vs. Notetaker ("Illustration of Flow helping you write and take notes") | keep — chooses which setup branch runs first |
| 4 | `about-yourself` | role, "What do you do for work?" | drop |
| 5 | `spend-time-typing` | "Where do you spend time typing?" (Chatting with AI, Coding with AI, Drafting emails, Sending messages, Something else) | optional (seeds reminder/app hints) |
| 6 | `introduction`, `work-environment`, `social-proof`, `testimonials` | experiments ("You can whisper around other people") | drop |
| 7 | `privacy` | "You control your data" (cloud sync, data sharing) | rewrite: "Everything stays on this Mac" |
| 8 | `permissions` | Microphone and Accessibility rows with Allow / Open Settings and the drag-icon guide | keep (§15) |
| 9 | `microphone-test` | "Test your microphone", "Do you see purple bars while you speak?", "Change microphone", AirPods warning, error states | keep |
| 10 | `shortcut` | "Test your dictation shortcut", "Hold <keys> while you speak.", "Does the button turn purple while pressing it?", "Edit shortcut" | keep |
| 11 | `language` | "Set the language(s) you speak" | keep |
| — | **model download** | — | **new**: pick/download the speech and cleanup models with progress (`local-models.md` §5) |
| 12 | `try-it-yourself` (or redesign: `tiy-intro`, `tiy-variant-slack`/`whatsapp`, `tiy-variant-gmail`, `tiy-variant-notion`) | practice textboxes in mock apps: message, email (hands-free double-tap), whispered note | keep 1–3 practice screens |
| 13 | `time-savings-*`, `personalize-*` (Personal/Work/Email/Other style pickers) | experiments | keep personalize (style per category) |
| 14 | team, trial, referral, Flow Pro pages | | drop |
| N | Notetaker branch: `about-yourself` → `how-do-you-record-meetings` → `what-would-make-notetaking-better` → `privacy` → `permissions` (Accessibility "Allow Wispr to recognize meetings", Microphone, **System audio** "Allow Wispr to capture meeting audio", restart if needed) → `connect-calendar` → `connect-apps` | | keep permissions + connect-calendar (EventKit); drop surveys and connect-apps |

Variant: the redesign shows Language before Shortcut. Afterwards a post-onboarding checklist runs (`set_app → open_app → click_textbox → completed`) with bar hints ("Open {{appSuggestion}}", "Click a textbox, hold …") [B][S]. "Restart tutorial" re-runs Microphone → Shortcut → Try it [S].

---

## 15. Permissions [S][B][R]

| Permission | Why (copy) | Detection / request |
|---|---|---|
| **Microphone** | "Flow will only access the mic when you are actively using it" · "Flow will play a sound and show an animation when the mic is active" | `AVCaptureDevice` auth; usage string "Allow Wispr Flow microphone access to transcribe your speech." |
| **Accessibility** | "This lets Flow put your spoken words in the right textbox" · "Flow uses this to gather context… and to access your clipboard temporarily" | `AXIsProcessTrusted`; System Settings opened at Privacy › Accessibility with a floating drag-the-icon guide window positioned next to System Settings ("Drag this icon into the Accessibility list") |
| **System audio** (Notetaker) | "Capture meeting audio for accurate transcripts" · "Notetaker uses this to transcribe the other participants in your meetings"; usage string "Wispr Flow needs to access your computer's audio to take notes during meetings." (`NSAudioCaptureUsageDescription`) | Core Audio process tap ("process_tap", macOS 14.4+; TCC "System Audio Recording Only"), fallback ScreenCaptureKit loopback ("screen_capture_kit", needs Screen Recording), else "unsupported"; a restart may be required ("Restart Wispr Flow to finish setup") [B][S] |
| **Calendars** (rebuild) | upcoming meetings, titles, attendees | EventKit full-access request, optional (Flow uses Google/Outlook OAuth instead) |
| Screen Recording (optional) | "This lets Flow answer any question about what's on your screen" | only for OCR and the SCK audio fallback; rebuild: requested only on macOS < 14.4 for meeting audio |
| Input Monitoring | not requested separately in Flow; the event tap runs under Accessibility | rebuild: request only if the tap fails without it [U] |

- Revocation is detected while running: "Accessibility Permission Required — Flow needs accessibility access to work properly." / "Microphone Permission Required" [S].
- Helper failures: "Just a moment - Flow is getting ready...", "Flow is having trouble loading/starting" [S].

---

## 16. Menu bar item and app menu

1. **Status item** (template image, tooltip "Wispr Flow"; macOS preferred position seeded to 40). Click opens the menu [B][R]. Menu order [B][S]:
   1. Meetings section: the next/ongoing meetings ("Now", "Today", "Tomorrow", "Join meeting"), "See all upcoming meetings", "Past notes" ▸ recent meetings ("Untitled note"), "See all past notes"; **Start Notetaker**; "Hide next meeting from menu bar" / "Show next meeting in menu bar". With the next-meeting option on, the status item shows the meeting title and a countdown next to the icon (rebuilt every minute) [B][S]
   2. **Open Wispr Flow**
   3. — update status row ("Check for updates..." / progress)
   4. — **Paste last transcript** (shows the paste shortcut; disabled when there is none), then a disabled row previewing the last transcript
   5. — **Shortcuts**, **Microphone ▸** (checkbox per device; unavailable ones disabled), **Languages ▸** (checkbox per language)
   6. — **Help center**, **Talk to support** ⌘/, **Share feedback** (rebuild: Help → docs URL; Report an issue → GitHub)
   7. — **Quit** ⌘Q
2. **App menu bar** when the hub is focused [S]: Wispr Flow (About, Settings, Hide, Quit), File (Close window), Edit (standard + Select All), Dictation (Start dictation, Paste last transcript, Copy last transcript, Words dictated: {{count}}), My Voice (Dictionary words: {{count}}, Snippets created: {{count}}, Add a word to dictionary, Create a new snippet), View, Window, Help (Help center, Talk to support, Share feedback, Shortcuts) [U on exact grouping].

---

## 17. Sounds

Cues for dictation start, dictation stop, hands-free lock (double-tap engaged), paste, notification success/error/alert, and an achievement sound for milestones; dictation cues at full volume, notification cues at half volume; several experimental sound sets, default set used when `selectedSoundFolder` is null [R][B]. Exact files and durations: `ui-reference.md` §8. Rebuild: ship its own start/stop/error cues; obey "Dictation and notification sounds".

---

## 18. Notifications (bar cards) — catalogue for the rebuild

Flow defines 204 notification types [B]. Keep these (copy in `strings.md`):

| Group | Types |
|---|---|
| Mic/audio | `MicDisconnected`, `NewMicDetected`, `MicNotFound`, `MicDeviceUnavailable`, `MicNotReadable`, `MicAccessError`, `MicAccessTimeout`, `NoAudio`, `NoAudioDuringDictation(+Escalated)`, `TranscriptionEmpty`, `NoClamshellBuiltInMic`, `AudioQualityIssue`, `AirPodsWarning`, `MicSwitched`, `SuggestWiredMic`, `DisableMuteMusic` |
| Dictation | `TranscriptionError`, `RawTranscript`, `TranscriptCurrentlyProcessing`, `TranscriptCancelled(+Detailed)`, `DictationDurationWarning`, `DictationMaxDurationReached`, `DictationCancelledOtherShortcut`, `Debounce`, `ProcessingDelayNotification`, `WrongLanguageSetting`, `LanguageNotification`, `VoidDictation`, `DictatingWithWisprFlow` (creator mode) |
| Insert | `PasteFailed`, `PasteBlocked`, `PressEnterCommandPrompt`, `SuggestPasteLastText` |
| Permissions/system | `AccessibilityPermissionRevoked`, `MicrophonePermissionRevoked`, `SecureInputBlockingShortcuts`, `HelperNotReady`, `HelperLoadingError`, `HelperPersistentFailure`, `DatabaseGenericError`, `DatabaseCorruptionError`, `DatabaseStorageFull`, `UpdateError` |
| Learning/tips | `LearnedDictionaryWords`, `SmartFormattingList/Emails/Backtrack/FileTagging` (+ `…Reminder`), `FeatureNotifDictionary/Snippets/Styles`, `SuggestPOPO`, `TypingReminderEnabled/Configure/Muted`, `BarHidden`, `MoveableFlowBarLaunchModal`, `MouseFlowDiscovery` |
| Transforms | `PolishRunningWarning`, `PolishTextNotEditable`, `PolishTextFailed`, `PolishTextNoSelection(+FirstTime)`, `PolishMaxWords`, `PolishTextNoChanges`, `PolishCancelled`, `PolishTimeout`, `PolishEmptyResponse`, `PolishTextboxDetectionFailed`, `FirstTransformCompletedOutsideFlow` |
| Focus mode | `FocusModeActivated/Deactivated/Blocked` (optional) |
| Notetaker | `MeetingRecorderNudgeFirst/SecondNeverTried/SecondUnder5` (meeting-detected prompts), `MeetingRecordingFailedToStart`, `MeetingRecordingConnectionLost`→rewrite, `NotetakerMicMismatch`, `NotetakerMicNoAudioDetected(+Escalated)`, `MeetingStartedByMistake`, `MeetingSummaryReady`, `RecordingStopped`, `MeetingAutoEnded`, `RecordingStoppedSilence`, `LowConfidenceStopPrompt`, `RecordingCheckInCalendarEnd`, `RecordingCheckIn1Hr`, `RecordingCheckInMaxLength`, `MeetingRecorderSwitchPrompt`, `ConferenceSwitchOffer`, `NotetakerScreenShareEducation`, `MeetingNoticeOptOutPrompt`, `MeetingNoticeIgnoredOptOutPrompt`, `MeetingNoticeAutoDisabled`, `MeetingDetectionReEnablePrompt`, `NotetakerUnsupportedLanguageDetected`, `NotetakerAutoHideEnabled/Offer`, `NotetakerAutoStartOptIn`, `NotetakerSetupIdleBlocked`, `LongDictationNotetakerPrompt`, `SuggestNotetaker` |

Drop: everything about trials, billing, teams, referrals, students, incidents/degraded network, cloud sync, HIPAA, Notetaker weekly limits/quota, `MeetingLiveTranscriptUnavailable` (offline transcription is the normal case locally), `NoInternet`, `FailedSignIn`, `SignedOut`, insights marketing. Notification categories are user-filterable (Suggestions, Announcements, Milestones) [S].

---

## 19. Data model and preferences

### 19.1 Tables (from `migrations/`) [R]
- `History`: `transcriptEntityId` PK, `asrText`, `formattedText`, `editedText`, `timestamp`, `audio` BLOB, `screenshot` BLOB, `additionalContext` JSON, `status`, `app`, `url`, `language`, `duration`, `numWords`, `isArchived`, plus later analytics columns (latencies, e2e, edit distance, correction counts, timezone offset).
- `Dictionary`: `phrase` (unique), `replacement`, `replacementHtml`, `isSnippet`, `manuallyAdded`, `isStarred`, `source`, `frequencyUsed`, `frequencySeen`, `lastUsed`, `lastSeen`.
- `Notes` (+ note versions, images), `Polish` (Transform runs: initial/polished text, word counts, app, status, undone, instruction, prompt name, shortcut key).
- Meetings (kept, local): `Meetings` (+ `MeetingVersions`; title, start/end, recorded ms, calendar event id/occurrence, participant names, speaker map, transcript, notes, summary, refine status, audio location), `CalendarEvents` (local mirror of EventKit), `Todos` (action items; sort order, completed/archived), `Folders` + `FolderMeetings` (local organisation only), notetaker chat tables ("Ask anything" threads).
- Drop: shared notes, folder grants/members/sharing, notifications sync, imports state (Granola/Otter), instruct history, user context.

### 19.2 User preferences (defaults, Mac) [B]
`shortcuts` (§3.1), `selectedLanguages = [locale]`, `enableSounds = true`, `shouldMuteAudio = false`, `shouldPauseAudio = false`, `shouldAutoLearnWords = true`, `useAxContext = true`, `ideFileTagging = true`, `cursorIdeIntegration = false`, `openAtLogin = true`, `hideAppInDock = false`, `hideFlowBarPermanently = false`, `statusDockEdge = "bottom"`, `theme = "light"`, `defaultTranscriptionFormat = "Apply AI formatting"`, `appTranscriptionFormats = []`, `aiFormatting = true`, `autoCleanup.level = Light`, `styleDetectionEnabled = true`, `personalizationStyles = null`, `commandModeEnabled = false`, `pressEnterCommandEnabled = false`, `stackedMessagesEnabled = false`, `focusModeEnabled = false`, `creatorMode = false`, `polishEnabled = true`, `polishAutoPaste = true`, `autoPolishAfterDictation = {active: false, promptName: "polish"}`, `processingDelayNotificationEnabled = true`, `localDataPolicy = StoreNormally`, `overrideAudioDeviceId = null`, `rankedAudioDevices = []`, `scratchpadInFlowBar = false`, `dictionarySort = Newest`, `modifierShortcut = Tab` (role unclear [U]).

## 20. Meeting Notetaker

Wispr Flow's Notetaker records meetings **without a bot joining the call**: it captures the user's microphone and the Mac's system audio, shows a live transcript, and writes notes, a summary and action items when the call ends ("Transcribes quietly in the background, then writes notes and action items when the call ends. Stop it any time"; "Nothing joins the call.") [S]. In Flow, transcription, speaker labelling and summaries run on Wispr's servers; **in the rebuild every stage is local** (§20.12, `local-models.md`). Visuals: `ui-reference.md`; copy: `strings.md`.

### 20.1 Surfaces
| Surface | What it shows [S][B] |
|---|---|
| **Meeting-detected prompt** (card above the Flow Bar) | "Transcribe this meeting with Wispr?" / "Want notes for this meeting?" with "Yes, take notes for me" / "Yes, transcribe" / "Another time" / "Maybe later"; later variants "Wispr Notetaker can take notes on this call", "Want the action items from this meeting?" ("Take notes for me", "Get action items", "Not this one", "I'll take my own", "No thanks") |
| **Calendar reminder pill** (above the bar) | "Meeting starting" / "Meeting detected", countdown "In {{minutes}} min" / "Now", **"Join + Start"**, menu: "Start Notetaker", "Start Notetaker automatically", "Snooze for 2 min", "Notification settings"; stacked when several ("{{count}} meeting reminders"), "Dismiss all reminders"; "Starts automatically when the countdown ends" |
| **Flow Bar, meeting mode** | Green-bordered pill with a live word count while recording; "Listening" recording pill; "Wrapping up…" when stopping; tooltips "Take notes", "Show Notepad", "Stop Notetaker", "Start note triple-tap {{keys}}" |
| **Notepad** (`meeting_recorder` window, docked right at 30 % of the screen width) | Tabs Notes · Transcript · Summary · Tasks · Docs · Brief; footer with "Ask anything", Start/Stop/Resume and a timer; header "Home", "All notes", "Split screen with meeting" |
| **Hub › Notetaker** | Meetings library (home widget, list, search, folders), meeting detail, **My Tasks** |
| **Menu bar** | Next meeting next to the icon (≤ 30 chars): "Title • in N min" (within 10 min), "Title • 25m left" (in a meeting), "Free until 3pm" / "Free from…" / "Free after…"; Meetings section in the menu (§16); exact rules in `ui-reference.md` §10 |

### 20.2 Starting a recording
1. **From a prompt** (detection, §20.3) or **calendar reminder** (§20.10): one click starts; "Join + Start" also opens the meeting link.
2. **Shortcut** ⌥M (`open_meeting_recorder`) or **triple-tap** of the dictation key; tray "Start Notetaker"; bar "Take notes"; hub "Start Notetaker" / "New note". The shortcut follows a decision ladder [B]:

   | Situation | Action |
   |---|---|
   | Notetaker disabled/blocked | nothing / open the Notetaker page |
   | A recording is already running | "Switch to another meeting?" / "Start a new meeting note?" / "Switch to \"{{name}}\"?" prompt |
   | No meeting is active | open the Notepad and start a new note (manual recording) |
   | Exactly one active meeting (detected or on the calendar now) | record it; if it is a calendar meeting not yet joined, open its link and record |
   | Several active meetings | open a drawer to pick one |

3. **Auto-start** (off by default, needs detection): starts as soon as a meeting is detected or the reminder countdown ends; an opt-in prompt offers it ("Want Notetaker to start automatically?").
4. **Gates**: permissions incomplete → "Complete setup to start Notetaker" / "Notetaker isn't recording yet — Finish setup to start recording your meeting."; first use may ask to "Obtain consent to start Notetaker" [S]. Starting the Notetaker while a dictation runs ends the dictation first [U].

### 20.3 Meeting detection
Setting "Automatically detect any call": **Notify me** (default) / **Do nothing** [S]. Flow combines several signals and keeps "authority" bookkeeping so a single noisy signal neither starts nor stops a recording [B, `[MeetingAutoDetect]` log lines]:

| Signal | How Flow gets it | Rebuild |
|---|---|---|
| **Microphone holders** | Helper `MicrophoneHoldersMonitor`: which processes hold audio input (sources `process_api`, `audio_session`, `running_apps_heuristic`); "mic-holder edges" start candidates | Core Audio process objects (`kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunningInput`, macOS 14+) with `kAudioDevicePropertyDeviceIsRunningSomewhere` as a cheap pre-check; map PID → bundle id |
| **Conferencing app** | Native apps: Zoom `us.zoom.xos`, Teams `com.microsoft.teams`/`teams2`, Slack huddles `com.tinyspeck.slackmacgap`, Webex, Discord, WhatsApp; platform enum `zoom`, `teams`, `slack`, `google_meet` | Same bundle-id table (data); FaceTime added [U] |
| **Browser meetings** | AX scan of the browser tab strip/window (`MeetingTabScanner`, `TabStripMonitor`: Meet codes, title digests) in Arc, Atlas, Brave, Chrome, Comet, Dia, Edge, Firefox, Opera, Safari, Vivaldi, Zen; URLs `meet.google.com`, `teams.microsoft.com`, `teams.live.com`, `app.zoom.us`, `whereby.com` | AX window/tab title + URL read of the browser that holds the mic |
| **Conference UI** | `ConferenceWindowMonitor` / conference end-state read: whether the call window is live or shows "call ended"; leave-button click witness in browsers | Optional refinement; window-gone + mic-released is enough for v1 |
| **Calendar** | Event at "now" with a matching conference URL → identity, title, attendees | EventKit (§20.10) |
| **Far-end audio** | System output going quiet | Level on the system-audio tap |

Prompt hygiene [S][B]: closing or ignoring several prompts in a row offers "Turn off meeting notifications?"; repeated non-use auto-disables them ("Meeting notifications turned off"); later "Never miss meeting notes" offers to re-enable. A meeting that is already being recorded clears its calendar reminder.

### 20.4 Recording
1. **Two sources**, kept as separate channels: the **microphone** (the user, "You") and **system audio** (other participants, "Them"). Live labels use exactly this split ("You" / "Them") [S].
2. **System audio capture** [B]: Core Audio **process tap** (`process_tap`, macOS 14.4+; "System Audio Recording Only" permission), falling back to **ScreenCaptureKit** loopback (`screen_capture_kit`, Screen Recording permission); otherwise unsupported. If system audio is off: banner "System audio turned off — Turn on system audio to capture what others say in your meeting." [S].
3. **Microphone**: "Notetaker always uses {{micName}}" (system/meeting mic, language auto-detect regardless of dictation languages); mismatch warning when the meeting app uses another mic ("We might not be capturing your words"); "No sound from {{micLabel}} for the past 3 minutes…" escalating to "Still there? Notetaker isn't hearing anything" [S].
4. **Lifecycle notices** [S]: "Couldn't start recording — We couldn't capture any audio, so nothing was saved."; "Started by mistake? Only a few words were captured. Keep this meeting or discard it."; "Stopped meeting — No audio was recorded."; check-ins "Still taking notes" (after 1 h and at the calendar end time), "Approaching time limit" (before the maximum length; default 2 h); "Notetaker stopping" / "Notetaker stopped".
5. **Ending** [B]: manual stop (bar, Notepad, tray, Esc does not stop a meeting [U]); **auto-end** ("Stop Notetaker when a call ends", default on) when the conference app releases the mic / its call window ends / the far end goes quiet, after a grace period that is cancelled if the same meeting returns; a low-confidence end asks "Stop taking notes?" (Keep / Stop; expiry keeps recording); joining a different call offers "Looks like a new meeting. Switch?"; fast user switching or sleep finalises immediately.
6. Audio is written to disk continuously (Opus in workers in Flow) so a crash or quit loses at most a few seconds [B]. Rebuild: write each channel as 16 kHz mono segments (e.g. 30 s CAF/FLAC or AAC) under `Audio/Meetings/<id>/`.
7. **Screen-share privacy**: "Don't show Notepad and Flow Bar in screen capture" (window sharing type none) and an education card "Your Flow Bar and Notepad show up in screen shares and screenshots." [S].

### 20.5 Live transcript
- Drawer with **Transcript** and **Chat** tabs; streaming text grouped in speaker blocks "You"/"Them"; "Search transcript…", "Copy transcript", "Toggle transcript", "Minimize" [S].
- Empty state: "Welcome to Notetaker!" / "Try saying “Hi Notetaker”"; hint "After the meeting, Wispr will improve the transcript & label speakers" [S].
- "Show live transcript" can be turned off (recording still happens) [S].
- Rebuild: live transcript from the local streaming ASR on each channel (VAD-segmented, a few seconds behind); post-meeting refine replaces it (§20.7).

### 20.6 Notepad (meeting notes window)
- A floating notes editor bound to the meeting: "Write your notes here. We'll make a separate summary at the end."; the user can dictate into it ("Hold Fn to dictate") [S].
- Section pills: **Summary**, **My Notes**, **Action Items**, Artifacts (chat outputs), Brief (pre-meeting brief from connected tools — drop) [S].
- "Split screen with meeting" arranges the meeting window left and the Notepad right (needs Accessibility: "Allow Accessibility access for Wispr Flow to arrange windows.") [S].
- Opens automatically on start (setting, default on); "Hide Notepad when Notetaker starts?" is offered to users who keep closing it [S].
- Window controls: Close, Minimize, Maximize, Restore, Full Screen [S].

### 20.7 After the meeting
1. **Processing stages** shown in order: "Processing audio..." → "Transcribing audio..." → "Refining content..." → "Summarizing meeting..." → "Generating summary..." [S].
2. **Refine pass** [S][B]: a better full-length transcription, **speaker diarization** of the "Them" channel, speaker naming from the meeting UI's participant list (AX) and calendar attendees ("Auto-detect speaker names"), and room handling (several voices from one conference-room mic: "Who is {{voice}} in {{room}}?", "Combine all voices", "Separate {{count}} voices").
3. **Speaker editing**: click a speaker → search people / add "{{name}}" → "Update only this block" or "Update everywhere" [S].
4. **Summary** ("Enhanced Summary", "{{minutes}} min read") merges the transcript with the user's own notes; regenerate with "Generate summary" / "Update Summary" when new audio arrived ("New recording since this summary."); too short → "The meeting was too short to summarize."; no audio → "No transcript or audio available for a summary" [S]. Notification "Your summary is ready! From {{meeting}}" and celebration copy ("{{duration}} meeting compressed to a 2 min read.") [S].
5. **Rebuild summary template** (the user's requested outputs): Title (from calendar or generated) · Summary (short paragraphs) · **Key decisions** · **Action items** (owner, due date if said → become Tasks) · **Follow-ups / open questions** · Notes (the user's notes, kept verbatim) · Transcript. Generated by the local LLM with chunked map-reduce for long meetings (`local-models.md`).
6. **Ask anything** per meeting (chat over transcript + notes) with presets "What did I miss?", "Write a follow-up email", "Identify blind spots", "Make notes longer", "Make me sound smart", "Suggest questions"; answers can create artifacts or update notes [S]. Rebuild: local LLM over the meeting's transcript (retrieval by chunk when it exceeds the context window).

### 20.8 Meetings library and Tasks
- **Hub › Notetaker**: home widget (upcoming + recent, "See all", "Show Notetaker"), meetings list grouped by date with search, **folders** (local organisation; sharing drops), meeting detail (summary, notes, action items, transcript, audio) [S].
- **My Tasks**: every action item from every meeting; "Add action item", complete, "Mark all as completed", "Archive all", "View all in Tasks" [S].
- **Export** (rebuild): copy summary/notes/transcript as Markdown; save `.md`; share sheet (Apple Notes, Mail); copy action items as a checklist. Flow's share links and auto-share to attendees drop.
- Delete a meeting (audio + transcript + notes); retention setting (§13.5).

### 20.9 Privacy (rebuild)
- Audio, transcripts, notes and summaries never leave the Mac.
- **Consent**: optional consent message posted into the meeting chat (Flow types it into Zoom/Meet/Teams chat via AX, falling back to a pasteboard paste) and a reminder in the prompt to ask for consent [B][S]; the default text is rewritten without the Wispr brand.
- Visible recording state: green bar + menu bar indicator while recording.
- Options: keep meeting audio (default keep for N days [U]) or delete audio after the transcript is refined; transcript retention (§13.5); exclude the Notepad and bar from screen capture.

### 20.10 Calendar integration
- Flow connects Google Calendar / Outlook via OAuth (server-side) to show upcoming meetings, remind ("Notify before scheduled meetings start": Never / Right before (15 s) / 1 min / 2 min), offer "Join + Start", title notes, name speakers, add notices to events [S]. Rebuild: **EventKit** (local calendars, including Google/Exchange accounts added to macOS), read-only: titles, times, attendees, conference link extracted from URL/location/notes (Zoom, Meet, Teams, Webex patterns). Calendar notices and auto-share drop.

### 20.11 Notetaker preferences (defaults) [B]
`autoDetectMeetingsEnabled = true`, `notetakerAutoStartEnabled = false`, `notetakerAutoEndEnabled = true`, `notetakerMaxRecordingLength = 2hr` (options 30min/1hr/2hr/3hr; 4hr/6hr internal), `notetakerLongMeetingCheckInEnabled = true`, `notetakerLiveTranscriptEnabled = true`, `notetakerAttributeNamesEnabled = true`, `notetakerAutoDetectParticipantNamesEnabled = true`, `notetakerSplitScreenJoinEnabled = false`, `notetakerOpenWindowOnRecord = true`, `notetakerMenuBarMeetingEnabled = true`, `notetakerTripleTapShortcutEnabled = true`, `notetakerCalendarNotificationsEnabled = true`, `notetakerConsentChatEnabled = unset`, `hideMeetingRecorderInScreenShare = false`, `notetakerTranscriptRetention = NeverDelete`.

### 20.12 Local pipeline (rebuild)
```
mic ────► echo cancel (ref: system) ─► VAD ─► streaming ASR ─► "You"  ─┐
                                                                         ├─► live transcript (Notepad) ─► SQLite + audio files
system tap ────────────────────────────► VAD ─► streaming ASR ─► "Them" ─┘
stop ─► refine: full-pass ASR (larger model optional) + diarization of "Them" (+ names from AX/EventKit)
     ─► LLM map-reduce: summary · key decisions · action items (→ Tasks) · follow-ups · title
```
Model choices, RAM/latency budgets and the CLT build path: `local-models.md`. Library choices (system-audio tap code, diarization, detection patterns): `oss-survey.md`.

---

## 21. Cloud, telemetry, account (replace or drop)

| Today | Rebuild |
|---|---|
| Streaming ASR (`api.wisprflow.ai`, gRPC/WebSocket, Baseten/Modal), `/llm/asr*` | **Local** speech engine |
| `/llm/formatting`, `/llm/format_non_english`, `/llm/detect_formality`, `/llm/check_sensibility`, `/llm/classify_intent` | **Local** rules + small LLM |
| `/llm/polish_text`, `/llm/command_mode*`, `/llm/instruct_mode`, `/llm/voice_profile` | **Local** LLM |
| `/llm/extract_asr_words`, `/llm/extract_edited_words` (auto-learn) | **Local** diff heuristics |
| Notetaker transcription, refine, speaker labelling, summaries, "Ask anything" chat (server jobs; meeting audio upload) | **Local** ASR + diarization + LLM (§20.12) |
| Google/Outlook calendar OAuth, calendar notices | **EventKit** read-only; notices drop |
| `/llm/ocr` | drop (optional Vision OCR later) |
| `/history/upload`, `/history/stats*`, cloud sync, notes/meetings sync, dictionary/snippet sync, share links, auto-share, data export | drop (local export instead) |
| Accounts (WorkOS auth, Supabase, magic links, SSO), subscription (Stripe), trials, word limits and Notetaker weekly limits, teams/orgs, admin policies, referrals, students, LinkedIn | drop |
| Telemetry: PostHog (`us.i.posthog.com`, `ph.wisprflow.ai`), Sentry (Electron + Swift helper), Datadog logs, Segment, feature flags (`/sdk/feature-flags`), keypress counters | drop — no telemetry; local `os.Logger` only |
| Pre-meeting briefs and connectors, Granola/Otter imports, MCP/extensions | drop (local MCP server is a possible later add-on, as in Super Paste) |
| Mobile/BLE mic ring, Jabra, web answer engine | drop |

The only network access the rebuild makes is **model download** (and optional update checks), both user-initiated or user-enabled.

---

## 22. Rebuild plan

### 22.1 Feature coverage

| Requested feature | Where specified |
|---|---|
| Transcriber: push-to-talk (hold Fn), hands-free (Fn+Space / double-tap), live level, 20-min sessions | §2, §3, §4, §5 |
| Autocorrect / cleanup: fillers, punctuation, capitalisation, self-corrections ("scratch that", "no wait"), lists, emails, numbers, cleanup level | §8.1–§8.3 |
| Per-app tone/style (personal, work, email, other) and per-app formatting | §6.2, §8.4 |
| Personal dictionary: custom words, replacements (misspelling → spelling), learned corrections (auto-add), starring | §8.5 |
| Snippets (spoken trigger → expansion) | §8.6 |
| Commands: "press enter", file tagging, stacked messages; Command mode (edit selected text by voice); Transforms | §8.3, §10 |
| Multilingual (multi-select + auto-detect, Hinglish) | §8.7 |
| History (search, copy, retry, undo AI edit, audio), Insights, Scratchpad | §11 |
| Meeting Notetaker: detection pop-up, one-click record, mic + system audio, live transcript, speakers, notes, summary, decisions, action items, follow-ups, library, Tasks, export, privacy, calendar | §20 |
| Flow Bar, menu bar, hub, settings, onboarding, permissions, notifications, sounds | §5, §12–§18 |

### 22.2 SwiftPM module plan

Swift 6 toolchain (Swift 5 language mode like the sister apps), macOS 14+ (Apple-only engines and features gated by availability: SpeechAnalyzer/Foundation Models on macOS 26, process taps on 14.4+), `swift build` with Command Line Tools only, app bundle assembled by a script. Same rules as Super Paste: **feature modules depend only on the Core contracts module and never import each other**; they talk through a `Services` registry; each protocol has one owning module whose `<Module>Module.install()` registers it; UI and services are `@MainActor`, heavy work (audio, inference, SQLite) runs off the main actor and hops back. Names are placeholders until the product name is chosen; they avoid clashing with Apple framework names such as `StoreKit` and `Speech`.

| Target | Kind | Responsibility | Spec § |
|---|---|---|---|
| `DictationCore` | library | Contracts and shared types only: dictation state/modes/outcomes, `Shortcut` codec + defaults + validation tables, `AppContext`/`AppType` + app lists (data), `Transcript`/`Segment`/`Speaker`, `HistoryEntry`, `DictionaryEntry`/`Snippet`, `StyleSettings`, `CleanupLevel`, `Meeting`/`MeetingChannel`/`Task`/`CalendarEvent`; service protocols (`AudioCapturing`, `SystemAudioCapturing`, `SpeechEngine`, `VoiceActivityDetector`, `EchoCanceller`, `Diarizer`, `TextFormatter`, `MeetingSummarizer`, `ModelStore`, `ContextReading`, `TextInserting`, `HistoryStoring`, `MeetingStoring`, `HotkeyMonitoring`, `MeetingDetecting`, `CalendarProviding`, `NotificationPresenting`, `PermissionChecking`); `Services` registry; typed Defaults keys (§19.2, §20.11); design tokens; paths; logging | 2, 3, 6.2, 19, 20.11 |
| `HotkeyKit` | library | CGEventTap (+ IOHID Caps Lock), Fn-keyboard detection, chord matcher (§3.3), triple-tap, secure-input monitor, shortcut recorder control | 3 |
| `CaptureKit` | library | Microphone: AVAudioEngine at 16 kHz mono, level meter, device list/ranking/override, clamshell/AirPods/virtual-device rules, no-audio detection, mute/pause media, cue sounds. **System audio**: Core Audio process tap (macOS 14.4+) with ScreenCaptureKit fallback; per-channel segment writer for meetings | 4, 17, 20.4 |
| `TranscribeKit` | library | VAD, echo cancellation of speaker bleed in the mic channel (system channel as reference), `SpeechEngine` implementations (dictation: low-latency engine; meetings: streaming chunked engine + post-meeting refine pass), language selection/detection, vocabulary biasing from the Dictionary, hallucination guards, `Diarizer` implementation (speaker segmentation + embeddings + clustering) | 7, 8.7, 20.5, 20.7; local-models |
| `FormatKit` | library | Deterministic text pipeline (backtrack, fillers, lists, numbers, casing per Style and format, dictionary replacements, snippet expansion, "press enter", file tagging); `TextFormatter` LLM engines (llama.cpp; Foundation Models on macOS 26) with guardrails/fallback; Transforms; Command mode; `MeetingSummarizer` (meeting summary, decisions, action items, follow-ups, titles, "Ask anything") with chunked map-reduce | 8, 10, 20.7; local-models |
| `ModelKit` | library | Model catalogue (speech, VAD, diarization, LLM), download with progress/resume/SHA-256, storage under `Application Support/<App>/Models`, RAM-based presets, packs (Dictation / Meetings), delete/redownload, warm-up and unload policy | local-models §5 |
| `InsertKit` | library | AX context reader (focused element, caret neighbourhood, selection, textbox ≤ 500 chars, app/URL/window), app-type classifier, pasteboard paste (lazy provider + ⌘V + restore + transient markers), verification, edit observation → auto-learn, simulated Return, AX posting of the consent message into meeting chats | 6, 9, 20.9 |
| `MeetingKit` | library | `MeetingDetecting` (mic-holder process monitor, conferencing bundle ids, browser tab/URL via AX, end detection with grace + low-confidence prompt, switch offer, prompt fatigue rules), meeting session state machine (start/stop/auto-end/check-ins/max length/started-by-mistake), orchestration of capture → live transcription → refine → diarization → summary → tasks, speaker naming from AX participant lists and attendees | 20.2–20.7 |
| `CalendarKit` | library | `CalendarProviding` via EventKit (read-only): upcoming meetings, conference-link extraction, reminder scheduling (Never / 15 s / 1 / 2 min), next-meeting title + countdown for the menu bar | 20.10, 16 |
| `HistoryStore` | library | SQLite (system `SQLite3`): History, Dictionary/Snippets, Notes, Transforms, Meetings (+ versions), Tasks, Folders, CalendarEvents mirror, chat threads; FTS5 search over transcripts/notes/summaries; retention policies (dictation store/24 h/never; meeting transcripts N days; audio pruning); import/export (JSON/CSV/Markdown) | 11, 19.1, 20.8 |
| `BarKit` | library | Flow Bar `NSPanel` (non-activating, all spaces, above full-screen), dictation states, meeting mode (green border, word count), waveform, hands-free buttons, drag-to-edge docking, right-click menu, notification cards, meeting-detected prompt, calendar reminder pills, typing reminder | 5, 18, 20.1 |
| `NotepadKit` | library | Notepad window: notes editor with dictation, live transcript drawer (search/copy), summary / My Notes / Action Items sections, Ask anything chat, speaker editing, split-screen arrangement, screen-capture exclusion | 20.5–20.7 |
| `HubKit` | library | Main window: sidebar, Home/History, Dictionary, Snippets, Style (+ Auto cleanup), Transforms, Scratchpad (notes + floating window), Notetaker library, meeting detail, My Tasks, folders, Insights | 11, 12, 20.8 |
| `SettingsKit` | library | Settings panes (General, System, Notetaker, Models, Vibe coding, Experimental, Data and Privacy), Shortcuts/Microphone/Languages dialogs, onboarding (dictation and Notetaker branches, model download), permission screens (Microphone, Accessibility, System Audio, Calendars) + drag-icon guide, open at login (`SMAppService`) | 13, 14, 15 |
| `UpdateKit` | library | GitHub Releases updater (as in the sister apps) | 1.5 |
| `DictationApp` | executable | App shell, launch sequence and module install order, dictation coordinator (capture → transcribe → format → insert → history), status item (meetings section, next-meeting countdown), app menu, URL scheme | 1, 2, 16 |
| `DictationSelfTest` | executable | Headless checks (`swift run DictationSelfTest`; CLT has no XCTest): shortcut matcher scenarios, validation, app-type classifier, formatting-rule golden tests, snippet/dictionary application, store migrations, meeting detector state machine on recorded signal traces, conference-link extraction, summary JSON schema validation, model checksum/download resume, engine smoke tests on bundled WAVs when models are present | all |
| External engines | dependencies | **FluidAudio** (SwiftPM package, pinned `exact:`; Parakeet ASR, Silero VAD, diarization, Core ML), **whisper.cpp** and **llama.cpp** as SwiftPM `binaryTarget` XCFrameworks from their GitHub releases (Metal embedded, no `metal` compiler needed), each wrapped only inside `TranscribeKit` / `FormatKit` behind the Core protocols; Apple `SpeechAnalyzer` / `FoundationModels` behind `#if canImport` + availability — pins and licences in `oss-survey.md` §8, model choices in `local-models.md` | — |

Launch order [U, mirrors the sister apps]: HistoryStore → ModelKit → CaptureKit → TranscribeKit (warm the dictation model in background) → FormatKit → InsertKit → HotkeyKit → CalendarKit → MeetingKit (starts detection when enabled) → BarKit → NotepadKit → HubKit → SettingsKit → UpdateKit; then the status item, the shortcuts, and onboarding until it is completed.

### 22.3 Features to drop
1. Accounts, sign-in, subscriptions, trials, word and note limits, teams/orgs/admin policies, referrals, student plans, LinkedIn, email signature marketing.
2. All telemetry, crash reporting, remote feature flags and remote config.
3. Cloud sync of history, notes, meetings, dictionary and snippets; share links, auto-share to attendees, calendar notices; server data export; HIPAA/BAA.
4. Pre-meeting briefs/connectors, Granola/Otter imports, extensions/MCP (possible later local add-on).
5. Mobile hand-off, BLE mic ring, Jabra integration, web answer engine, screen OCR.
6. Windows code paths.

### 22.4 Gaps and open questions

| # | Gap | Proposed decision |
|---|---|---|
| 1 | Exact cloud formatting rules (filler list, number/date formatting, list heuristics) are server-side | Define our own rule set + golden tests; LLM only for Light/Medium/High cleanup |
| 2 | Click vs. press-and-hold on the idle Flow Bar | Click = start hands-free; press-and-hold = push-to-talk [U] |
| 3 | Style default per category | Formal for Email/Work/Other, Casual for Personal [U] |
| 4 | Dictionary context cap | 100 entries, starred first [U] |
| 5 | Paste failure timeout and clipboard-restore delay | ~600 ms failure timeout, restore after 500 ms [U] |
| 6 | `modifierShortcut` (= Tab on Mac) purpose | Not needed unless file tagging requires it |
| 7 | Whether the rebuild shows a Dock icon by default | Follow Flow (Dock icon on, toggle in System) — or agent app like the sister apps; owner decision |
| 8 | Fn key swallowing vs. the macOS Globe-key action ("Press 🌐 to show Emoji") | Detect `com.apple.HIToolbox AppleFnUsageType`; onboarding tells the user to set it to "Do Nothing" if Fn is chosen [U] |
| 9 | Instruct mode | After Command mode ships |
| 10 | Meeting auto-end thresholds (grace period, quiet duration) are spread over Flow's detector and not recovered as constants | 30 s grace after the conference process stops input, 2 min far-end silence → low-confidence prompt [U]; tune with recorded traces in the self-test |
| 11 | Meeting audio retention default | Keep 30 days, then delete audio but keep transcript and notes [U]; owner decision |
| 12 | Diarization quality on a single mixed "Them" channel (many remote speakers) | Accept clusters + manual naming; names from AX participant lists where the app exposes them |
| 13 | Concurrency: dictating during a meeting (two ASR consumers, one GPU) | Dictation has priority; meeting live transcription pauses/queues while a dictation runs (`local-models.md`) |
| 14 | Visual/UI values | Owned by `ui-reference.md`; no visual decisions are made here |
