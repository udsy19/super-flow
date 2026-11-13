# Privacy and permissions (Store edition)

No account, no analytics, no telemetry. Audio, transcripts and notes stay in the app container. The only network traffic is
model downloads from huggingface.co after the user agrees (no update checks in the Store build).

| Permission | Used for | Store mechanism | Sandbox result (test-results.md) |
|---|---|---|---|
| Microphone (`NSMicrophoneUsageDescription`, `device.audio-input` + `device.microphone`) | dictation, meeting "You" track | `AVCaptureDevice.requestAccess`, AVAudioEngine | prompt fires; after Allow the engine starts |
| System audio recording (`NSAudioCaptureUsageDescription`) | meeting "Them" track | Core Audio process tap (`AudioHardwareCreateProcessTap`, macOS 14.4+), private aggregate device | tap + aggregate created in the sandbox; TCC `kTCCServiceAudioCapture` prompt fires; no extra entitlement needed |
| Accessibility (post events) | pasting with ⌘V, Return/Tab after insert, ⌘C for transforms | `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` | no prompt appears sandboxed (`deny mach-lookup com.apple.universalaccessAuthWarn`); the app opens System Settings › Accessibility for the user to add it. Granted path: needs human run |
| Input Monitoring | Fn / shortcut push-to-talk (listen-only CGEventTap) | `IOHIDRequestAccess` / `CGRequestListenEventAccess` | listen-only tap object is created; request returns false without a prompt; app opens System Settings › Input Monitoring. Granted path: needs human run |
| Calendars (`NSCalendarsFullAccessUsageDescription`, `personal-information.calendars`) | meeting titles/attendees, reminders | EventKit `requestFullAccessToEvents` | status readable; prompt path unchanged from direct (needs human run) |
| User-selected files | meeting export, data import | NSSavePanel / NSOpenPanel | – |

Not available sandboxed, gated in the Store build:
- AX inspection of other apps (reading the focused field, text around the cursor for "context awareness", browser window titles for
  web-meeting detection, AX value write insertion). The code paths check AX trust and return empty, so the features degrade:
  no surrounding-text context, no secure-field detection via AX (Secure Event Input is still honoured), browser meetings not auto-detected.
- Reading `com.apple.HIToolbox` (Globe-key usage hint) — returns nothing; the hint is not shown.

Recording consent and indicator (2.5.14): dictation records only while the key is held / hands-free is on, and the Flow Bar shows the
listening state on screen the whole time. Meetings never record without the user answering the meeting prompt ("a detected meeting
always asks", behaviour.md §20) or pressing record; the Flow Bar shows the recording phase and timer during the meeting, and macOS
shows its own microphone / audio-recording indicator.

TCC grants do not transfer between the direct and Store editions (different bundle ids); users grant again.
