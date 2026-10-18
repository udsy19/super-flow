# Wispr Flow 1.6.1147 — English UI string table (reference for the rebuild)

Every user-visible English string found in the installed app (`/Applications/Wispr Flow.app`, version 1.6.1147, Electron), grouped by the screen it appears on. Companion to `behaviour.md` (what each screen does) and `ui-reference.md` (how it looks). The rebuild reimplements the behaviour with its own wording. It copies no code or assets.

**Sources**

| Tag | Source |
|---|---|
| **[R] i18n** | i18next resources bundled into `Contents/Resources/app.asar` → `.webpack/renderer/hub/index.js`, webpack module map `./en/<namespace>.json`. Seven English namespaces: `menus` (56 keys), `settings` (1101), `onboarding` (930), `notifications` (853), `insights` (368), `hub` (2818), `emails` (2) — 6128 keys. The same English JSON is compiled into every renderer window, and the main process reads `menus` for the tray and app menus. Other languages are lazy-loaded chunks per namespace. |
| **[B-main]** | English literals hard-coded in the main process `.webpack/main/index.js`: system dialogs, window titles, in-app announcement cards, import parser errors. |
| **[B-renderer]** | Literals hard-coded in renderer bundles (`status`, `hub`, `scratchpad`, `contextMenu`) that do not go through `t()`. |
| **[B-native]** | The bundled Swift helper `Contents/Resources/swift-helper-app-dist/Wispr Flow.app` (`LSUIElement`), its `MainMenu.nib`, and `Helpers/FlowPermissionGuide.app`. |
| **[R-plist]** | `Info.plist` usage descriptions. |

Call sites: the keys used by each small window were found by scanning its bundle with the embedded JSON removed. `renderer/status/index.js` (the flow bar) references 177 keys, `contextMenu` 114, `scratchpad` 122, `feature_tour` 32, `accessibility_drop` 8 and `overlay` 5. The hub window references the rest. Screen grouping beyond that comes from key prefixes and was hand-checked.

**How to read the tables**

- Strings are copied verbatim. `\n` marks a line break in the source.
- Exception: the name of a third-party AI chat product is replaced by `[AI chat app]` (and `[ai-chat]` inside key names). The rebuild uses generic wording there anyway.
- i18next syntax:
  - `{{name}}` is a placeholder. `{{count, number}}` is a locale-formatted number.
  - `_one` / `_other` key suffixes are plural forms chosen by `count`.
  - `<1>…</1>`, `<bold>`, `<shortcut></shortcut>`, `<keys></keys>`, `<pill>`, `<display>` and similar are `Trans` component slots. The UI fills them with styled spans, keycaps or icons.
- Values that contain tags, backticks, or leading/trailing spaces are shown as code spans so they render exactly. A leading or trailing space matters: those strings are concatenated with a keycap or another fragment.
- **NS** column: `men` menus, `set` settings, `onb` onboarding, `ntf` notifications, `ins` insights, `hub` hub, `eml` emails.
- **Rebuild** column:
  - `reuse`: relevant to the rebuild (local dictation plus the local meeting Notetaker). Keep short labels. Rewrite long prose in our own words. Swap the brand ("Wispr Flow", "Flow", "Flow Bar", "Flow Hub" → the rebuild's name, which is not decided yet). A brand swap alone does not make a row `rewrite`.
  - `rewrite`: the screen stays, but the wording assumes a server, an account, cloud storage, other devices or an organisation, and must change for a local-only app.
  - `drop`: the row belongs to a dropped feature (teams and org policies, note sharing and link visibility, auto-share, Granola/Otter imports, HIPAA, cloud sync, billing and quotas, Windows-only, and so on) even though its screen stays.
- Flags were first assigned by rule, then hand-checked. Keys mentioning team/org/department/shared/pending approval/sync, grants/members/visibility/auto-share, weekly limits, or Windows-only behaviour, are `drop`. Values mentioning servers, cloud, accounts, upgrades or organisations are `rewrite`. In the Notetaker tables, rows that name Google/Outlook/iCloud calendar sign-in, Slack/Notion/Linear connectors, uploads, offline mode, email or shared notes are also `rewrite`. The calendar becomes EventKit, reports and feedback become local, and transcription runs on-device.

**Totals**

| | Count |
|---|---|
| i18n keys in the 7 English namespaces | 6128 |
| Same key and same value exported by two namespaces (listed once) | 47 |
| Listed verbatim in Part A (screens the rebuild keeps: dictation and the local Notetaker) | 3819 |
| Summarised in "Dropped domains" (whole features the rebuild does not have) | 2262 |
| Hard-coded strings in Part B (about 100 table rows; the testing-only and marketing tables are summarised) | — |

**Contents**

- Part A — i18n strings by screen: flow bar and its pop-overs · menu bar and app menus · onboarding (chrome, welcome, about you, Notetaker branch, privacy, permissions, microphone test, shortcut, language, try-it-yourself, personalize, speed) · permissions recovery · hub (shell, history, dictionary, snippets, bulk import, style, notes, scratchpad, transforms/command/instruct) · Notetaker (bar meeting pill and prompts, setup gate and tour, meeting window and notepad, live transcript and speakers, summaries, My Tasks, meetings library, folders, calendar, notifications) · settings (sidebar, General, Shortcuts, Microphone, Languages, Notetaker, System, Data and Privacy, Experimental, Vibe coding) · notifications and toasts (microphone, dictation, tips, errors) · insights · dropped domains summary.
- Part B — hard-coded strings: Info.plist · system dialogs · window titles · menus without keys · announcement cards · flow-bar literals · keycap labels · onboarding mock-ups · import errors · native helper · use-case nudges · internal/testing panel.

---


## Part A. i18n strings (`en/*.json`), grouped by screen [R]

### Flow bar (status window) and its pop-overs

#### Flow bar: states, tooltips, hints (65)

Keys referenced by `renderer/status/index.js` (the floating bar), plus the move-the-bar coachmark. `hub_status_menu_*` is the bar's right-click menu (next table).

| Key | NS | English | Rebuild |
|---|---|---|---|
| `audio_quality_action_change_mic` | ntf | Change microphone | reuse |
| `audio_quality_action_dismiss` | ntf | Don't show again | reuse |
| `audio_quality_body` | ntf | Your mic quality is low. Click to hear your audio. | reuse |
| `audio_quality_title` | ntf | We didn't hear you clearly. | reuse |
| `bar_hidden_action_undo` | ntf | Undo | reuse |
| `bar_hidden_title` | ntf | The Flow Bar will be hidden for an hour | reuse |
| `flow_bar_move_hint_title` | ntf | Click and drag the Flow Bar to move it! | reuse |
| `language_picker_retired_action` | ntf | Manage languages | reuse |
| `language_picker_retired_body` | ntf | We’ll detect your language automatically. Make sure all the languages you speak are selected. | reuse |
| `language_picker_retired_title` | ntf | No need to pick a language each time | reuse |
| `language_picker_retired_tooltip` | ntf | Automatic language detection | reuse |
| `notification_close_aria` | ntf | Dismiss notification | reuse |
| `voice_edit_transform_hint` | ntf | Use {{shortcut}} to voice edit | reuse |
| `void_dictation_action_copied` | ntf | Copied! | reuse |
| `void_dictation_action_label` | ntf | Copy | reuse |
| `void_dictation_hint` | ntf | Select a textbox first, then dictate | reuse |
| `hub_common_no_matches` | hub | No matches found | reuse |
| `hub_common_untitled` | hub | Untitled | reuse |
| `hub_instruct_listening` | hub | Listening | reuse |
| `hub_polish_processing_done` | hub | Done. | reuse |
| `hub_polish_processing_see_changes` | hub | See changes | reuse |
| `hub_post_instruct_follow_up_label` | hub | to instruct | reuse |
| `hub_post_instruct_open_chat_aria` | hub | Open instruct chat | reuse |
| `hub_post_instruct_undo_label` | hub | Undo | reuse |
| `hub_select_default_placeholder` | hub | Select | reuse |
| `hub_select_search_placeholder` | hub | Select... | reuse |
| `hub_status_app_suggestion_chatting_with_ai` | hub | [AI chat app] or any AI app | reuse |
| `hub_status_app_suggestion_coding_with_ai` | hub | Cursor or any IDE | reuse |
| `hub_status_app_suggestion_drafting_emails` | hub | your email inbox | reuse |
| `hub_status_app_suggestion_sending_messages` | hub | Slack or any messenger | reuse |
| `hub_status_app_suggestion_taking_notes` | hub | a notetaking app | reuse |
| `hub_status_app_suggestion_writing_documents` | hub | a document-writing app | reuse |
| `hub_status_app_suggestion_writing_posts` | hub | LinkedIn or any social app | reuse |
| `hub_status_auto_cleanup_label` | hub | Cleaned up! | reuse |
| `hub_status_auto_cleanup_see_changes` | hub | ` See what’s changed` | reuse |
| `hub_status_cancel_tooltip` | hub | Cancel | reuse |
| `hub_status_fetch_links_tooltip` | hub | Fetch links | reuse |
| `hub_status_finish_and_paste_tooltip` | hub | Finish and paste | reuse |
| `hub_status_growth_nudge_ai_prompts` | hub | AI prompts | reuse |
| `hub_status_growth_nudge_double_tap` | hub | Double tap | reuse |
| `hub_status_growth_nudge_emails` | hub | emails | reuse |
| `hub_status_growth_nudge_hold` | hub | Hold | reuse |
| `hub_status_growth_nudge_messages` | hub | messages | reuse |
| `hub_status_growth_nudge_to_dictate` | hub | ` to dictate {{appType}}` | reuse |
| `hub_status_pulsar_any_text_app` | hub | any text based app | reuse |
| `hub_status_pulsar_click_textbox_double_tap` | hub | Click a textbox, double-tap | reuse |
| `hub_status_pulsar_click_textbox_hold` | hub | Click a textbox, hold | reuse |
| `hub_status_pulsar_dictate` | hub | Dictate | reuse |
| `hub_status_pulsar_finish_and_paste` | hub | to finish and paste | reuse |
| `hub_status_pulsar_instead_of_typing` | hub | instead of typing | reuse |
| `hub_status_pulsar_open_app` | hub | Open {{appSuggestion}} | reuse |
| `hub_status_pulsar_press` | hub | Press | reuse |
| `hub_status_pulsar_to_dictate` | hub | to dictate | reuse |
| `hub_status_pulsar_try_dictating_double_tap` | hub | Try dictating by double tapping | reuse |
| `hub_status_pulsar_try_dictating_hold` | hub | Try dictating by holding | reuse |
| `hub_status_tooltip_instruct_chat` | hub | Open instruct chat | reuse |
| `hub_status_tooltip_next_step` | hub | Next step → | reuse |
| `hub_status_tooltip_reconnecting` | hub | Still listening · Reconnecting… | rewrite |
| `hub_status_tooltip_scratchpad` | hub | Scratchpad | reuse |
| `hub_status_tooltip_word_count_one` | hub | {{count, number}} word | reuse |
| `hub_status_tooltip_word_count_other` | hub | {{count, number}} words | reuse |
| `moveable_flow_bar_modal_body` | hub | Click and drag on the Flow Bar to move it to the left, right, or bottom of your screen. | reuse |
| `moveable_flow_bar_modal_close_aria` | hub | Dismiss | reuse |
| `moveable_flow_bar_modal_cta` | hub | Try it out | reuse |
| `moveable_flow_bar_modal_title` | hub | You can now move the Flow Bar! | reuse |

#### Flow bar right-click menu and Fetch-links palette (contextMenu window) (31)

Keys referenced by `renderer/contextMenu/index.js`.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_context_menu_mic_in_use_prefix` | set | Mic in use: | reuse |
| `context_menu_auto_polish_configure_transforms` | ntf | Configure transforms | reuse |
| `context_menu_auto_polish_default_option` | ntf | {{name}} | reuse |
| `context_menu_auto_polish_toggle` | ntf | Auto Apply After Dictation | reuse |
| `context_menu_fetch_links_copy_only` | ntf | Copy only | reuse |
| `context_menu_fetch_links_empty` | ntf | No copied links yet | reuse |
| `context_menu_fetch_links_no_matching_links` | ntf | No matching links | reuse |
| `context_menu_fetch_links_no_recent_links` | ntf | No recent links | reuse |
| `context_menu_fetch_links_no_recent_matches` | ntf | No matching recent links | reuse |
| `context_menu_fetch_links_open_and_copy` | ntf | Open and copy | reuse |
| `context_menu_fetch_links_pin` | ntf | Pin | reuse |
| `context_menu_fetch_links_pinned` | ntf | Pinned | reuse |
| `context_menu_fetch_links_recents` | ntf | Recents | reuse |
| `context_menu_fetch_links_remove` | ntf | Remove | reuse |
| `context_menu_fetch_links_search_placeholder` | ntf | Search links | reuse |
| `context_menu_fetch_links_unpin` | ntf | Unpin | reuse |
| `hub_status_menu_configure_reminder` | hub | Configure reminder | reuse |
| `hub_status_menu_formatting_options` | hub | Formatting options | reuse |
| `hub_status_menu_hide_one_hour` | hub | Hide for 1 hour | reuse |
| `hub_status_menu_languages` | hub | Languages | reuse |
| `hub_status_menu_microphone` | hub | Microphone | reuse |
| `hub_status_menu_microphone_hide_virtual` | hub | Show fewer devices | reuse |
| `hub_status_menu_microphone_notetaker` | hub | Microphone (Notetaker) | reuse |
| `hub_status_menu_microphone_notetaker_change_mic` | hub | Change system microphone… | reuse |
| `hub_status_menu_microphone_notetaker_description` | hub | Notetaker always uses {{micName}} | reuse |
| `hub_status_menu_microphone_show_virtual` | hub | Show other devices ({{count}}) | reuse |
| `hub_status_menu_mute_reminder` | hub | Mute reminder for 12 hours | reuse |
| `hub_status_menu_paste_last_transcript` | hub | Paste last transcript | reuse |
| `hub_status_menu_settings` | hub | Settings | reuse |
| `hub_status_menu_show_all` | hub | Show all | reuse |
| `hub_status_menu_transcript_history` | hub | Transcript history | reuse |

#### Typing reminder (bar nudge when you type at length instead of dictating) (12)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `typing_reminder_configure_action_save` | ntf | Save | reuse |
| `typing_reminder_configure_body` | ntf | You made it to {{milestoneWords}} words. Choose the way your Flow Bar looks when you've been typing a lot. ✨ | reuse |
| `typing_reminder_configure_title` | ntf | You've reached your Flow! | reuse |
| `typing_reminder_enabled_action_dismiss` | ntf | Great | reuse |
| `typing_reminder_enabled_action_settings` | ntf | Go to Settings | reuse |
| `typing_reminder_enabled_body` | ntf | We’ll gently remind you to dictate as you get started. Adjust anytime in Settings. | reuse |
| `typing_reminder_enabled_header_stagger` | ntf | Congrats! You’re ready to Flow | reuse |
| `typing_reminder_enabled_header_typewriter` | ntf | in any app. | reuse |
| `typing_reminder_enabled_no_reminder` | ntf | No reminder | reuse |
| `typing_reminder_enabled_title` | ntf | Congrats! You’re ready to Flow in any app. | reuse |
| `typing_reminder_muted_action_undo` | ntf | Undo | reuse |
| `typing_reminder_muted_title` | ntf | Dictation reminder muted for 12 hours | reuse |

### Menu bar item and app menus

#### Tray menu, application menu, Dock menu, update prompts (56)

Tray order (top→bottom): [upcoming meetings…] · Start Notetaker · Open Wispr Flow · ― · ‹update state› · ― · Paste last transcript (accelerator = paste-last shortcut) · ‹last transcript preview, disabled, 25 chars + "..."› · ― · Shortcuts · Microphone ▸ (device checkboxes) · Languages ▸ (language checkboxes) · ― · Help center · Talk to support ⌘/ · Share feedback · ― · Quit ⌘Q. Tray tooltip: "Wispr Flow". App menu: Wispr Flow ▸ (About · ‹update state› · ― · Settings ⌘, · ― · Hide · Hide Others · Show All · ― · Quit ⌘Q), File, Edit, Dictation ▸ (Words dictated: N · ― · Copy last transcript · ‹preview› · ― · Microphone ▸ · Languages ▸), [Notes], [My Voice ▸ (Dictionary words: N · Snippets created: N · ― · Add a word to dictionary · Create a new snippet)], View, Help ▸ (Help center · Talk to support ⌘/ · Share feedback · Shortcuts), Window ▸ (Minimize · Close). Update state label maps CHECKING→`menus_update_checking`, AVAILABLE→`menus_update_downloading`, DOWNLOADED→`menus_update_ready`, ERROR→`menus_update_error`, NOT_AVAILABLE→`menus_update_check`.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `menus_about_wispr_flow` | men | About Wispr Flow | reuse |
| `menus_add_dictionary_word` | men | Add a word to dictionary | reuse |
| `menus_close_window` | men | Close window | reuse |
| `menus_copy_last_transcript` | men | Copy last transcript | reuse |
| `menus_create_snippet` | men | Create a new snippet | reuse |
| `menus_dictation` | men | Dictation | reuse |
| `menus_dictionary_words_count` | men | Dictionary words: {{count}} | reuse |
| `menus_edit` | men | Edit | reuse |
| `menus_file` | men | File | reuse |
| `menus_help` | men | Help | reuse |
| `menus_help_center` | men | Help center | reuse |
| `menus_hide_next_meeting_from_menu_bar` | men | Hide next meeting from menu bar | reuse |
| `menus_hide_wispr_flow` | men | Hide Wispr Flow | reuse |
| `menus_join_meeting` | men | Join meeting | reuse |
| `menus_languages` | men | Languages | reuse |
| `menus_microphone` | men | Microphone | reuse |
| `menus_my_voice` | men | My Voice | reuse |
| `menus_notetaker` | men | Notetaker | reuse |
| `menus_notetaker_consent_notice_default_message` | men | Hi everyone — quick note that I'm using Wispr Notetaker to transcribe this meeting so I can stay present. Let me know if you'd like me to turn it off. | reuse |
| `menus_now` | men | Now | reuse |
| `menus_open_notetaker` | men | Open Notetaker | reuse |
| `menus_open_wispr_flow` | men | Open Wispr Flow | reuse |
| `menus_past_notes` | men | Past notes | reuse |
| `menus_paste_last_transcript` | men | Paste last transcript | reuse |
| `menus_quit_wispr_flow` | men | Quit Wispr Flow | reuse |
| `menus_recent_meetings` | men | Recent meetings | reuse |
| `menus_see_all_past_notes` | men | See all past notes | reuse |
| `menus_see_all_upcoming_meetings` | men | See all upcoming meetings | reuse |
| `menus_select_all` | men | Select All | reuse |
| `menus_settings` | men | Settings | reuse |
| `menus_share_feedback` | men | Share feedback | reuse |
| `menus_shortcuts` | men | Shortcuts | reuse |
| `menus_show_next_meeting_in_menu_bar` | men | Show next meeting in menu bar | reuse |
| `menus_snippets_created_count` | men | Snippets created: {{count}} | reuse |
| `menus_start_dictation` | men | Start dictation | reuse |
| `menus_start_new_note` | men | Start new note | reuse |
| `menus_start_notetaker` | men | Start Notetaker | reuse |
| `menus_talk_to_support` | men | Talk to support | reuse |
| `menus_today` | men | Today | reuse |
| `menus_tomorrow` | men | Tomorrow | reuse |
| `menus_untitled_note` | men | Untitled note | reuse |
| `menus_update_ceiling_detail` | men | Restarting takes a few seconds. Choose Later and Flow will install it the next time you step away. | reuse |
| `menus_update_ceiling_later` | men | Later | reuse |
| `menus_update_ceiling_message` | men | A new version of Wispr Flow is ready | reuse |
| `menus_update_ceiling_restart` | men | Restart now | reuse |
| `menus_update_ceiling_title` | men | Update ready | reuse |
| `menus_update_check` | men | Check for updates... | reuse |
| `menus_update_checking` | men | Checking for updates... | reuse |
| `menus_update_downloading` | men | Update downloading... | reuse |
| `menus_update_error` | men | Error updating, please restart | reuse |
| `menus_update_next_check` | men | Next update check: {{date}} | reuse |
| `menus_update_ready` | men | Update ready, restart now? | reuse |
| `menus_view` | men | View | reuse |
| `menus_window` | men | Window | reuse |
| `menus_words_dictated_count` | men | Words dictated: {{count}} | reuse |
| `menus_yesterday` | men | Yesterday | reuse |

### Onboarding

#### Onboarding chrome: progress rail, navigation, gating (32)

Progress-rail sections are also referenced by the status, overlay, contextMenu and accessibility_drop windows.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `center_layout_skip_button` | onb | Skip | reuse |
| `continue_button` | onb | Continue | reuse |
| `dictation_locked_gate_body` | onb | It only takes 2 minutes. Flow turns your speech into polished text in any app on your computer! No integrations needed. | reuse |
| `dictation_locked_gate_cta` | onb | Get started | reuse |
| `dictation_locked_gate_title` | onb | Complete your setup to use dictation | reuse |
| `dictation_locked_gate_title_dictionary` | onb | Set up dictation to access Dictionary | reuse |
| `dictation_locked_gate_title_insights` | onb | Set up dictation to access Insights | reuse |
| `dictation_locked_gate_title_my_voice` | onb | Set up dictation to access My Voice | reuse |
| `dictation_locked_gate_title_snippets` | onb | Set up dictation to access Snippets | reuse |
| `dictation_locked_gate_title_style` | onb | Set up dictation to access Style | reuse |
| `dictation_locked_gate_title_transforms` | onb | Set up dictation to access Transforms | reuse |
| `layout_back_button` | onb | Back | reuse |
| `onboarding_progress_section_get_started` | onb | Get started | reuse |
| `onboarding_progress_section_learn` | onb | Learn | reuse |
| `onboarding_progress_section_permissions` | onb | Permissions | reuse |
| `onboarding_progress_section_personalize` | onb | Personalize | reuse |
| `onboarding_progress_section_set_up` | onb | Set up | reuse |
| `onboarding_progress_section_sign_up` | onb | Sign up | reuse |
| `speedy_onboarding_modal_body` | onb | We'll cover the essentials and skip the parts you've already seen. | reuse |
| `speedy_onboarding_modal_close_label` | onb | Close | reuse |
| `speedy_onboarding_modal_show_everything` | onb | Show me everything | reuse |
| `speedy_onboarding_modal_skip_onboarding` | onb | Skip onboarding | reuse |
| `speedy_onboarding_modal_title` | onb | Want to skip ahead? | reuse |
| `onboarding_continue_nudge_action_finish` | ntf | Finish onboarding | reuse |
| `onboarding_continue_nudge_body` | ntf | Return to the app and finish a few more steps to unlock the full power of Flow. | reuse |
| `onboarding_continue_nudge_title` | ntf | Just a few more steps! | reuse |
| `post_onboarding_completed_body` | ntf | Keep going: write a note, draft an email, send a message or dictate anywhere else! | reuse |
| `post_onboarding_completed_title` | ntf | You're ready to Flow everywhere. | reuse |
| `post_onboarding_explore_flow_action` | ntf | Explore Wispr Flow | reuse |
| `post_onboarding_failed_paste_title` | ntf | Click on a textbox first and then dictate | reuse |
| `post_onboarding_in_app_dictation_body` | ntf | Don't dictate with Flow here. | reuse |
| `post_onboarding_in_app_dictation_title` | ntf | Try using Flow in another app! | reuse |

#### Welcome and introduction (17)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `intelligence_modal_cta` | onb | Try it → | reuse |
| `intelligence_modal_title_fixes_mistakes` | onb | Wispr Flow fixes your mistakes | reuse |
| `intelligence_modal_title_formats_for_you` | onb | Wispr Flow formats for you | reuse |
| `introduction_cta` | onb | Continue | reuse |
| `introduction_cta_v2` | onb | Start Setup | reuse |
| `introduction_description` | onb | Whatever the task—to clear your inbox or craft documents faster—Flow works everywhere you do. | reuse |
| `introduction_description_v2` | onb | Flow understands what you mean – not just what you said – turning your voice into perfectly formatted text in every app. | reuse |
| `introduction_header` | onb | `Flow is seamless voice-to-text that works in <em>every app</em>.` | reuse |
| `introduction_header_v2` | onb | `Flow is voice-to-text that works <em>everywhere</em>.` | reuse |
| `introduction_image_alt` | onb | Flow works everywhere | reuse |
| `welcome_basic_description` | onb | Where did you hear about us? | reuse |
| `welcome_basic_description_v2` | onb | Where did you hear about us? | reuse |
| `welcome_basic_header` | onb | Welcome! | reuse |
| `welcome_basic_header_named` | onb | Welcome, {{name}}! | reuse |
| `welcome_basic_header_v2` | onb | Welcome {{name}}! A few questions to get started. | reuse |
| `welcome_basic_header_v2_no_name` | onb | Welcome! A few questions to get started. | reuse |
| `welcome_basic_image_alt` | onb | Welcome to Flow | reuse |

#### About you (role, industry, where you type, work environment, intent) (97)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `about_yourself_description` | onb | What do you do for work? | reuse |
| `about_yourself_description_student` | onb | What is your occupation? | reuse |
| `about_yourself_description_v2` | onb | What do you do for work? | reuse |
| `about_yourself_header` | onb | Tell us about yourself | reuse |
| `about_yourself_header_v2` | onb | Tell us about yourself | reuse |
| `about_yourself_image_alt` | onb | Tell us about yourself | reuse |
| `about_yourself_industry_director` | onb | Director | reuse |
| `about_yourself_industry_executive` | onb | Executive | reuse |
| `about_yourself_industry_freelancer` | onb | Freelancer | reuse |
| `about_yourself_industry_individual_contributor` | onb | Individual contributor | reuse |
| `about_yourself_industry_manager` | onb | Manager | reuse |
| `about_yourself_industry_other` | onb | Other | reuse |
| `about_yourself_role_consultant` | onb | Consultant | reuse |
| `about_yourself_role_creator` | onb | Creator | reuse |
| `about_yourself_role_customer_support` | onb | Customer Support | reuse |
| `about_yourself_role_data_analyst` | onb | Data Analysis | reuse |
| `about_yourself_role_developer` | onb | Developer | reuse |
| `about_yourself_role_educator` | onb | Educator | reuse |
| `about_yourself_role_founder` | onb | Founder/CEO | reuse |
| `about_yourself_role_healthcare` | onb | Healthcare | reuse |
| `about_yourself_role_legal` | onb | Legal | reuse |
| `about_yourself_role_marketing` | onb | Marketing | reuse |
| `about_yourself_role_operations` | onb | Operations | reuse |
| `about_yourself_role_other` | onb | Other | reuse |
| `about_yourself_role_product` | onb | Product | reuse |
| `about_yourself_role_recruiting` | onb | Recruiting | reuse |
| `about_yourself_role_sales` | onb | Sales | reuse |
| `about_yourself_role_student` | onb | Student | reuse |
| `about_yourself_role_writer` | onb | Writer | reuse |
| `about_yourself_tell_us_more` | onb | Tell us more | reuse |
| `product_intent_demo_dictation_email_formatted` | onb | Hi Sam,\n\nCan we move our sync to Thursday?\n\nThanks! | reuse |
| `product_intent_demo_dictation_email_spoken` | onb | `hi Sam <filler>um</filler> can we move our sync to Thursday <filler>uh</filler> thanks` | reuse |
| `product_intent_demo_dictation_email_subject` | onb | Re: Q3 launch plan | reuse |
| `product_intent_demo_dictation_email_subject_label` | onb | Subject | reuse |
| `product_intent_demo_dictation_email_to` | onb | Sam Rivera | reuse |
| `product_intent_demo_dictation_email_to_label` | onb | To | reuse |
| `product_intent_demo_dictation_slack_channel` | onb | launch-team | reuse |
| `product_intent_demo_dictation_slack_formatted` | onb | Quick update:\n- Designs are approved\n- Dashboard ships Friday | reuse |
| `product_intent_demo_dictation_slack_spoken` | onb | `quick update <filler>um</filler> designs are approved <filler>uh</filler> dashboard ships Friday` | reuse |
| `product_intent_demo_notetaker_speaker_1` | onb | Hayle | reuse |
| `product_intent_demo_notetaker_speaker_2` | onb | Mikel | reuse |
| `product_intent_demo_notetaker_summary_action_1` | onb | Mikel: pricing proposal by Friday | reuse |
| `product_intent_demo_notetaker_summary_action_2` | onb | Hayle: onboarding metrics review | reuse |
| `product_intent_demo_notetaker_summary_actions_heading` | onb | Action items | reuse |
| `product_intent_demo_notetaker_summary_decision_1` | onb | Launch moves to the week of the 14th | reuse |
| `product_intent_demo_notetaker_summary_decisions_heading` | onb | Decisions | reuse |
| `product_intent_demo_notetaker_summary_label` | onb | Summary | reuse |
| `product_intent_demo_notetaker_summary_overview` | onb | Aligned on launch timing and split up next steps. | reuse |
| `product_intent_demo_notetaker_transcript_1` | onb | Let’s push the launch to the week of the 14th. | reuse |
| `product_intent_demo_notetaker_transcript_2` | onb | I can have the pricing proposal ready by Friday. | reuse |
| `product_intent_demo_notetaker_transcript_3` | onb | Sure, I’ll own the onboarding metrics review. | reuse |
| `product_intent_description` | onb | What are you interested in trying? Select all that apply. | reuse |
| `product_intent_dictation_description` | onb | Speak, instead of typing, and get perfectly formatted text in any app | reuse |
| `product_intent_dictation_title` | onb | Dictation | reuse |
| `product_intent_header` | onb | How can Flow help you? | reuse |
| `product_intent_image_alt` | onb | Illustration of Flow helping you write and take notes | reuse |
| `product_intent_notetaker_description` | onb | Transcribe all your meetings, and get auto-generated notes and summaries | reuse |
| `product_intent_notetaker_title` | onb | Notetaker | reuse |
| `product_intent_notetaker_unsupported_tooltip` | onb | Notetaker needs macOS 13 or later | reuse |
| `spend_time_typing_chatting_with_ai_icon_alt` | onb | Chatting with AI | reuse |
| `spend_time_typing_description` | onb | This helps us personalize Flow where you work. Select all that apply. | reuse |
| `spend_time_typing_description_v2` | onb | This helps us personalize Flow where you work. Select all that apply. | reuse |
| `spend_time_typing_header` | onb | Where do you spend time typing? | reuse |
| `spend_time_typing_header_v2` | onb | Where do you spend time typing? | reuse |
| `spend_time_typing_image_alt` | onb | Typing Locations | reuse |
| `spend_time_typing_keyboard_image_alt` | onb | Typing Relationship | reuse |
| `spend_time_typing_option_chatting_with_ai` | onb | Chatting with AI | reuse |
| `spend_time_typing_option_coding_with_ai` | onb | Coding with AI | reuse |
| `spend_time_typing_option_drafting_emails` | onb | Drafting emails | reuse |
| `spend_time_typing_option_sending_messages` | onb | Sending messages | reuse |
| `spend_time_typing_option_something_else` | onb | Something else | reuse |
| `spend_time_typing_option_taking_notes` | onb | Taking notes | reuse |
| `spend_time_typing_option_writing_discussion_posts` | onb | Writing discussion posts | reuse |
| `spend_time_typing_option_writing_documents` | onb | Writing documents | reuse |
| `spend_time_typing_option_writing_essays` | onb | Writing essays | reuse |
| `spend_time_typing_option_writing_posts_or_comments` | onb | Writing posts or comments | reuse |
| `spend_time_typing_option_writing_problem_sets` | onb | Writing problem sets | reuse |
| `spend_time_typing_other_label` | onb | Where else do you type? | reuse |
| `spend_time_typing_writing_need_capture_ideas_quickly` | onb | I need to be able to capture ideas quickly | reuse |
| `spend_time_typing_writing_need_code_with_ai` | onb | I want to code with AI more easily | reuse |
| `spend_time_typing_writing_need_detailed_ai_prompts` | onb | I want to write more detailed AI prompts | reuse |
| `spend_time_typing_writing_need_draft_documents_easily` | onb | I need to draft documents with less effort | reuse |
| `spend_time_typing_writing_need_typing_tiring` | onb | I think typing is tiring or uncomfortable | reuse |
| `spend_time_typing_writing_need_work_hands_free` | onb | I need to be able to work hands-free or on-the-go | reuse |
| `spend_time_typing_writing_need_write_many_emails` | onb | I have to write a lot of emails | reuse |
| `spend_time_typing_writing_need_write_many_messages` | onb | I have to write a lot of messages | reuse |
| `spend_time_typing_writing_needs_description` | onb | Learning how you type helps us find the ways Flow can be helpful to you. | reuse |
| `spend_time_typing_writing_needs_header` | onb | Let’s talk about your relationship with typing. | reuse |
| `work_environment_description` | onb | We'll give you tips based on your environment. | reuse |
| `work_environment_header` | onb | Do you work next to other people? | reuse |
| `work_environment_image_alt` | onb | Work Environment | reuse |
| `work_environment_option_no_description` | onb | Mostly private, quiet spaces | reuse |
| `work_environment_option_no_title` | onb | No | reuse |
| `work_environment_option_sometimes_description` | onb | Mix of private and public spaces | reuse |
| `work_environment_option_sometimes_title` | onb | Sometimes | reuse |
| `work_environment_option_yes_description` | onb | Mostly working around others | reuse |
| `work_environment_option_yes_title` | onb | Yes | reuse |

#### Notetaker branch: how you record meetings, meeting types, calendar connection (150)

Shown when the user picks Notetaker in "product intent". Calendar rows that name Google/Outlook/iCloud sign-in are `rewrite`: the rebuild reads calendars through EventKit.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `connect_calendar_brief_preview_brief_label` | onb | Brief | reuse |
| `connect_calendar_brief_preview_join_subtitle` | onb | & Start Notetaker | reuse |
| `connect_calendar_brief_preview_join_title` | onb | Join Meeting | reuse |
| `connect_calendar_brief_preview_line_1` | onb | `Updated designs were shared in <slack>Slack</slack> on Thursday and are waiting on your review.` | rewrite |
| `connect_calendar_brief_preview_line_2` | onb | Your open action item: send last week’s launch metrics to the team. | reuse |
| `connect_calendar_brief_preview_line_3` | onb | Scope was left open last time — the team is expecting a decision today. | reuse |
| `connect_calendar_brief_preview_meeting_title` | onb | Weekly product sync | reuse |
| `connect_calendar_brief_preview_starts_in` | onb | In 2 min | reuse |
| `connect_calendar_choice_icloud` | onb | iCloud | rewrite |
| `connect_calendar_choice_none` | onb | I don’t use a calendar | reuse |
| `connect_calendar_choice_outlook` | onb | Outlook | rewrite |
| `connect_calendar_choice_question` | onb | What calendar do you currently use? | reuse |
| `connect_calendar_choice_something_else` | onb | Something else | reuse |
| `connect_calendar_coming_soon_icloud_body` | onb | You can still use Notetaker but it’s not compatible with iCloud yet. We’ll notify you when it’s ready! | rewrite |
| `connect_calendar_coming_soon_icloud_title` | onb | iCloud coming soon! | rewrite |
| `connect_calendar_coming_soon_outlook_body` | onb | You can still use Notetaker but it’s not compatible with Outlook yet. We’ll notify you when it’s ready! | rewrite |
| `connect_calendar_coming_soon_outlook_title` | onb | Outlook coming soon! | rewrite |
| `connect_calendar_connect_button` | onb | Connect | reuse |
| `connect_calendar_connect_error` | onb | Couldn’t start connecting. Try again. | reuse |
| `connect_calendar_connected_card` | onb | Google Calendar connected | rewrite |
| `connect_calendar_connecting_status` | onb | Connecting Google Calendar… | rewrite |
| `connect_calendar_description` | onb | We'll capture notes for all your meetings. | reuse |
| `connect_calendar_different` | onb | I use a different calendar | reuse |
| `connect_calendar_failed_error` | onb | We couldn’t finish connecting your calendar. | reuse |
| `connect_calendar_google_description` | onb | For accurate meeting reminders and pre-meeting briefs | reuse |
| `connect_calendar_google_title` | onb | Connect Google Calendar | rewrite |
| `connect_calendar_header` | onb | Connect your calendar | reuse |
| `connect_calendar_outlook_connected_status` | onb | Outlook connected | rewrite |
| `connect_calendar_outlook_connecting_status` | onb | Connecting Outlook… | rewrite |
| `connect_calendar_outlook_title` | onb | Connect Outlook | rewrite |
| `connect_calendar_upcoming_one_on_one_time` | onb | 3:30pm - 4:00pm | reuse |
| `connect_calendar_upcoming_one_on_one_title` | onb | Design 1:1 | reuse |
| `connect_calendar_upcoming_pill` | onb | Upcoming meetings ({{count}}) | reuse |
| `connect_calendar_upcoming_review_time` | onb | 1:00pm - 1:45pm | reuse |
| `connect_calendar_upcoming_review_title` | onb | Product review | reuse |
| `connect_calendar_upcoming_standup_time` | onb | 10:15am - 10:30am | reuse |
| `connect_calendar_upcoming_standup_title` | onb | Team standup | reuse |
| `connect_calendar_value_prop_briefs` | onb | Pre-meeting briefs | reuse |
| `connect_calendar_value_prop_context` | onb | Relevant meeting context | reuse |
| `connect_calendar_value_prop_reminders` | onb | Reminders to join and transcribe meetings | reuse |
| `connect_calendar_value_prop_speakers` | onb | Speaker names in transcripts | reuse |
| `how_do_you_record_meetings_description` | onb | This helps us personalize Notetaker for you. Select all that apply. | reuse |
| `how_do_you_record_meetings_header` | onb | How do you currently record meetings? | reuse |
| `how_do_you_record_meetings_import_callout_both` | onb | You’ll be able to import all your Granola and Otter notes once you’re set up! | drop |
| `how_do_you_record_meetings_import_callout_granola` | onb | You’ll be able to import all your Granola notes once you’re set up! | drop |
| `how_do_you_record_meetings_import_callout_otter` | onb | You’ll be able to import all your Otter notes once you’re set up! | drop |
| `how_do_you_record_meetings_option_fathom` | onb | Fathom | reuse |
| `how_do_you_record_meetings_option_google_meet` | onb | Google Meet | reuse |
| `how_do_you_record_meetings_option_grain` | onb | Grain | reuse |
| `how_do_you_record_meetings_option_granola` | onb | Granola | drop |
| `how_do_you_record_meetings_option_none` | onb | I don’t record meetings | reuse |
| `how_do_you_record_meetings_option_notion` | onb | Notion | rewrite |
| `how_do_you_record_meetings_option_otter` | onb | Otter | drop |
| `how_do_you_record_meetings_option_plaud` | onb | Plaud | reuse |
| `how_do_you_record_meetings_option_something_else` | onb | Something else | reuse |
| `how_do_you_record_meetings_option_teams` | onb | Microsoft Teams | rewrite |
| `how_do_you_record_meetings_option_zoom` | onb | Zoom | reuse |
| `what_kinds_of_meetings_description` | onb | We’ll configure Notetaker around your meeting types. Select all that apply. | reuse |
| `what_kinds_of_meetings_example_catch_ups_next_step_1` | onb | `(<s2>{{firstName}}</s2>) Introduce <s1>Maya</s1> to Chris` | reuse |
| `what_kinds_of_meetings_example_catch_ups_next_step_2` | onb | `(<s1>Maya</s1>) Send her comp plan` | reuse |
| `what_kinds_of_meetings_example_catch_ups_section_1_heading` | onb | Move to Lisbon | reuse |
| `what_kinds_of_meetings_example_catch_ups_section_1_item_1` | onb | `<s1>Maya</s1> moves in March and will work remotely` | reuse |
| `what_kinds_of_meetings_example_catch_ups_section_1_item_2` | onb | Her team has agreed to the time difference | reuse |
| `what_kinds_of_meetings_example_catch_ups_section_2_heading` | onb | Running sales at Orbit | reuse |
| `what_kinds_of_meetings_example_catch_ups_section_2_item_1` | onb | Two reps start next month | reuse |
| `what_kinds_of_meetings_example_catch_ups_section_2_item_2` | onb | First goal is 10 new customers by June | reuse |
| `what_kinds_of_meetings_example_catch_ups_summary` | onb | `Caught up on <s1>Maya</s1>’s move to Lisbon and her first months running sales at Orbit.` | reuse |
| `what_kinds_of_meetings_example_catch_ups_title` | onb | Coffee with Maya | reuse |
| `what_kinds_of_meetings_example_classes_talks_next_step_1` | onb | `(<s2>{{firstName}}</s2>) Read chapter 3 before Thursday` | reuse |
| `what_kinds_of_meetings_example_classes_talks_next_step_2` | onb | `(<s2>{{firstName}}</s2>) Finish problem set 2 by Oct 21` | reuse |
| `what_kinds_of_meetings_example_classes_talks_section_1_heading` | onb | From sound to text | reuse |
| `what_kinds_of_meetings_example_classes_talks_section_1_item_1` | onb | Audio is cut into slices of about 25 milliseconds | reuse |
| `what_kinds_of_meetings_example_classes_talks_section_1_item_2` | onb | A model predicts the most likely words | reuse |
| `what_kinds_of_meetings_example_classes_talks_section_2_heading` | onb | Why it gets words wrong | reuse |
| `what_kinds_of_meetings_example_classes_talks_section_2_item_1` | onb | Names and jargon are rare in what it learned | reuse |
| `what_kinds_of_meetings_example_classes_talks_section_2_item_2` | onb | Noise and accents raise the error rate | reuse |
| `what_kinds_of_meetings_example_classes_talks_summary` | onb | `<s1>Prof. Reyes</s1> explained how software turns speech into text and why it still gets names wrong.` | reuse |
| `what_kinds_of_meetings_example_classes_talks_title` | onb | CS 101: Lecture 5 | reuse |
| `what_kinds_of_meetings_example_client_partner_next_step_1` | onb | `(<s2>{{firstName}}</s2>) Confirm the fix with <s1>Tom</s1> on Thursday` | reuse |
| `what_kinds_of_meetings_example_client_partner_next_step_2` | onb | `(<s1>Tom</s1>) Send sample recordings` | reuse |
| `what_kinds_of_meetings_example_client_partner_section_1_heading` | onb | Issue | reuse |
| `what_kinds_of_meetings_example_client_partner_section_1_item_1` | onb | `<s1>Tom</s1> reports it hears “Priya” as “pizza”` | reuse |
| `what_kinds_of_meetings_example_client_partner_section_2_heading` | onb | Status | reuse |
| `what_kinds_of_meetings_example_client_partner_section_2_item_1` | onb | Cause found, fix in testing | reuse |
| `what_kinds_of_meetings_example_client_partner_summary` | onb | Pear’s voice assistant keeps getting customer names wrong. A fix ships Thursday. | reuse |
| `what_kinds_of_meetings_example_client_partner_title` | onb | Pear assistant issue | reuse |
| `what_kinds_of_meetings_example_interviews_next_step_1` | onb | `(<s2>{{firstName}}</s2>) Send <s1>Sam</s1> the take-home brief` | reuse |
| `what_kinds_of_meetings_example_interviews_next_step_2` | onb | `(<s3>Riya</s3>) Schedule the onsite` | reuse |
| `what_kinds_of_meetings_example_interviews_section_1_heading` | onb | Background | reuse |
| `what_kinds_of_meetings_example_interviews_section_1_item_1` | onb | Six years in product design | reuse |
| `what_kinds_of_meetings_example_interviews_section_1_item_2` | onb | Most recently at a 40-person startup | reuse |
| `what_kinds_of_meetings_example_interviews_section_2_heading` | onb | Candidate answers | reuse |
| `what_kinds_of_meetings_example_interviews_section_2_item_1` | onb | Proudest of a redesign that halved sign-up time | reuse |
| `what_kinds_of_meetings_example_interviews_section_2_item_2` | onb | Wants a smaller team with more ownership | reuse |
| `what_kinds_of_meetings_example_interviews_summary` | onb | `First interview with <s1>Sam</s1> for the product designer role. Moving to the onsite.` | reuse |
| `what_kinds_of_meetings_example_interviews_title` | onb | Interview with Sam Lee | reuse |
| `what_kinds_of_meetings_example_investor_board_next_step_1` | onb | `(<s2>{{firstName}}</s2>) Send retention numbers by Wednesday` | reuse |
| `what_kinds_of_meetings_example_investor_board_next_step_2` | onb | `(<s1>Elena</s1>) Set up a partner meeting` | reuse |
| `what_kinds_of_meetings_example_investor_board_section_1_heading` | onb | Questions | reuse |
| `what_kinds_of_meetings_example_investor_board_section_1_item_1` | onb | `<s1>Elena</s1> asks what retention looks like after month three` | reuse |
| `what_kinds_of_meetings_example_investor_board_section_1_item_2` | onb | `<s1>Elena</s1> asks how much of growth is paid` | reuse |
| `what_kinds_of_meetings_example_investor_board_section_2_heading` | onb | Feedback | reuse |
| `what_kinds_of_meetings_example_investor_board_section_2_item_1` | onb | `<s1>Elena</s1> thinks pricing looks low for teams` | reuse |
| `what_kinds_of_meetings_example_investor_board_summary` | onb | Kestrel likes the growth and wants to see retention before a partner meeting. | reuse |
| `what_kinds_of_meetings_example_investor_board_title` | onb | Intro call with Kestrel | reuse |
| `what_kinds_of_meetings_example_next_steps_heading` | onb | Next Steps | reuse |
| `what_kinds_of_meetings_example_one_on_one_next_step_1` | onb | `(<s2>{{firstName}}</s2>) Unblock design review this week` | reuse |
| `what_kinds_of_meetings_example_one_on_one_next_step_2` | onb | `(<s1>Priya</s1>) Draft the launch plan by Monday` | reuse |
| `what_kinds_of_meetings_example_one_on_one_section_1_heading` | onb | Blockers | reuse |
| `what_kinds_of_meetings_example_one_on_one_section_1_item_1` | onb | Design review is two weeks behind | reuse |
| `what_kinds_of_meetings_example_one_on_one_section_2_heading` | onb | Decisions | reuse |
| `what_kinds_of_meetings_example_one_on_one_section_2_item_1` | onb | `<s1>Priya</s1> leads the January launch` | reuse |
| `what_kinds_of_meetings_example_one_on_one_summary` | onb | `<s1>Priya</s1> is blocked on design review and wants to lead the next launch.` | reuse |
| `what_kinds_of_meetings_example_one_on_one_title` | onb | 1:1 with Priya | reuse |
| `what_kinds_of_meetings_example_owner_fallback` | onb | You | reuse |
| `what_kinds_of_meetings_example_sales_next_step_1` | onb | `(<s2>{{firstName}}</s2>) Send pricing by Friday` | reuse |
| `what_kinds_of_meetings_example_sales_next_step_2` | onb | `(<s1>Maria</s1>) Bring IT to the next call` | reuse |
| `what_kinds_of_meetings_example_sales_section_1_heading` | onb | Questions | reuse |
| `what_kinds_of_meetings_example_sales_section_1_item_1` | onb | `<s1>Maria</s1> asks if it supports single sign-on` | reuse |
| `what_kinds_of_meetings_example_sales_section_1_item_2` | onb | `<s3>Leo</s3> asks if finance can export the reports` | reuse |
| `what_kinds_of_meetings_example_sales_section_2_heading` | onb | Concerns | reuse |
| `what_kinds_of_meetings_example_sales_section_2_item_1` | onb | Migration time | reuse |
| `what_kinds_of_meetings_example_sales_section_2_item_2` | onb | Per-seat pricing above 200 seats | reuse |
| `what_kinds_of_meetings_example_sales_summary` | onb | Acme wants to switch tools before January. Price is the open question. | reuse |
| `what_kinds_of_meetings_example_sales_title` | onb | Discovery call with Acme | reuse |
| `what_kinds_of_meetings_example_team_next_step_1` | onb | `(<s2>Mikel</s2>) Send the pricing proposal by Friday` | reuse |
| `what_kinds_of_meetings_example_team_next_step_2` | onb | `(<s1>Hayle</s1>) Review onboarding metrics` | reuse |
| `what_kinds_of_meetings_example_team_section_1_heading` | onb | Decisions | reuse |
| `what_kinds_of_meetings_example_team_section_1_item_1` | onb | Launch moves to the week of the 14th | reuse |
| `what_kinds_of_meetings_example_team_section_2_heading` | onb | Still open | reuse |
| `what_kinds_of_meetings_example_team_section_2_item_1` | onb | Whether pricing ships with the launch | reuse |
| `what_kinds_of_meetings_example_team_summary` | onb | Aligned on launch timing and split up next steps. | reuse |
| `what_kinds_of_meetings_example_team_title` | onb | Weekly product sync | reuse |
| `what_kinds_of_meetings_header` | onb | What kinds of meetings do you have? | reuse |
| `what_kinds_of_meetings_option_catch_ups` | onb | Catch-ups | reuse |
| `what_kinds_of_meetings_option_classes_talks` | onb | Lectures | reuse |
| `what_kinds_of_meetings_option_client_partner` | onb | Client calls | reuse |
| `what_kinds_of_meetings_option_interviews` | onb | Interviews | reuse |
| `what_kinds_of_meetings_option_investor_board` | onb | Executive meetings | reuse |
| `what_kinds_of_meetings_option_one_on_one` | onb | 1:1s | reuse |
| `what_kinds_of_meetings_option_sales` | onb | Sales calls | reuse |
| `what_kinds_of_meetings_option_something_else` | onb | Something else | reuse |
| `what_kinds_of_meetings_option_team` | onb | Team meetings | reuse |
| `what_would_make_notetaking_better_description` | onb | We’ll configure Notetaker around what matters most to you. Select all that apply. | reuse |
| `what_would_make_notetaking_better_header` | onb | What’s frustrating about meetings? | reuse |
| `what_would_make_notetaking_better_option_finding_notes_afterward` | onb | Finding notes afterward | reuse |
| `what_would_make_notetaking_better_option_prepping_for_meetings` | onb | Prepping for meetings | reuse |
| `what_would_make_notetaking_better_option_something_else` | onb | Something else | reuse |
| `what_would_make_notetaking_better_option_taking_notes_during_call` | onb | Taking notes during the call | reuse |
| `what_would_make_notetaking_better_option_tracking_action_items` | onb | Tracking action items | reuse |

#### Privacy choices (10)

Flow asks about Privacy Mode, usage sharing and cloud sync here. The rebuild is local-only, so this screen becomes a statement, not a set of cloud choices.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `privacy_change_later_notice` | onb | You can always change this later in settings. | rewrite |
| `privacy_data_sharing_description` | onb | Share usage data to help us evaluate, train, and improve Flow and its AI models. | drop |
| `privacy_data_sharing_locked_notice` | onb | Data Sharing is turned off by your HIPAA or organization privacy settings. | drop |
| `privacy_data_sharing_title` | onb | Data Sharing | drop |
| `privacy_header` | onb | You control your data | rewrite |
| `privacy_mode_description` | onb | None of your data will be used for model training by us or any third party. | drop |
| `privacy_mode_title` | onb | Don't use my data for training | drop |
| `privacy_read_more_link` | onb | Read more here. | rewrite |
| `privacy_share_usage_description` | onb | To make Wispr Flow better, this option lets us collect your audio, transcripts, and edits to train and improve AI models. | drop |
| `privacy_share_usage_title` | onb | Improve the model for everyone | drop |

#### Permissions (Accessibility, Microphone; Notetaker: system audio, screen capture) (36)

`permissions_accessibility_drag_*` is the floating drag-to-allow panel (accessibility_drop window) shown over System Settings. `permissions_notetaker_*`, `permissions_system-audio_*` and `permissions_screen-capture_*` belong to the Notetaker branch.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `permissions_accessibility_description` | onb | This lets Flow put your spoken words in the right textbox | reuse |
| `permissions_accessibility_drag_aria_label` | onb | Wispr Flow app icon. Drag it into the Accessibility list in System Settings. | reuse |
| `permissions_accessibility_drag_dismiss` | onb | Hide | reuse |
| `permissions_accessibility_drag_hint` | onb | Click Allow to open System Settings, then drop the icon into the list. | reuse |
| `permissions_accessibility_drag_panel_hint` | onb | Drop it into the Accessibility list above, then make sure Wispr Flow is turned on. | reuse |
| `permissions_accessibility_drag_title` | onb | Drag this icon into the Accessibility list | reuse |
| `permissions_accessibility_help_text` | onb | Flow uses this to gather context based on the application you're using, and to access your clipboard temporarily to paste text. | reuse |
| `permissions_accessibility_success_message` | onb | Flow can now paste text anywhere | reuse |
| `permissions_accessibility_title` | onb | Allow Flow to insert spoken words | reuse |
| `permissions_button_allow` | onb | Allow | reuse |
| `permissions_button_open_settings` | onb | Open Settings | reuse |
| `permissions_header_complete` | onb | Thanks for trusting us, we value your privacy | reuse |
| `permissions_header_in_progress` | onb | Give Flow permissions on your computer | reuse |
| `permissions_microphone_description` | onb | Flow will only access the mic when you are actively using it | reuse |
| `permissions_microphone_help_text` | onb | Flow will play a sound and show an animation when the mic is active | reuse |
| `permissions_microphone_success_message` | onb | Flow can now use your microphone | reuse |
| `permissions_microphone_title` | onb | Allow Flow to use your microphone | reuse |
| `permissions_notetaker_accessibility_description` | onb | Lets you start Notetaker when your meeting begins | reuse |
| `permissions_notetaker_accessibility_title` | onb | Allow Wispr to recognize meetings | reuse |
| `permissions_notetaker_header_in_progress` | onb | Give Wispr permissions on your computer | reuse |
| `permissions_notetaker_microphone_description` | onb | Capture your voice when Notetaker is active | reuse |
| `permissions_notetaker_microphone_title` | onb | Allow Wispr to use your microphone | reuse |
| `permissions_screen-capture_description` | onb | This lets Flow answer any question about what's on your screen | reuse |
| `permissions_screen-capture_help_text` | onb | Flow uses this to gather context on the application you're using to answer your questions. | reuse |
| `permissions_screen-capture_success_message` | onb | Flow can now take screenshots | reuse |
| `permissions_screen-capture_title` | onb | Allow Flow to take screenshots | reuse |
| `permissions_system-audio_button_allow` | onb | Allow | reuse |
| `permissions_system-audio_button_restart` | onb | Restart | reuse |
| `permissions_system-audio_description` | onb | Capture meeting audio for accurate transcripts | reuse |
| `permissions_system-audio_help_text` | onb | Notetaker uses this to transcribe the other participants in your meetings | reuse |
| `permissions_system-audio_restart_description` | onb | A restart is needed to capture other people's audio | reuse |
| `permissions_system-audio_restart_title` | onb | Restart Wispr Flow to finish setup | reuse |
| `permissions_system-audio_title` | onb | Allow Wispr to capture meeting audio | reuse |
| `permissions_toast_not_all_granted` | onb | Some permissions are not yet granted. Please grant all permissions to continue. | drop |
| `permissions_toast_request_timed_out` | onb | Permission request timed out. Please try again or restart the app. | reuse |
| `permissions_toast_verify_failed` | onb | Something went wrong verifying permissions. Please try again. | reuse |

#### Microphone test (33)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `microphone_test_airpods_warning` | onb | AirPods aren't the best for dictation. Click "Change microphone" to choose another option. | reuse |
| `microphone_test_button_change_mic` | onb | Change microphone | reuse |
| `microphone_test_button_speak_to_continue` | onb | Speak to continue | reuse |
| `microphone_test_button_yes` | onb | Yes | reuse |
| `microphone_test_centered_header` | onb | Test your microphone | reuse |
| `microphone_test_centered_subheading` | onb | `We recommend built-in or wired microphones.<br />Bluetooth devices are less reliable.` | reuse |
| `microphone_test_description` | onb | Your computer's built-in mic will ensure optimal transcription. | reuse |
| `microphone_test_enforcement_tooltip` | onb | We can't hear you. Try changing your mic. | reuse |
| `microphone_test_error_auto_retry_footer` | onb | We're checking your mic — we'll move on automatically when it's working. | reuse |
| `microphone_test_error_checking` | onb | Checking… | reuse |
| `microphone_test_error_choose_different_mic` | onb | Choose a different microphone | reuse |
| `microphone_test_error_not_allowed_body` | onb | Wispr needs your microphone to work. | reuse |
| `microphone_test_error_not_allowed_title` | onb | Microphone access required | reuse |
| `microphone_test_error_not_found_body` | onb | Connect a microphone or check that one is enabled. | reuse |
| `microphone_test_error_not_found_title` | onb | No microphone detected | reuse |
| `microphone_test_error_not_readable_body_1` | onb | Another app may be holding your mic. Close any of these that you have open and try again: Zoom, Microsoft Teams, Google Meet, Discord, FaceTime, or other apps that use your microphone. | reuse |
| `microphone_test_error_not_readable_body_2` | onb | Still stuck? Try selecting a different input device in settings. | reuse |
| `microphone_test_error_not_readable_title` | onb | Microphone is in use | reuse |
| `microphone_test_error_open_settings` | onb | Open Settings | reuse |
| `microphone_test_error_open_sound_settings` | onb | Open Sound Settings | reuse |
| `microphone_test_error_overconstrained_body` | onb | The mic you previously chose isn't connected. | reuse |
| `microphone_test_error_overconstrained_title` | onb | Selected microphone unavailable | reuse |
| `microphone_test_error_refresh_devices` | onb | Refresh devices | reuse |
| `microphone_test_error_restart_flow` | onb | Restart Flow | reuse |
| `microphone_test_error_unknown_body` | onb | Wispr couldn't start your microphone. | reuse |
| `microphone_test_error_unknown_title` | onb | Microphone error | reuse |
| `microphone_test_header` | onb | Test your microphone | reuse |
| `microphone_test_quick_tip_image_alt` | onb | Audio jack | reuse |
| `microphone_test_quick_tip_label` | onb | QUICK TIP | reuse |
| `microphone_test_quick_tip_text` | onb | A wired headset or desk microphone also works well for whispering with Flow | reuse |
| `microphone_test_toast_no_permission` | onb | Microphone access is required. Please enable it in Settings. | reuse |
| `microphone_test_toast_trouble` | onb | Having trouble detecting microphone? Try restarting Flow. | reuse |
| `microphone_test_widget_instruction` | onb | Do you see purple bars while you speak? | reuse |

#### Shortcut setup (21)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `shortcut_centered_header` | onb | Test your dictation shortcut | reuse |
| `shortcut_centered_header_notetaker` | onb | Test your dictation shortcut | reuse |
| `shortcut_centered_subheading` | onb | `Hold <shortcutKeys /> while you speak. Flow Dictation turns your voice to text` | reuse |
| `shortcut_description_prefix` | onb | `We recommend the ` | reuse |
| `shortcut_description_suffix_plural` | onb | ` keys at the bottom left of the keyboard.` | reuse |
| `shortcut_description_suffix_singular` | onb | ` key at the bottom left of the keyboard.` | reuse |
| `shortcut_dialog_subtitle` | onb | Choose your preferred shortcuts for using Flow. | reuse |
| `shortcut_dialog_title` | onb | Shortcuts | reuse |
| `shortcut_header` | onb | Press the keyboard shortcut to test it out | reuse |
| `shortcut_widget_alternative_label` | onb | Or use | reuse |
| `shortcut_widget_alternative_use` | onb | Use {{shortcut}} instead | reuse |
| `shortcut_widget_button_edit` | onb | Edit shortcut | reuse |
| `shortcut_widget_button_no` | onb | No | reuse |
| `shortcut_widget_button_yes` | onb | Yes | reuse |
| `shortcut_widget_caps_lock_callout` | onb | Caps Lock now starts dictation instead of turning on all caps. You can change this below or anytime in settings. | reuse |
| `shortcut_widget_instruction_plural` | onb | Do the buttons turn purple while pressing them? | reuse |
| `shortcut_widget_instruction_singular` | onb | Does the button turn purple while pressing it? | reuse |
| `shortcut_widget_keyboard_hint_plural` | onb | Press the keys on your keyboard! | reuse |
| `shortcut_widget_keyboard_hint_singular` | onb | Press the key on your keyboard! | reuse |
| `shortcut_widget_tooltip_plural` | onb | Press both shortcut buttons at the same time! | reuse |
| `shortcut_widget_tooltip_singular` | onb | Press your shortcut button to continue! | reuse |

#### Language setup (14)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `language_centered_header` | onb | Set all the languages you speak | reuse |
| `language_centered_subheading_suggestions` | onb | Flow works in 100+ languages. Pick all that apply, and mix them in one sentence. | reuse |
| `language_description_line1` | onb | Flow works in 100+ languages. | reuse |
| `language_description_line2` | onb | Select all the languages you speak or let Flow detect them automatically. | reuse |
| `language_header` | onb | Set the language(s) you speak | reuse |
| `language_widget_button_add` | onb | Add languages | reuse |
| `language_widget_button_change_multiple` | onb | Change languages | reuse |
| `language_widget_button_change_single` | onb | Change language | reuse |
| `language_widget_suggestion_add` | onb | Add {{language}} | reuse |
| `language_widget_title_any_count` | onb | Your languages | reuse |
| `language_widget_title_auto_detect` | onb | Auto-detect enabled | reuse |
| `language_widget_title_multiple` | onb | Your selected languages | reuse |
| `language_widget_title_none` | onb | No languages selected | reuse |
| `language_widget_title_single` | onb | Your selected language | reuse |

#### Try it yourself (guided practice in mock notes, email, team-chat, AI-chat and messenger apps) and tutorial video (113)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `onboarding_video_final_step_click_textbox` | onb | Click on a textbox | reuse |
| `onboarding_video_final_step_go_to_app` | onb | Go to any app | reuse |
| `onboarding_video_final_subtitle` | onb | No additional setup needed | reuse |
| `onboarding_video_final_title` | onb | Go try Flow in another app | reuse |
| `onboarding_video_finish` | onb | Finish | reuse |
| `onboarding_video_loading` | onb | Loading... | reuse |
| `onboarding_video_next` | onb | Next | reuse |
| `onboarding_video_ptt_hint_prefix` | onb | Press and hold | reuse |
| `onboarding_video_ptt_hint_suffix` | onb | to dictate. | reuse |
| `onboarding_video_skip_confirm_keep_watching` | onb | Keep watching | reuse |
| `onboarding_video_skip_confirm_subtitle` | onb | People who watch this video get 2x the value from Flow | reuse |
| `onboarding_video_skip_confirm_title` | onb | Are you sure? | reuse |
| `onboarding_video_skip_confirm_yes` | onb | Yes, skip | reuse |
| `onboarding_video_watch_subtitle` | onb | Watch a short video to get the most out of Flow | reuse |
| `onboarding_video_watch_title` | onb | Dictate in every app with Flow | reuse |
| `post_onboarding_modal_mute_video` | onb | Mute video | reuse |
| `post_onboarding_modal_title` | onb | How would you like to use Flow first? | reuse |
| `post_onboarding_modal_try_it_now_cta` | onb | Try it now | reuse |
| `post_onboarding_modal_unmute_video` | onb | Unmute video | reuse |
| `post_onboarding_typing_location_chatting_with_ai_label` | onb | Chat with AI | reuse |
| `post_onboarding_typing_location_coding_with_ai_label` | onb | Prompt Cursor or Windsurf | reuse |
| `post_onboarding_typing_location_drafting_emails_label` | onb | Draft an email | reuse |
| `post_onboarding_typing_location_sending_messages_label` | onb | Write a message | reuse |
| `post_onboarding_typing_location_taking_notes_label` | onb | Take a note | reuse |
| `post_onboarding_typing_location_writing_documents_label` | onb | Write a document | reuse |
| `post_onboarding_typing_location_writing_posts_or_comments_label` | onb | Write a post or comment | reuse |
| `post_onboarding_variant_b_more_ways_cta` | onb | More ways people use Wispr Flow | reuse |
| `post_onboarding_variant_b_preview_label` | onb | Get the most out of Wispr Flow | reuse |
| `post_onboarding_variant_b_title` | onb | `How would you like to use <0>Flow</0> first?` | reuse |
| `post_onboarding_variant_b_welcome` | onb | Welcome {{firstName}}! | reuse |
| `tiy_[ai-chat]_generating` | onb | Generating... | reuse |
| `tiy_[ai-chat]_label` | onb | Prompting AI | reuse |
| `tiy_[ai-chat]_placeholder_initial` | onb | Dictate a long brain-dump, then tap {{shortcutKeys}} to finish | reuse |
| `tiy_[ai-chat]_placeholder_message` | onb | Message [AI chat app] | reuse |
| `tiy_[ai-chat]_subtitle` | onb | `Tap <shortcutKeys /> twice to start hands-free mode.<br/>Press <shortcutKeys2 /> again when you are done dictating.` | reuse |
| `tiy_[ai-chat]_title` | onb | Try Hands-Free Mode | reuse |
| `tiy_click_textbox_first` | onb | Click on the textbox first! | reuse |
| `tiy_demo_try_saying` | onb | Try saying... | reuse |
| `tiy_gmail_cta_intro` | onb | Give it a try! | reuse |
| `tiy_gmail_gif_alt_popo` | onb | Tap shortcut to dictate with Flow hands free | reuse |
| `tiy_gmail_gif_alt_ptt` | onb | Press and hold shortcut to dictate with Flow | reuse |
| `tiy_gmail_header_accent` | onb | hands free | reuse |
| `tiy_gmail_header_prefix` | onb | Write an email | reuse |
| `tiy_gmail_header_subject_label` | onb | Subject: | reuse |
| `tiy_gmail_header_subject_value` | onb | Meeting plan | reuse |
| `tiy_gmail_header_subject_value_student` | onb | Assignment extension | reuse |
| `tiy_gmail_header_to_label` | onb | To: | reuse |
| `tiy_gmail_header_to_value_student` | onb | Professor Li | reuse |
| `tiy_gmail_label` | onb | Email | reuse |
| `tiy_gmail_placeholder_now_say` | onb | Great! Now say.... | reuse |
| `tiy_gmail_placeholder_quote` | onb | Umm Hi Greg. Let's connect soon. Are you available on Friday at 3, no actually 4? Best, {{signerFirstName}} | reuse |
| `tiy_gmail_placeholder_quote_student` | onb | Umm Hi Professor. Can I turn my assignment in on Thursday, no actually Friday? Best, {{signerFirstName}} | reuse |
| `tiy_gmail_placeholder_release` | onb | `and release <shortcutKeys />` | reuse |
| `tiy_gmail_placeholder_tap_to_finish` | onb | `Tap on <shortcutKeys /> to finish` | reuse |
| `tiy_gmail_subheading` | onb | Flow Dictation formats for you and fixes mistakes | reuse |
| `tiy_gmail_subject_label` | onb | Subject: | reuse |
| `tiy_gmail_subject_value` | onb | Quick update | reuse |
| `tiy_gmail_subtitle` | onb | `Hold down on the <shortcutKeys />, speak, and let go to insert spoken text.` | reuse |
| `tiy_gmail_subtitle_flow_instructions` | onb | Flow will punctuate and format for you. | reuse |
| `tiy_gmail_title_accent` | onb | Smart Formatting | reuse |
| `tiy_gmail_title_prefix` | onb | Try | reuse |
| `tiy_gmail_title_suffix` | onb | in Email | reuse |
| `tiy_hold_hotkey_modal_got_it` | onb | Got it! | reuse |
| `tiy_hold_hotkey_modal_text` | onb | `Don't tap. Hold down <shortcutKeys />, talk, then release!` | reuse |
| `tiy_idle_click_into_field` | onb | Click into the text field here | reuse |
| `tiy_intro_cta` | onb | Give it a try! | reuse |
| `tiy_intro_header_popo` | onb | `Flow starts listening <br /> when you double-tap <shortcutKeys />` | reuse |
| `tiy_intro_header_ptt` | onb | `Flow starts listening <br /> when you hold <shortcutKeys />` | reuse |
| `tiy_intro_subheading_popo` | onb | It'll paste in what you said when you tap again | reuse |
| `tiy_intro_subheading_ptt` | onb | It'll paste what you said when you let go | reuse |
| `tiy_messenger_demo_greeting_fallback_name` | onb | there | reuse |
| `tiy_messenger_demo_greeting_whats_up` | onb | Hey {{firstName}}, what's up? | reuse |
| `tiy_messenger_header_accent` | onb | Dictate | reuse |
| `tiy_messenger_header_prefix` | onb |  | reuse |
| `tiy_messenger_header_suffix` | onb | a message with Flow | reuse |
| `tiy_messenger_popo_placeholder` | onb | `Now say something, and tap <shortcutKeys /> to finish` | reuse |
| `tiy_messenger_ptt_hold_placeholder` | onb | `Hold down <shortcutKeys />, say something, then release.` | reuse |
| `tiy_messenger_well_done_sticker` | onb | Well done! | reuse |
| `tiy_notion_cta_intro` | onb | Next | reuse |
| `tiy_notion_fallback_sticker` | onb | Good work! | reuse |
| `tiy_notion_gif_alt` | onb | Get ready to whisper | reuse |
| `tiy_notion_header_accent` | onb | whispering | reuse |
| `tiy_notion_header_prefix` | onb | Try | reuse |
| `tiy_notion_header_suffix` | onb | a list | reuse |
| `tiy_notion_label` | onb | Whisper a note | reuse |
| `tiy_notion_page_title` | onb | Shopping list | reuse |
| `tiy_notion_page_title_student` | onb | To-do list | reuse |
| `tiy_notion_placeholder_hold_whisper` | onb | `Hold or double tap <shortcutKeys /> and whisper...` | reuse |
| `tiy_notion_placeholder_quote` | onb | I want to pick up a few things from the store: Bread, potato chips, ice cream | reuse |
| `tiy_notion_placeholder_quote_student` | onb | Here's my to-do list: Study for mid-term, do laundry, apply for club funding | reuse |
| `tiy_notion_placeholder_release_when_done` | onb | `Release <shortcutKeys /> when you're done` | reuse |
| `tiy_notion_placeholder_tap_to_finish` | onb | `Tap <shortcutKeys /> to finish` | reuse |
| `tiy_notion_subheading` | onb | Around others? Lean in closer to the mic and dictate quietly | reuse |
| `tiy_notion_subtitle` | onb | Wispr Flow will auto-format your dictation into lists depending on the context. | reuse |
| `tiy_notion_subtitle_whisper` | onb | It even understands when you whisper! | reuse |
| `tiy_notion_title` | onb | Now, get ready to whisper | reuse |
| `tiy_notion_whisper_badge` | onb | Whisper close to your mic... | reuse |
| `tiy_popo_double_tap` | onb | Double tap | reuse |
| `tiy_popo_double_tap_error` | onb | Try again, tap 2 times | reuse |
| `tiy_popo_hint` | onb | `Tap <shortcutKeys /> again when you're done speaking` | reuse |
| `tiy_ptt_hold_down` | onb | Hold down | reuse |
| `tiy_skip_button` | onb | Skip | reuse |
| `tiy_slack_demo_greeting_is_flow_working` | onb | Hey {{firstName}}, is Flow working for you? | reuse |
| `tiy_slack_input_placeholder` | onb | Hold down on the {{shortcutKeys}} and start speaking... | reuse |
| `tiy_slack_label` | onb | Message | reuse |
| `tiy_slack_subtitle` | onb | `Hold down on the <shortcutKeys />, speak, and let go to insert spoken text.` | reuse |
| `tiy_slack_title` | onb | Press the keyboard shortcut to use Flow | reuse |
| `tiy_sticker_email_formatted` | onb | Formatted! | reuse |
| `tiy_sticker_list_formatted` | onb | List created! | reuse |
| `tiy_sticker_mistakes_fixed` | onb | Mistakes fixed | reuse |
| `tiy_toast_hold_part1` | onb | Don't tap. Press and hold | reuse |
| `tiy_toast_oops` | onb | Oops, something went wrong - try again! | reuse |
| `tiy_try_again_button` | onb | Try again | reuse |

#### Personalize style (tone per app category) (63)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `personalize_card_email_casual_content_rich` | onb | `<h>H</h>i Alex<c>,</c> it was great talking with you today. <h>L</h>ooking forward to our next chat<c>.</c><br /><br />Best,<br />Mary` | reuse |
| `personalize_card_email_casual_subtitle` | onb | `Caps<br />Less punctuation` | reuse |
| `personalize_card_email_casual_title` | onb | Casual | reuse |
| `personalize_card_email_excited_content_rich` | onb | `<h>H</h>i Alex<c>,</c><br /><br /><h>I</h>t was great talking with you today. <h>L</h>ooking forward to our next chat<clg>!</clg><br /><br />Best,<br />Mary` | reuse |
| `personalize_card_email_excited_subtitle` | onb | `Caps<br />Less punctuation` | reuse |
| `personalize_card_email_excited_title` | onb | Excited! | reuse |
| `personalize_card_email_formal_content_rich` | onb | `<h>H</h>i Alex<c>,</c><br /><br /><h>I</h>t was great talking with you today. <h>L</h>ooking forward to our next chat<c>.</c><br /><br />Best,<br />Mary` | reuse |
| `personalize_card_email_formal_subtitle` | onb | `Caps<br />Punctuation` | reuse |
| `personalize_card_email_formal_title` | onb | Formal | reuse |
| `personalize_card_other_casual_content_rich` | onb | `<h>So</h> far <h>I’m</h> enjoying the new workout routine.<br /><br /><h>I’m</h> excited for tomorrow’s workout especially after a full night of rest.` | reuse |
| `personalize_card_other_casual_subtitle` | onb | `Caps<br />Less punctuation` | reuse |
| `personalize_card_other_casual_title` | onb | Casual | reuse |
| `personalize_card_other_excited_content_rich` | onb | `<h>So</h> far<c>,</c> <h>I’m</h> enjoying the new workout routine.<br /><br /><h>I’m</h> excited for tomorrow’s workout<c>,</c> especially after a full night of rest<clg>!</clg>` | reuse |
| `personalize_card_other_excited_subtitle` | onb | More exclamations! | reuse |
| `personalize_card_other_excited_title` | onb | Excited! | reuse |
| `personalize_card_other_formal_content_rich` | onb | `<h>So</h> far<c>,</c> <h>I am</h> enjoying the new workout routine.<br /><br /><h>I am</h> excited for tomorrow’s workout<c>,</c> especially after a full night of rest.` | reuse |
| `personalize_card_other_formal_subtitle` | onb | `Caps<br />Punctuation` | reuse |
| `personalize_card_other_formal_title` | onb | Formal | reuse |
| `personalize_card_personal_casual_content_rich` | onb | `<h>H</h>ey are you free for lunch tomorrow? <h>L</h>et’s do 12 if that works for you` | reuse |
| `personalize_card_personal_casual_subtitle` | onb | `Caps<br />Less punctuation` | reuse |
| `personalize_card_personal_casual_title` | onb | Casual | reuse |
| `personalize_card_personal_formal_content_rich` | onb | `<h>H</h>ey<c>,</c> are you free for lunch tomorrow? <h>L</h>et’s do 12 if that works for you<c>.</c>` | reuse |
| `personalize_card_personal_formal_subtitle` | onb | `Caps<br />Punctuation` | reuse |
| `personalize_card_personal_formal_title` | onb | Formal | reuse |
| `personalize_card_personal_veryCasual_content_rich` | onb | `<h>h</h>ey are you free for lunch tomorrow? <h>l</h>et’s do 12 if that works for you` | reuse |
| `personalize_card_personal_veryCasual_subtitle` | onb | `No caps<br />Less punctuation` | reuse |
| `personalize_card_personal_veryCasual_title` | onb | very casual | reuse |
| `personalize_card_work_casual_content_rich` | onb | `<h>H</h>ey<c>,</c> if you’re free let’s chat about the great results` | reuse |
| `personalize_card_work_casual_subtitle` | onb | `Caps<br />Less punctuation` | reuse |
| `personalize_card_work_casual_title` | onb | Casual | reuse |
| `personalize_card_work_excited_content_rich` | onb | `<h>H</h>ey<c>,</c> if you’re free<c>,</c> let’s chat about the great results<clg>!</clg>` | reuse |
| `personalize_card_work_excited_subtitle` | onb | `Caps<br />Less punctuation` | reuse |
| `personalize_card_work_excited_title` | onb | Excited! | reuse |
| `personalize_card_work_formal_content_rich` | onb | `<h>H</h>ey<c>,</c> if you’re free<c>,</c> let’s chat about the great results<c>.</c>` | reuse |
| `personalize_card_work_formal_subtitle` | onb | `Caps<br />Punctuation` | reuse |
| `personalize_card_work_formal_title` | onb | Formal | reuse |
| `personalize_intro_description` | onb | Choose how Wispr Flow formats your dictations in different apps | reuse |
| `personalize_intro_header` | onb | `Next, let's personalize <accent>your</accent> Flow` | reuse |
| `personalize_intro_image_alt` | onb | Girl with mirror | reuse |
| `personalize_intro_set_up_later` | onb | Set up later | reuse |
| `personalize_style_email_heading_prefix` | onb | How do you write your | reuse |
| `personalize_style_email_heading_word` | onb | emails | reuse |
| `personalize_style_email_right_subheader` | onb | and more | reuse |
| `personalize_style_email_subtitle` | onb | We'll apply this style to emails | reuse |
| `personalize_style_other_heading_prefix` | onb | How do you write in | reuse |
| `personalize_style_other_heading_word` | onb | other types of apps | reuse |
| `personalize_style_other_right_subheader` | onb | and more | reuse |
| `personalize_style_other_subtitle` | onb | We'll apply this style to all other apps | reuse |
| `personalize_style_personal_heading_prefix` | onb | How do you write your | reuse |
| `personalize_style_personal_heading_word` | onb | personal messages | reuse |
| `personalize_style_personal_right_subheader` | onb | and more | reuse |
| `personalize_style_personal_subtitle` | onb | We'll apply this style to personal messages | reuse |
| `personalize_style_skip` | onb | Skip | reuse |
| `personalize_style_work_heading_prefix` | onb | How do you write your | reuse |
| `personalize_style_work_heading_word` | onb | work messages | reuse |
| `personalize_style_work_right_subheader` | onb | and more | reuse |
| `personalize_style_work_subtitle` | onb | We'll apply this style to work messages | reuse |
| `onboarding_personalize_and_more` | ntf | and more | reuse |
| `onboarding_personalize_email_subtitle` | ntf | We’ll apply this style to emails | reuse |
| `onboarding_personalize_other_subtitle` | ntf | We’ll apply this style to all other apps | reuse |
| `onboarding_personalize_personal_subtitle` | ntf | We’ll apply this style to personal messages | reuse |
| `onboarding_personalize_skip` | ntf | Skip | reuse |
| `onboarding_personalize_work_subtitle` | ntf | We’ll apply this style to work messages | reuse |

#### Speed and time savings (typing test, words per minute) (26)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `speed_comparison_avg_typing_label` | onb | Avg typing speed | reuse |
| `speed_comparison_continue` | onb | Continue | reuse |
| `speed_comparison_faster` | onb | faster | reuse |
| `speed_comparison_multiplier_subtitle` | onb | than the average typing speed | reuse |
| `speed_comparison_subtitle_above_threshold` | onb | You just spoke | reuse |
| `speed_comparison_subtitle_below_threshold` | onb | Speaking can be | reuse |
| `speed_comparison_title` | onb | Nice job! | reuse |
| `speed_comparison_words_per_min` | onb | {{count}} words/min | reuse |
| `speed_comparison_your_voice` | onb | Your voice | reuse |
| `speed_comparison_your_voice_named` | onb | {{name}}'s voice | reuse |
| `time_savings_a_week` | onb | a week! | reuse |
| `time_savings_continue` | onb | Continue | reuse |
| `time_savings_finish` | onb | Finish | reuse |
| `time_savings_hours_label` | onb | hours | reuse |
| `time_savings_slider_label` | onb | Typing time/day | reuse |
| `time_savings_subtitle` | onb | With Flow you could save | reuse |
| `time_savings_test_typing_speed` | onb | Don't believe us? Test your typing speed | reuse |
| `time_savings_unit_plural` | onb | hours | reuse |
| `time_savings_unit_singular` | onb | hour | reuse |
| `typing_test_modal_language_hint` | onb | Wispr works in 100+ languages | reuse |
| `typing_test_modal_recalculate` | onb | Recalculate time savings | reuse |
| `typing_test_modal_seconds_left` | onb | seconds left | reuse |
| `typing_test_modal_speaking_wpm` | onb | speaking words/min | reuse |
| `typing_test_modal_title` | onb | `Can you type faster than you <em>dictate?</em>` | reuse |
| `typing_test_modal_try_again` | onb | Try Again | reuse |
| `typing_test_modal_typing_wpm` | onb | typing words/min | reuse |

### Permissions recovery

#### Revoked or missing permissions, blocked input (15)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `accessibility_permission_revoked_action_open_settings` | ntf | Open Settings | reuse |
| `accessibility_permission_revoked_body` | ntf | Flow needs accessibility access to work properly. | reuse |
| `accessibility_permission_revoked_title` | ntf | Accessibility Permission Required | reuse |
| `mic_access_error_action_troubleshoot` | ntf | Troubleshoot | reuse |
| `mic_access_error_body` | ntf | Flow couldn't start your microphone. Try reconnecting the microphone. Contact support if this issue persists. | rewrite |
| `mic_access_error_title` | ntf | Microphone error | reuse |
| `mic_access_timeout_action_restart` | ntf | Restart App | reuse |
| `mic_access_timeout_body` | ntf | Flow is having trouble accessing your microphone. | reuse |
| `mic_access_timeout_title` | ntf | Unable to access mic | reuse |
| `microphone_permission_revoked_action_grant` | ntf | Grant Permission | drop |
| `microphone_permission_revoked_body` | ntf | Flow needs microphone access to work. | reuse |
| `microphone_permission_revoked_title` | ntf | Microphone Permission Required | reuse |
| `paste_failed_title` | ntf | Click a textbox and use {{shortcut}} to paste | reuse |
| `secure_input_blocked_body` | ntf | {{appName}} has Secure Keyboard Entry turned on, which blocks Flow's shortcuts. This is due to a bug in 1Password. Quit and restart 1Password to clear the issue. | reuse |
| `secure_input_blocked_title` | ntf | Flow's shortcuts are blocked | reuse |

### Hub (main window)

#### Sidebar, navigation, frame, home, help menu, shared controls (103)

`notifications_modal_*` is the in-app notification inbox (bell). `hub_banner_*` are dismissible home banners.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_banner_mouse_flow_cta` | ntf | Get started | reuse |
| `hub_banner_mouse_flow_description` | ntf | Keyboards? Who needs them! | reuse |
| `hub_banner_mouse_flow_title` | ntf | Flow using your mouse | reuse |
| `hub_banner_scratchpad_cta` | ntf | Start new note | reuse |
| `hub_banner_scratchpad_description` | ntf | Drop a to-do list, polish a message before you send it, brain dump an idea. Scratchpad is your safe space to save, create, and explore. | reuse |
| `hub_banner_scratchpad_title` | ntf | For quick thoughts you want to come back to | reuse |
| `hub_banner_tagging_cta` | ntf | Get started | reuse |
| `hub_banner_tagging_description` | ntf | Flow automatically tags the right files and variables in Cursor and Windsurf. | reuse |
| `hub_banner_tagging_title` | ntf | `` Tag @files and `variables` `` | reuse |
| `notifications_modal_archive` | ntf | Archive | reuse |
| `notifications_modal_archive_all` | ntf | Archive all | reuse |
| `notifications_modal_caught_up_body` | ntf | We'll ping you when there's something exciting again. | reuse |
| `notifications_modal_caught_up_title` | ntf | You're all caught up! | reuse |
| `notifications_modal_empty_body` | ntf | You'll see tips, milestones, and new features announcements here | reuse |
| `notifications_modal_empty_title` | ntf | No notifications yet | reuse |
| `notifications_modal_filter_archived` | ntf | Archived | reuse |
| `notifications_modal_filter_new` | ntf | New | reuse |
| `notifications_modal_mark_all_read` | ntf | Mark all as read | reuse |
| `notifications_modal_title` | ntf | Notifications | reuse |
| `hub_banner_dismiss_aria` | hub | Dismiss | reuse |
| `hub_combobox_remove_chip_label` | hub | Remove {{name}} | reuse |
| `hub_combobox_trigger_label` | hub | Show options | reuse |
| `hub_common_back` | hub | Back | reuse |
| `hub_common_chat_history_aria` | hub | Chat history | reuse |
| `hub_common_delete` | hub | Delete | reuse |
| `hub_common_helpful_aria` | hub | Helpful | reuse |
| `hub_common_more_options` | hub | More options | reuse |
| `hub_common_not_helpful_aria` | hub | Not helpful | reuse |
| `hub_common_preview` | hub | Preview | reuse |
| `hub_common_rename` | hub | Rename | reuse |
| `hub_common_retry` | hub | Retry | reuse |
| `hub_common_search_aria` | hub | Search | reuse |
| `hub_common_search_clear_aria` | hub | Clear search | reuse |
| `hub_common_today` | hub | Today | reuse |
| `hub_common_upcoming_meetings_section_aria` | hub | Upcoming meetings | reuse |
| `hub_dark_mode_coachmark_card_close` | hub | Dismiss | reuse |
| `hub_dark_mode_coachmark_card_cta` | hub | Try it out | reuse |
| `hub_dark_mode_coachmark_card_subtitle` | hub | You asked - we answered. Enjoy! | reuse |
| `hub_dark_mode_coachmark_card_title` | hub | Dark mode is finally here | reuse |
| `hub_frame_notifications_aria` | hub | Notifications | reuse |
| `hub_help_item_help_center` | hub | Help Center | reuse |
| `hub_help_item_languages` | hub | Languages | reuse |
| `hub_help_item_microphone` | hub | Microphone | reuse |
| `hub_help_item_shortcuts` | hub | Shortcuts | reuse |
| `hub_help_item_talk_to_support` | hub | Talk to support | reuse |
| `hub_help_item_whats_new` | hub | What's New | reuse |
| `hub_help_menu_aria_label` | hub | Help menu | reuse |
| `hub_help_section_essentials` | hub | Essentials | reuse |
| `hub_help_section_get_in_touch` | hub | Get in touch | reuse |
| `hub_help_section_updates` | hub | Updates | reuse |
| `hub_home_notetaker_empty_cta` | hub | Get started | reuse |
| `hub_home_notetaker_empty_description` | hub | Never miss a detail with accurate transcripts and summaries | reuse |
| `hub_home_notetaker_empty_title` | hub | Capture meetings with Notetaker | reuse |
| `hub_home_notetaker_widget_hide` | hub | Hide | reuse |
| `hub_home_notetaker_widget_options` | hub | Options | reuse |
| `hub_home_notetaker_widget_see_all` | hub | See all | reuse |
| `hub_home_notetaker_widget_settings` | hub | Settings | reuse |
| `hub_home_notetaker_widget_show` | hub | Show Notetaker | reuse |
| `hub_home_welcome_back` | hub | Welcome back, {{firstName}} | reuse |
| `hub_home_welcome_gated` | hub | Welcome, {{firstName}} | reuse |
| `hub_home_welcome_get_back` | hub | `Hey {{firstName}}, get back into the flow with <shortcut></shortcut>` | reuse |
| `hub_navsection_archive_all_error_toast` | hub | Failed to archive all notifications | reuse |
| `hub_navsection_archive_error_toast` | hub | Failed to archive notification | reuse |
| `hub_navsection_mark_all_read_error_toast` | hub | Failed to mark all notifications as read | reuse |
| `hub_navsection_notifications_label` | hub | Notifications | reuse |
| `hub_navsection_settings_label` | hub | Settings | reuse |
| `hub_sidebar_dictionary_label` | hub | Dictionary | reuse |
| `hub_sidebar_help_label` | hub | Help | reuse |
| `hub_sidebar_home_label` | hub | Dictation | reuse |
| `hub_sidebar_home_redesign_label` | hub | Home | reuse |
| `hub_sidebar_insights_label` | hub | Insights | reuse |
| `hub_sidebar_main_nav_aria` | hub | Main navigation | reuse |
| `hub_sidebar_meetings_label` | hub | Notetaker | reuse |
| `hub_sidebar_microphone_dialog_title` | hub | Microphone | reuse |
| `hub_sidebar_my_voice_label` | hub | My Voice | reuse |
| `hub_sidebar_notes_label` | hub | Scratchpad | reuse |
| `hub_sidebar_secondary_nav_aria` | hub | Secondary navigation | reuse |
| `hub_sidebar_settings_label` | hub | Settings | reuse |
| `hub_sidebar_shortcuts_dialog_subtitle` | hub | Customize how you interact with Flow | reuse |
| `hub_sidebar_shortcuts_dialog_title` | hub | Change hotkeys | reuse |
| `hub_sidebar_shortcuts_label` | hub | Shortcuts | reuse |
| `hub_sidebar_snippets_label` | hub | Snippets | reuse |
| `hub_sidebar_style_label` | hub | Style | reuse |
| `hub_sidebar_tasks_label` | hub | My Tasks | reuse |
| `hub_sidebar_transforms_label` | hub | Transforms | reuse |
| `hub_tab_container_beta` | hub | Beta | reuse |
| `hub_tab_container_coming_soon` | hub | Coming soon | reuse |
| `hub_typing_location_chatting_with_ai_description` | hub | Ask questions and ideate quickly | reuse |
| `hub_typing_location_chatting_with_ai_label` | hub | Chat with AI | reuse |
| `hub_typing_location_coding_with_ai_description` | hub | Ship code hands-free | reuse |
| `hub_typing_location_coding_with_ai_label` | hub | Prompt Cursor or Windsurf | reuse |
| `hub_typing_location_drafting_emails_description` | hub | Get through your inbox faster | reuse |
| `hub_typing_location_drafting_emails_label` | hub | Draft an email | reuse |
| `hub_typing_location_sending_messages_description` | hub | Stay in touch without typing | reuse |
| `hub_typing_location_sending_messages_label` | hub | Write a message | reuse |
| `hub_typing_location_something_else_description` | hub | Explore new ways to flow | reuse |
| `hub_typing_location_something_else_label` | hub | Something else | reuse |
| `hub_typing_location_taking_notes_description` | hub | Capture thoughts and to-dos | reuse |
| `hub_typing_location_taking_notes_label` | hub | Take a note | reuse |
| `hub_typing_location_writing_documents_description` | hub | Move long-form work forward | reuse |
| `hub_typing_location_writing_documents_label` | hub | Write a document | reuse |
| `hub_typing_location_writing_posts_or_comments_description` | hub | Share updates effortlessly | reuse |
| `hub_typing_location_writing_posts_or_comments_label` | hub | Write a post or comment | reuse |

#### History (108)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `history_cancelled_tooltip` | ntf | This transcription was cancelled. To recover, go to options and click retry. | reuse |
| `history_menu_cancel` | ntf | Cancel | reuse |
| `history_menu_confirm_delete` | ntf | Yes, delete it | reuse |
| `history_menu_delete_transcript` | ntf | Delete transcript | reuse |
| `history_menu_extract_audio` | ntf | Extract audio | reuse |
| `history_menu_redo_ai_edit` | ntf | Redo AI edit | reuse |
| `history_menu_retry_transcript` | ntf | Retry transcript | reuse |
| `history_menu_tooltip_copy` | ntf | Copy transcript | reuse |
| `history_menu_tooltip_feedback` | ntf | Send feedback | reuse |
| `history_menu_tooltip_more` | ntf | More options | reuse |
| `history_menu_undo_ai_edit` | ntf | Undo AI edit | reuse |
| `history_menu_view_history_row` | ntf | View history row | reuse |
| `history_retry_audio_unavailable_error` | ntf | Cannot retry transcription as audio is no longer available (older than 14 days) | reuse |
| `history_retry_failed_error` | ntf | Retry failed. Please try again. | reuse |
| `history_retry_while_dictating_error` | ntf | Cannot retry while dictating | reuse |
| `transcript_cancelled_action_undo` | ntf | Undo | reuse |
| `transcript_cancelled_detailed_action_open_history` | ntf | Open History | reuse |
| `transcript_cancelled_detailed_action_undo` | ntf | Undo | reuse |
| `transcript_cancelled_detailed_body` | ntf | We noticed you cancelled your transcription | reuse |
| `transcript_cancelled_detailed_title` | ntf | You can recover your cancelled transcript | reuse |
| `transcript_cancelled_title` | ntf | Transcript cancelled | reuse |
| `transcription_empty_action_select_microphone` | ntf | Select microphone | reuse |
| `transcription_empty_action_troubleshoot` | ntf | Troubleshoot | reuse |
| `transcription_empty_body` | ntf | We didn't pick up any speech from your {{micLabel}} microphone | reuse |
| `transcription_empty_title` | ntf | We couldn't hear you | reuse |
| `transcription_error_action_open_history` | ntf | Open History | reuse |
| `transcription_error_action_retry` | ntf | Retry | reuse |
| `transcription_error_body` | ntf | Transcript failed to load. You can always recover it from History. | reuse |
| `transcription_error_title` | ntf | Something's not right | reuse |
| `hub_history_action_copy_tooltip` | hub | Copy transcript | reuse |
| `hub_history_action_pause_tooltip` | hub | Pause audio | reuse |
| `hub_history_action_play_tooltip` | hub | Play audio | reuse |
| `hub_history_action_report_tooltip` | hub | Send feedback | reuse |
| `hub_history_audio_silent` | hub | Audio is silent. | reuse |
| `hub_history_audio_silent_tooltip` | hub | Flow didn't detect any words in the dictation, which is why this transcription is empty. | reuse |
| `hub_history_delete_dialog_cancel` | hub | Cancel | reuse |
| `hub_history_delete_dialog_confirm` | hub | Yes, delete it | reuse |
| `hub_history_delete_dialog_subtitle` | hub | Once deleted it cannot be recovered | reuse |
| `hub_history_delete_dialog_title` | hub | Are you sure you want to delete this transcript? | reuse |
| `hub_history_disabled_body_enterprise` | hub | Your organization has disabled the retention of your dictation history. | drop |
| `hub_history_disabled_body_user` | hub | `Data storage is set to never store data. You can change this in Settings > Data and Privacy.` | reuse |
| `hub_history_disabled_title` | hub | History disabled | reuse |
| `hub_history_dismissed_message` | hub | The transcription was dismissed. | reuse |
| `hub_history_dismissed_prefix` | hub | `This transcription was dismissed. ` | reuse |
| `hub_history_dismissed_tooltip` | hub | This transcription was cancelled. To recover, go to options and click retry. | reuse |
| `hub_history_empty_body` | hub | Once you dictate across different apps, your entire dictation history will appear here. | reuse |
| `hub_history_empty_title` | hub | No dictations yet | reuse |
| `hub_history_instruct_row_dialog_subtitle` | hub | Dictation and instruct-history records (internal use) | reuse |
| `hub_history_instruct_row_dialog_title` | hub | History Row Data | reuse |
| `hub_history_instruct_row_load_failed` | hub | Failed to load instruct history row | reuse |
| `hub_history_list_aria` | hub | Dictation history | reuse |
| `hub_history_menu_cannot_retry_title` | hub | Cannot retry while dictating | reuse |
| `hub_history_menu_delete_transcript` | hub | Delete transcript | reuse |
| `hub_history_menu_extract_audio` | hub | Extract audio | reuse |
| `hub_history_menu_open_ax_inspector` | hub | Open in AX inspector | reuse |
| `hub_history_menu_redo_ai_edit` | hub | Redo AI edit | reuse |
| `hub_history_menu_retry_transcript` | hub | Retry transcript | reuse |
| `hub_history_menu_undo_ai_edit` | hub | Undo AI edit | reuse |
| `hub_history_menu_view_history_row` | hub | View history row | reuse |
| `hub_history_no_microphone` | hub | Couldn't access your microphone. | reuse |
| `hub_history_recover_link` | hub | Recover | reuse |
| `hub_history_report_dialog_placeholder` | hub | Describe what you expected instead | reuse |
| `hub_history_report_dialog_submit` | hub | Send feedback | reuse |
| `hub_history_report_dialog_subtitle` | hub | Thanks for the feedback to help improve our model. If you'd like a reply, please visit our Help Center. | reuse |
| `hub_history_report_dialog_title` | hub | Report to Improve Model | reuse |
| `hub_history_retry_estimate_minutes` | hub | This may take ~{{minutes}} min | reuse |
| `hub_history_retry_estimate_seconds` | hub | This may take ~{{seconds}}s | reuse |
| `hub_history_retry_your` | hub | ` your transcription` | reuse |
| `hub_history_retry_your_duration` | hub | ` your {{duration}} transcription` | reuse |
| `hub_history_row_close_button` | hub | Close | reuse |
| `hub_history_row_dialog_subtitle` | hub | Full transcript details (internal use) | reuse |
| `hub_history_row_dialog_title` | hub | History Row Data | reuse |
| `hub_history_row_load_failed` | hub | Failed to load history row | reuse |
| `hub_history_row_loading` | hub | Loading... | reuse |
| `hub_history_row_tab_dictation` | hub | Dictation | reuse |
| `hub_history_row_tab_instruct` | hub | Instruct | reuse |
| `hub_history_row_view_toggle_aria` | hub | History row source | reuse |
| `hub_history_search_aria` | hub | Search past transcripts | reuse |
| `hub_history_search_loading` | hub | Searching your history… | reuse |
| `hub_history_search_no_results` | hub | No transcripts found for "{{query}}" | reuse |
| `hub_history_search_placeholder` | hub | Search past transcripts | reuse |
| `hub_history_section_yesterday` | hub | Yesterday | reuse |
| `hub_history_time_am` | hub | am | reuse |
| `hub_history_time_pm` | hub | pm | reuse |
| `hub_history_time_unknown` | hub | 12:00am | reuse |
| `hub_history_toast_audio_unavailable_download` | hub | Cannot download audio as it is no longer available (older than 14 days) | reuse |
| `hub_history_toast_audio_unavailable_play` | hub | Can't play audio because it's no longer available (older than 14 days) | reuse |
| `hub_history_toast_audio_unavailable_retry` | hub | Cannot retry transcription as audio is no longer available (older than 14 days) | reuse |
| `hub_history_toast_audio_unavailable_unexpected` | hub | Cannot download audio as it is no longer available (unexpected error) | reuse |
| `hub_history_toast_ax_inspector_failed` | hub | Couldn't open AX inspector | reuse |
| `hub_history_toast_cannot_retry_dictating` | hub | Cannot retry while dictating | reuse |
| `hub_history_toast_cannot_retry_dictating_period` | hub | Cannot retry while dictating. | reuse |
| `hub_history_toast_paste_with_shortcut` | hub | You can also paste your last transcript with {{shortcut}} | reuse |
| `hub_history_toast_report_failed` | hub | Failed to send report. Please try again or notify support. | reuse |
| `hub_history_toast_report_sent` | hub | Report sent! | reuse |
| `hub_history_toast_retry_failed` | hub | Retry failed. Please try again. | reuse |
| `hub_history_toast_sending_report` | hub | Sending report... | reuse |
| `hub_history_toast_transcript_archived` | hub | Transcript archived | reuse |
| `hub_history_toast_transcript_copied` | hub | Transcript copied | reuse |
| `hub_history_toast_transcript_copy_failed` | hub | Couldn't copy transcript. Try again. | reuse |
| `hub_history_toast_transcript_deleted` | hub | Transcript deleted | reuse |
| `hub_history_toast_transcript_empty` | hub | Transcript is empty | reuse |
| `hub_history_toast_transcript_unarchived` | hub | Transcript unarchived | reuse |
| `hub_history_transcript_interrupted` | hub | Your transcription was interrupted. But Flow can still retry it for you. | reuse |
| `hub_inline_report_category_important_word` | hub | Important word transcribed incorrectly | reuse |
| `hub_inline_report_category_name` | hub | Name transcribed incorrectly | reuse |
| `hub_inline_report_category_other` | hub | Other | reuse |
| `hub_inline_report_category_wrong_language` | hub | Wrong language | reuse |

#### Dictionary (115)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_system_auto_add_dictionary_description` | set | Adds corrected words automatically | reuse |
| `settings_system_auto_add_dictionary_label` | set | Auto-add to dictionary | reuse |
| `feature_notif_dictionary_action_view_dictionary` | ntf | View dictionary | reuse |
| `learned_dictionary_words_action_undo` | ntf | Undo | reuse |
| `learned_dictionary_words_title` | ntf | Added {{terms}} to your Dictionary | reuse |
| `hub_banner_dictionary_body` | hub | `Correct a spelling once or add it here manually, so your <1>personal terms, company jargon, or uncommon names</1> are spelled right in both dictations and meeting notes.` | reuse |
| `hub_banner_dictionary_cta_add_new_word` | hub | Add new word | reuse |
| `hub_banner_dictionary_team_join_others_one` | hub | Join {{count}} other at {{teamName}} to access your organization’s dictionary. | drop |
| `hub_banner_dictionary_team_join_others_other` | hub | Join {{count}} others at {{teamName}} to access your organization’s dictionary. | drop |
| `hub_banner_dictionary_team_upsell_title` | hub | `The words <1>your team</1> shouldn’t have to repeat.` | drop |
| `hub_banner_dictionary_title_team` | hub | `Flow spells the way <1>your team</1> does.` | drop |
| `hub_banner_dictionary_title_you` | hub | `Flow spells the way <1>you</1> do.` | reuse |
| `hub_bulk_import_dictionary_duplicate_text` | hub | dictionary | reuse |
| `hub_bulk_import_dictionary_empty_error` | hub | No dictionary items found in file | reuse |
| `hub_bulk_import_dictionary_item_noun` | hub | item | reuse |
| `hub_bulk_import_dictionary_item_noun_plural` | hub | items | reuse |
| `hub_bulk_import_dictionary_loading_text` | hub | Importing dictionary items... | reuse |
| `hub_bulk_import_dictionary_preview_count_label` | hub | items detected | reuse |
| `hub_bulk_import_dictionary_preview_subtitle` | hub | Confirm dictionary items are ready for import, and we'll add them to your dictionary. | reuse |
| `hub_bulk_import_dictionary_title` | hub | Dictionary | reuse |
| `hub_dictionary_add_new_button` | hub | Add new | reuse |
| `hub_dictionary_auto_learned_tooltip` | hub | Flow learned this word automatically ✨ | reuse |
| `hub_dictionary_bulk_delete_confirm_body_one` | hub | The selected word will be deleted permanently. | reuse |
| `hub_dictionary_bulk_delete_confirm_body_other` | hub | The selected words will be deleted permanently. | reuse |
| `hub_dictionary_bulk_delete_confirm_title_one` | hub | Delete {{count}} word? | reuse |
| `hub_dictionary_bulk_delete_confirm_title_other` | hub | Delete {{count}} words? | reuse |
| `hub_dictionary_bulk_delete_one` | hub | Delete {{count}} | reuse |
| `hub_dictionary_bulk_delete_other` | hub | Delete {{count}} | reuse |
| `hub_dictionary_bulk_share_count_department_one` | hub | Share {{count}} with department | drop |
| `hub_dictionary_bulk_share_count_department_other` | hub | Share {{count}} with department | drop |
| `hub_dictionary_bulk_share_count_one` | hub | Share {{count}} with team | reuse |
| `hub_dictionary_bulk_share_count_other` | hub | Share {{count}} with team | reuse |
| `hub_dictionary_bulk_toolbar_aria` | hub | Bulk actions | reuse |
| `hub_dictionary_dialog_cancel` | hub | Cancel | reuse |
| `hub_dictionary_dialog_confirm_delete` | hub | Yes, delete it | reuse |
| `hub_dictionary_dialog_delete_org_title` | hub | Delete from organization vocabulary? | drop |
| `hub_dictionary_dialog_delete_personal_title` | hub | Delete from personal vocabulary? | reuse |
| `hub_dictionary_dialog_delete_subtitle` | hub | '{{phrase}}' will be deleted permanently. | reuse |
| `hub_dictionary_dialog_delete_team_title` | hub | Delete from team vocabulary? | drop |
| `hub_dictionary_dialog_delete_team_title_department` | hub | Delete from department vocabulary? | drop |
| `hub_dictionary_dialog_edit_replacement_title` | hub | Edit replacement | reuse |
| `hub_dictionary_dialog_edit_word_title` | hub | Edit word | reuse |
| `hub_dictionary_dialog_save_changes` | hub | Save changes | reuse |
| `hub_dictionary_edit_correct_spelling_placeholder` | hub | Correct spelling | reuse |
| `hub_dictionary_edit_misspelling_placeholder` | hub | Misspelling | reuse |
| `hub_dictionary_edit_tooltip` | hub | Edit | reuse |
| `hub_dictionary_edit_word_placeholder` | hub | Edit word | reuse |
| `hub_dictionary_import_button` | hub | Import | reuse |
| `hub_dictionary_last_synced_tooltip` | hub | Dictionary last synced {{relativeTime}} | drop |
| `hub_dictionary_modal_add_cta` | hub | Add word | reuse |
| `hub_dictionary_modal_add_title` | hub | Add to vocabulary | reuse |
| `hub_dictionary_modal_add_word_placeholder` | hub | Add a new word | reuse |
| `hub_dictionary_modal_correct_misspelling` | hub | Correct a misspelling | reuse |
| `hub_dictionary_modal_correct_misspelling_tooltip` | hub | When enabled, this turns your custom word into a correction rule. Flow will automatically replace the incorrect version whenever it’s dictated. | reuse |
| `hub_dictionary_modal_share_with_team_disabled_tooltip` | hub | To share vocabulary with your team, go to Settings and set up a team. | drop |
| `hub_dictionary_modal_share_with_team_tooltip` | hub | Adds this word to your team's shared dictionary. | drop |
| `hub_dictionary_modal_share_with_team_tooltip_department` | hub | Adds this word to your department's shared dictionary. Other departments in your organization won't see it. | drop |
| `hub_dictionary_no_results_body` | hub | No words found matching your search | reuse |
| `hub_dictionary_no_results_title` | hub | No results found | reuse |
| `hub_dictionary_search_placeholder` | hub | Search your vocabulary | reuse |
| `hub_dictionary_search_tooltip` | hub | Search vocabulary | reuse |
| `hub_dictionary_sort_alphabetical` | hub | Alphabetical (A-Z) | reuse |
| `hub_dictionary_sort_menu_title` | hub | Sort by | reuse |
| `hub_dictionary_sort_newest_first` | hub | Newest first | reuse |
| `hub_dictionary_sort_oldest_first` | hub | Oldest first | reuse |
| `hub_dictionary_sort_starred_first` | hub | Starred first | reuse |
| `hub_dictionary_sort_tooltip` | hub | Sort by | reuse |
| `hub_dictionary_star_tooltip` | hub | Star | reuse |
| `hub_dictionary_sync_tooltip` | hub | Sync dictionary | drop |
| `hub_dictionary_title` | hub | Dictionary | reuse |
| `hub_dictionary_toast_add_error` | hub | An error occurred while adding the word. Please try again or contact support. | reuse |
| `hub_dictionary_toast_added` | hub | "{{word}}" added successfully | reuse |
| `hub_dictionary_toast_added_pending` | hub | "{{word}}" is awaiting admin approval before your team can use it | drop |
| `hub_dictionary_toast_added_pending_department` | hub | "{{word}}" is awaiting admin approval before your department can use it | drop |
| `hub_dictionary_toast_added_replacement` | hub | "{{word}}" added successfully as a replacement for "{{misspelling}}" | reuse |
| `hub_dictionary_toast_added_replacement_pending` | hub | "{{word}}" is awaiting admin approval before your team can use it as a replacement for "{{misspelling}}" | drop |
| `hub_dictionary_toast_added_replacement_pending_department` | hub | "{{word}}" is awaiting admin approval before your department can use it as a replacement for "{{misspelling}}" | drop |
| `hub_dictionary_toast_bulk_delete_failed_one` | hub | Failed to delete {{count}} word | reuse |
| `hub_dictionary_toast_bulk_delete_failed_other` | hub | Failed to delete {{count}} words | reuse |
| `hub_dictionary_toast_bulk_deleted_one` | hub | Deleted {{count}} word | reuse |
| `hub_dictionary_toast_bulk_deleted_other` | hub | Deleted {{count}} words | reuse |
| `hub_dictionary_toast_correction_already_exists` | hub | "{{word}}" already has a correction | reuse |
| `hub_dictionary_toast_delete_failed` | hub | "{{word}}" could not be deleted | reuse |
| `hub_dictionary_toast_deleted` | hub | "{{word}}" deleted | reuse |
| `hub_dictionary_toast_move_to_team_failed` | hub | "{{word}}" could not be moved to teams vocabulary, please try again. | drop |
| `hub_dictionary_toast_move_to_team_failed_department` | hub | "{{word}}" could not be moved to department vocabulary, please try again. | drop |
| `hub_dictionary_toast_move_to_team_pending` | hub | "{{word}}" is awaiting admin approval — it stays in your personal dictionary until then | drop |
| `hub_dictionary_toast_moved_to_team` | hub | "{{word}}" moved to teams vocabulary | drop |
| `hub_dictionary_toast_moved_to_team_department` | hub | "{{word}}" moved to department vocabulary | drop |
| `hub_dictionary_toast_moving_to_team` | hub | Moving "{{word}}" to teams vocabulary... | drop |
| `hub_dictionary_toast_moving_to_team_department` | hub | Moving "{{word}}" to department vocabulary... | drop |
| `hub_dictionary_toast_no_changes` | hub | No changes made | reuse |
| `hub_dictionary_toast_personal_already_exists` | hub | "{{word}}" already exists in your personal dictionary | reuse |
| `hub_dictionary_toast_remove_personal_failed` | hub | "{{word}}" could not be removed from personal vocabulary | reuse |
| `hub_dictionary_toast_share_to_team_failed_department_one` | hub | Couldn't share {{count}} word with department | drop |
| `hub_dictionary_toast_share_to_team_failed_department_other` | hub | Couldn't share {{count}} words with department | drop |
| `hub_dictionary_toast_share_to_team_failed_one` | hub | Couldn't share {{count}} word with team | drop |
| `hub_dictionary_toast_share_to_team_failed_other` | hub | Couldn't share {{count}} words with team | drop |
| `hub_dictionary_toast_shared_to_team_department_one` | hub | Shared {{count}} word with department | drop |
| `hub_dictionary_toast_shared_to_team_department_other` | hub | Shared {{count}} words with department | drop |
| `hub_dictionary_toast_shared_to_team_one` | hub | Shared {{count}} word with team | drop |
| `hub_dictionary_toast_shared_to_team_other` | hub | Shared {{count}} words with team | drop |
| `hub_dictionary_toast_shared_to_team_pending_one` | hub | {{count}} word is awaiting admin approval — it stays in your personal dictionary until then | drop |
| `hub_dictionary_toast_shared_to_team_pending_other` | hub | {{count}} words are awaiting admin approval — they stay in your personal dictionary until then | drop |
| `hub_dictionary_toast_sharing_to_team_department_one` | hub | Sharing {{count}} word with department… | drop |
| `hub_dictionary_toast_sharing_to_team_department_other` | hub | Sharing {{count}} words with department… | drop |
| `hub_dictionary_toast_sharing_to_team_one` | hub | Sharing {{count}} word with team… | drop |
| `hub_dictionary_toast_sharing_to_team_other` | hub | Sharing {{count}} words with team… | drop |
| `hub_dictionary_toast_team_already_exists` | hub | "{{word}}" already exists in your team dictionary | drop |
| `hub_dictionary_toast_team_already_exists_department` | hub | "{{word}}" already exists in your department dictionary | drop |
| `hub_dictionary_toast_update_error` | hub | An error occurred while updating the word. Please try again or contact support. | reuse |
| `hub_dictionary_toast_updated_replacement` | hub | Updated "{{oldWord}}" → "{{newReplacement}}" | reuse |
| `hub_dictionary_toast_updated_word` | hub | Updated "{{word}}" | reuse |
| `hub_dictionary_toast_word_empty` | hub | Word cannot be empty | reuse |
| `hub_dictionary_unstar_tooltip` | hub | Unstar | reuse |

#### Snippets (117)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `feature_notif_snippets_action_save` | ntf | Save | reuse |
| `feature_notif_snippets_reminder_action_save` | ntf | Save | reuse |
| `feature_notif_snippets_title` | ntf | Type that often? Save it as a snippet for later. | reuse |
| `hub_banner_snippets_cta_add_new_snippet` | hub | Add new snippet | reuse |
| `hub_banner_snippets_description` | hub | Save text you type often — an email, intro, or prompt — then say a word to drop it in instantly. | reuse |
| `hub_banner_snippets_example_intro_email_expansion` | hub | Hey, would love to find some time to chat later... | reuse |
| `hub_banner_snippets_example_intro_email_trigger` | hub | intro email | reuse |
| `hub_banner_snippets_example_personal_linkedin_expansion` | hub | https://www.linkedin.com/in/john-doe/ | reuse |
| `hub_banner_snippets_example_personal_linkedin_trigger` | hub | my LinkedIn | reuse |
| `hub_banner_snippets_example_personal_rewrite_expansion` | hub | Rewrite this to be more concise... | reuse |
| `hub_banner_snippets_example_personal_rewrite_trigger` | hub | rewrite prompt | reuse |
| `hub_banner_snippets_example_team_company_intro_expansion` | hub | Wispr Flow is a company that does ... | drop |
| `hub_banner_snippets_example_team_company_intro_trigger` | hub | company intro | drop |
| `hub_banner_snippets_example_team_support_expansion` | hub | Please message support@company.com for... | drop |
| `hub_banner_snippets_example_team_support_trigger` | hub | support message | drop |
| `hub_banner_snippets_team_join_others_one` | hub | Join {{count}} other at {{teamName}} to access your organization’s snippets. | drop |
| `hub_banner_snippets_team_join_others_other` | hub | Join {{count}} others at {{teamName}} to access your organization’s snippets. | drop |
| `hub_banner_snippets_team_upsell_description` | hub | `Save shortcuts to speak the things you type all the time—emails, links, addresses, bios—anything. <1>Just speak and Flow expands them instantly</1>, without retyping or hunting through old messages.` | drop |
| `hub_banner_snippets_team_upsell_title` | hub | `The stuff <1>your team</1> shouldn’t have to re-type.` | drop |
| `hub_banner_snippets_title_team` | hub | `The stuff <1>your team</1> shouldn’t have to re-type.` | drop |
| `hub_banner_snippets_title_you` | hub | `The stuff <1>you</1> shouldn’t have to re-type.` | reuse |
| `hub_bulk_import_snippets_duplicate_text` | hub | snippets | reuse |
| `hub_bulk_import_snippets_empty_error` | hub | No snippets found in file | reuse |
| `hub_bulk_import_snippets_item_noun` | hub | snippet | reuse |
| `hub_bulk_import_snippets_item_noun_plural` | hub | snippets | reuse |
| `hub_bulk_import_snippets_loading_text` | hub | Importing snippets... | reuse |
| `hub_bulk_import_snippets_preview_count_label` | hub | items displayed | reuse |
| `hub_bulk_import_snippets_preview_subtitle` | hub | Confirm snippets are ready for import, and we'll add them to your snippets. | reuse |
| `hub_bulk_import_snippets_title` | hub | Snippets | reuse |
| `hub_snippet_format_insert_link` | hub | Insert link (Cmd+K) | reuse |
| `hub_snippets_add_new_button` | hub | Add new | reuse |
| `hub_snippets_auto_learned_tooltip` | hub | Flow learned this word automatically ✨ | reuse |
| `hub_snippets_bulk_delete_confirm_body_one` | hub | The selected snippet will be deleted permanently. | reuse |
| `hub_snippets_bulk_delete_confirm_body_other` | hub | The selected snippets will be deleted permanently. | reuse |
| `hub_snippets_bulk_delete_confirm_title_one` | hub | Delete {{count}} snippet? | reuse |
| `hub_snippets_bulk_delete_confirm_title_other` | hub | Delete {{count}} snippets? | reuse |
| `hub_snippets_bulk_delete_one` | hub | Delete {{count}} | reuse |
| `hub_snippets_bulk_delete_other` | hub | Delete {{count}} | reuse |
| `hub_snippets_bulk_share_count_department_one` | hub | Share {{count}} with department | drop |
| `hub_snippets_bulk_share_count_department_other` | hub | Share {{count}} with department | drop |
| `hub_snippets_bulk_share_count_one` | hub | Share {{count}} with team | reuse |
| `hub_snippets_bulk_share_count_other` | hub | Share {{count}} with team | reuse |
| `hub_snippets_bulk_toolbar_aria` | hub | Bulk actions | reuse |
| `hub_snippets_dialog_cancel` | hub | Cancel | reuse |
| `hub_snippets_dialog_confirm_delete` | hub | Yes, delete it | reuse |
| `hub_snippets_dialog_delete_org_title` | hub | Delete from organization snippets? | drop |
| `hub_snippets_dialog_delete_personal_title` | hub | Delete from personal snippets? | reuse |
| `hub_snippets_dialog_delete_subtitle` | hub | '{{phrase}}' will be deleted permanently. | reuse |
| `hub_snippets_dialog_delete_team_title` | hub | Delete from team snippets? | drop |
| `hub_snippets_dialog_delete_team_title_department` | hub | Delete from department snippets? | drop |
| `hub_snippets_dialog_edit_title` | hub | Edit snippet | reuse |
| `hub_snippets_dialog_save_changes` | hub | Save changes | reuse |
| `hub_snippets_edit_expansion_placeholder` | hub | Expansion | reuse |
| `hub_snippets_edit_snippet_placeholder` | hub | Snippet | reuse |
| `hub_snippets_edit_tooltip` | hub | Edit | reuse |
| `hub_snippets_expansion_counter` | hub | {{length}}/{{max}} | reuse |
| `hub_snippets_import_button` | hub | Import | reuse |
| `hub_snippets_last_synced_tooltip` | hub | Snippets last synced {{relativeTime}} | drop |
| `hub_snippets_modal_add_cta` | hub | Add snippet | reuse |
| `hub_snippets_modal_add_title` | hub | Add snippet | reuse |
| `hub_snippets_modal_share_with_team_disabled_tooltip` | hub | To share snippets with your team, go to Settings and set up a team. | drop |
| `hub_snippets_modal_share_with_team_tooltip` | hub | Adds this Snippet to your team's shared Snippets. | drop |
| `hub_snippets_modal_share_with_team_tooltip_department` | hub | Adds this Snippet to your department's shared Snippets. Other departments in your organization won't see it. | drop |
| `hub_snippets_no_results_body` | hub | No snippets were found | reuse |
| `hub_snippets_no_results_title` | hub | No results found | reuse |
| `hub_snippets_search_placeholder` | hub | Search your snippets | reuse |
| `hub_snippets_search_tooltip` | hub | Search snippets | reuse |
| `hub_snippets_sort_alphabetical` | hub | Alphabetical (A-Z) | reuse |
| `hub_snippets_sort_menu_title` | hub | Sort by | reuse |
| `hub_snippets_sort_newest_first` | hub | Newest first | reuse |
| `hub_snippets_sort_oldest_first` | hub | Oldest first | reuse |
| `hub_snippets_sort_tooltip` | hub | Sort by | reuse |
| `hub_snippets_sync_tooltip` | hub | Sync Snippets | drop |
| `hub_snippets_title` | hub | Snippets | reuse |
| `hub_snippets_toast_add_error` | hub | An error occurred while adding the snippet. Please try again or contact support. | reuse |
| `hub_snippets_toast_added` | hub | "{{word}}" added successfully | reuse |
| `hub_snippets_toast_added_pending` | hub | "{{word}}" is awaiting admin approval before your team can use it | drop |
| `hub_snippets_toast_added_pending_department` | hub | "{{word}}" is awaiting admin approval before your department can use it | drop |
| `hub_snippets_toast_added_similar` | hub | "{{word}}" added successfully, but is similar to the existing snippet "{{similar}}", please use distinct snippets for the best experience. | reuse |
| `hub_snippets_toast_bulk_delete_failed_one` | hub | Failed to delete {{count}} snippet | reuse |
| `hub_snippets_toast_bulk_delete_failed_other` | hub | Failed to delete {{count}} snippets | reuse |
| `hub_snippets_toast_bulk_deleted_one` | hub | Deleted {{count}} snippet | reuse |
| `hub_snippets_toast_bulk_deleted_other` | hub | Deleted {{count}} snippets | reuse |
| `hub_snippets_toast_delete_failed` | hub | "{{word}}" could not be deleted | reuse |
| `hub_snippets_toast_deleted` | hub | "{{word}}" deleted | reuse |
| `hub_snippets_toast_expansion_too_long` | hub | This expansion is too long. Please shorten it and try again. | reuse |
| `hub_snippets_toast_missing_snippet_or_expansion` | hub | Please enter a snippet and its expansion | reuse |
| `hub_snippets_toast_move_to_team_failed` | hub | "{{word}}" could not be moved to teams snippets, please try again. | drop |
| `hub_snippets_toast_move_to_team_failed_department` | hub | "{{word}}" could not be moved to department snippets, please try again. | drop |
| `hub_snippets_toast_move_to_team_pending` | hub | "{{word}}" is awaiting admin approval — it stays in your personal snippets until then | drop |
| `hub_snippets_toast_moved_to_team` | hub | "{{word}}" moved to teams snippets | drop |
| `hub_snippets_toast_moved_to_team_department` | hub | "{{word}}" moved to department snippets | drop |
| `hub_snippets_toast_moving_to_team` | hub | Moving "{{word}}" to teams snippets... | drop |
| `hub_snippets_toast_moving_to_team_department` | hub | Moving "{{word}}" to department snippets... | drop |
| `hub_snippets_toast_no_changes` | hub | No changes made | reuse |
| `hub_snippets_toast_personal_already_exists` | hub | "{{word}}" already exists in your personal dictionary | reuse |
| `hub_snippets_toast_remove_personal_failed` | hub | "{{word}}" could not be removed from personal snippets | reuse |
| `hub_snippets_toast_share_to_team_failed_department_one` | hub | Couldn't share {{count}} snippet with department | drop |
| `hub_snippets_toast_share_to_team_failed_department_other` | hub | Couldn't share {{count}} snippets with department | drop |
| `hub_snippets_toast_share_to_team_failed_one` | hub | Couldn't share {{count}} snippet with team | drop |
| `hub_snippets_toast_share_to_team_failed_other` | hub | Couldn't share {{count}} snippets with team | drop |
| `hub_snippets_toast_shared_to_team_department_one` | hub | Shared {{count}} snippet with department | drop |
| `hub_snippets_toast_shared_to_team_department_other` | hub | Shared {{count}} snippets with department | drop |
| `hub_snippets_toast_shared_to_team_one` | hub | Shared {{count}} snippet with team | drop |
| `hub_snippets_toast_shared_to_team_other` | hub | Shared {{count}} snippets with team | drop |
| `hub_snippets_toast_shared_to_team_pending_one` | hub | {{count}} snippet is awaiting admin approval — it stays in your personal snippets until then | drop |
| `hub_snippets_toast_shared_to_team_pending_other` | hub | {{count}} snippets are awaiting admin approval — they stay in your personal snippets until then | drop |
| `hub_snippets_toast_sharing_to_team_department_one` | hub | Sharing {{count}} snippet with department… | drop |
| `hub_snippets_toast_sharing_to_team_department_other` | hub | Sharing {{count}} snippets with department… | drop |
| `hub_snippets_toast_sharing_to_team_one` | hub | Sharing {{count}} snippet with team… | drop |
| `hub_snippets_toast_sharing_to_team_other` | hub | Sharing {{count}} snippets with team… | drop |
| `hub_snippets_toast_team_already_exists` | hub | "{{word}}" already exists in your team snippets | drop |
| `hub_snippets_toast_team_already_exists_department` | hub | "{{word}}" already exists in your department snippets | drop |
| `hub_snippets_toast_update_error` | hub | An error occurred while updating the snippet. Please try again or contact support. | reuse |
| `hub_snippets_toast_updated` | hub | Updated snippet {{word}} | reuse |
| `hub_snippets_toast_updated_similar` | hub | "{{word}}" updated successfully, but is similar to the existing snippet "{{similar}}", please use distinct snippets for the best experience. | reuse |
| `hub_snippets_toast_word_empty` | hub | Word cannot be empty | reuse |

#### Bulk import (shared by Dictionary and Snippets) (1)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_bulk_import_summary_pending` | hub | {{count}} {{itemNoun}} sent for admin approval | drop |

#### Style, My Voice, cleanup level, personalization (147)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `feature_notif_styles_action_customize` | ntf | Pick My Style | reuse |
| `feature_notif_styles_reminder_action_customize` | ntf | Customize how Flow writes | reuse |
| `feature_notif_styles_reminder_title` | ntf | Sound too formal? | reuse |
| `feature_notif_styles_title` | ntf | Flow can adjust its style in different apps. | reuse |
| `formality_mismatch_detected_action_disable` | ntf | Disable | reuse |
| `formality_mismatch_detected_title` | ntf | Style mismatch detected | reuse |
| `personalization_email_casual_content` | ntf | `Hi Alex, it was great talking with you today. Looking forward to our next chat.<br /><br />Best,<br />Mary` | reuse |
| `personalization_email_casual_subtitle` | ntf | Caps + Less punctuation | reuse |
| `personalization_email_casual_title` | ntf | Casual | reuse |
| `personalization_email_excited_content` | ntf | `Hi Alex,<br /><br />It was great talking with you today. Looking forward to our next chat!<br /><br />Best,<br />Mary` | reuse |
| `personalization_email_excited_subtitle` | ntf | More exclamations | reuse |
| `personalization_email_excited_title` | ntf | Excited! | reuse |
| `personalization_email_formal_content` | ntf | `Hi Alex,<br /><br />It was great talking with you today. Looking forward to our next chat.<br /><br />Best,<br />Mary` | reuse |
| `personalization_email_formal_subtitle` | ntf | Caps + Punctuation | reuse |
| `personalization_email_formal_title` | ntf | Formal. | reuse |
| `personalization_modal_back` | ntf | Back | reuse |
| `personalization_modal_done_tooltip` | ntf | Click on the Style tab to make changes to your personalization settings | reuse |
| `personalization_modal_final_body` | ntf | Try Flow in your apps to see the difference. You can update your styles anytime in the Style tab. | reuse |
| `personalization_modal_final_cta` | ntf | Done | reuse |
| `personalization_modal_final_disclaimer` | ntf | Style formatting only applies in English. More languages coming soon. | reuse |
| `personalization_modal_final_title` | ntf | You're all set! | reuse |
| `personalization_modal_intro_cta` | ntf | Start personalization | reuse |
| `personalization_modal_intro_subtitle` | ntf | Set how Flow writes when you dictate in different apps | reuse |
| `personalization_modal_intro_title` | ntf | Let's personalize Flow to you | reuse |
| `personalization_modal_next` | ntf | Next | reuse |
| `personalization_modal_stage_email_title` | ntf | `How do you write your <1>emails?</1>` | reuse |
| `personalization_modal_stage_other_title` | ntf | `How do you write in <1>other apps?</1>` | reuse |
| `personalization_modal_stage_personal_title` | ntf | `How do you write your <1>personal messages?</1>` | reuse |
| `personalization_modal_stage_work_title` | ntf | `How do you write your <1>work messages?</1>` | reuse |
| `personalization_other_casual_content` | ntf | `So far I am enjoying the new workout routine.<br /><br />I am excited for tomorrow’s workout especially after a full night of rest.` | reuse |
| `personalization_other_casual_subtitle` | ntf | Caps + Less punctuation | reuse |
| `personalization_other_casual_title` | ntf | Casual | reuse |
| `personalization_other_excited_content` | ntf | `So far, I am enjoying the new workout routine.<br /><br />I am excited for tomorrow’s workout, especially after a full night of rest!` | reuse |
| `personalization_other_excited_subtitle` | ntf | More exclamations | reuse |
| `personalization_other_excited_title` | ntf | Excited! | reuse |
| `personalization_other_formal_content` | ntf | `So far, I am enjoying the new workout routine.<br /><br />I am excited for tomorrow’s workout, especially after a full night of rest.` | reuse |
| `personalization_other_formal_subtitle` | ntf | Caps + Punctuation | reuse |
| `personalization_other_formal_title` | ntf | Formal. | reuse |
| `personalization_personal_messages_casual_content` | ntf | Hey are you free for lunch tomorrow? Let’s do 12 if that works for you | reuse |
| `personalization_personal_messages_casual_subtitle` | ntf | Caps + Less punctuation | reuse |
| `personalization_personal_messages_casual_title` | ntf | Casual | reuse |
| `personalization_personal_messages_formal_content` | ntf | Hey, are you free for lunch tomorrow? Let’s do 12 if that works for you. | reuse |
| `personalization_personal_messages_formal_subtitle` | ntf | Caps + Punctuation | reuse |
| `personalization_personal_messages_formal_title` | ntf | Formal. | reuse |
| `personalization_personal_messages_very_casual_content` | ntf | hey are you free for lunch tomorrow? let’s do 12 if that works for you | reuse |
| `personalization_personal_messages_very_casual_subtitle` | ntf | No Caps + Less punctuation | reuse |
| `personalization_personal_messages_very_casual_title` | ntf | very casual | reuse |
| `personalization_work_messages_casual_content` | ntf | Hey, if you’re free let’s chat about the great results | reuse |
| `personalization_work_messages_casual_subtitle` | ntf | Caps + Less punctuation | reuse |
| `personalization_work_messages_casual_title` | ntf | Casual | reuse |
| `personalization_work_messages_excited_content` | ntf | Hey, if you’re free, let’s chat about the great results! | reuse |
| `personalization_work_messages_excited_subtitle` | ntf | More exclamations | reuse |
| `personalization_work_messages_excited_title` | ntf | Excited! | reuse |
| `personalization_work_messages_formal_content` | ntf | Hey, if you’re free, let’s chat about the great results. | reuse |
| `personalization_work_messages_formal_subtitle` | ntf | Caps + Punctuation | reuse |
| `personalization_work_messages_formal_title` | ntf | Formal. | reuse |
| `hub_banner_my_voice_description` | hub | Help Flow sound more like you so you can feel confident in using your voice anywhere. | reuse |
| `hub_banner_my_voice_title` | hub | `Customize <1>your writing styles</1>` | reuse |
| `hub_banner_personalization_cta` | hub | Start now | reuse |
| `hub_banner_personalization_description` | hub | Set up different writing styles for different apps. | reuse |
| `hub_banner_personalization_title` | hub | `Make Flow sound like <1>you</1>` | reuse |
| `hub_banner_styles_disclaimer` | hub | Style formatting only applies in English. More languages coming soon. | reuse |
| `hub_banner_styles_title_email` | hub | This style applies in all major email apps | reuse |
| `hub_banner_styles_title_other` | hub | This style applies in all other apps | reuse |
| `hub_banner_styles_title_personal_messages` | hub | This style applies in personal messengers | reuse |
| `hub_banner_styles_title_work_messages` | hub | This style applies in workplace messengers | reuse |
| `hub_cleanup_level_description` | hub | Choose how much Flow edits each dictation for clarity and correctness. | reuse |
| `hub_cleanup_level_high_description` | hub | Rewrites for brevity and polish | reuse |
| `hub_cleanup_level_high_example` | hub | Hey Joey, are we still on for coffee? Let’s leave early to beat traffic. What do you think? | reuse |
| `hub_cleanup_level_high_label` | hub | High | reuse |
| `hub_cleanup_level_light_description` | hub | Cleans up filler words and grammar | reuse |
| `hub_cleanup_level_light_example` | hub | Hey Joey, are we still on for coffee? I think we should leave earlier to make it there in time. There might be traffic. What are you thinking? | reuse |
| `hub_cleanup_level_light_label` | hub | Light | reuse |
| `hub_cleanup_level_medium_description` | hub | Edits for clarity and conciseness | reuse |
| `hub_cleanup_level_medium_example` | hub | Hey Joey, are we still on for coffee? We should leave earlier; there might be traffic. What do you think? | reuse |
| `hub_cleanup_level_medium_label` | hub | Medium | reuse |
| `hub_cleanup_level_none_description` | hub | Transcribes exactly what you said, including mistakes | reuse |
| `hub_cleanup_level_none_example` | hub | hey joey, we still on for coffee or? I think we maybe should leave earlier to make it there in time there might um be traffic. What are you thinking? | reuse |
| `hub_cleanup_level_none_label` | hub | None | reuse |
| `hub_myvoice_all_other_apps` | hub | All other apps | reuse |
| `hub_myvoice_apply_in_apps` | hub | Automatically apply in these apps or websites | reuse |
| `hub_myvoice_apps_using_style_aria` | hub | Apps using this style | reuse |
| `hub_myvoice_content_edit_level_aria` | hub | Level of Content Edit | reuse |
| `hub_myvoice_custom_prompts_coming_soon` | hub | \* Custom style prompts coming soon | reuse |
| `hub_myvoice_delete_style` | hub | Delete style | reuse |
| `hub_myvoice_edit_cleanup_level` | hub | Edit and cleanup level | reuse |
| `hub_myvoice_preferred_style_aria` | hub | Preferred style | reuse |
| `hub_myvoice_select_style` | hub | Select style | reuse |
| `hub_myvoice_style_instructions` | hub | Style Instructions | reuse |
| `hub_myvoice_style_name` | hub | Style name | reuse |
| `hub_myvoice_subtitle` | hub | How you sound in different contexts: | reuse |
| `hub_myvoice_title` | hub | My Voice | reuse |
| `hub_myvoice_untitled_style` | hub | Untitled style | reuse |
| `hub_personalization_done_button` | hub | Done | reuse |
| `hub_personalization_done_tooltip` | hub | Click on the Style tab to make changes to your personalization settings | reuse |
| `hub_personalization_final_body` | hub | Try Flow in your apps to see the difference. You can update your styles anytime in the Style tab. | reuse |
| `hub_personalization_final_disclaimer` | hub | Style formatting only applies in English. More languages coming soon. | reuse |
| `hub_personalization_final_title` | hub | You're all set! | reuse |
| `hub_personalization_intro_subtitle` | hub | Set how Flow writes when you dictate in different apps | reuse |
| `hub_personalization_intro_title` | hub | Let's personalize Flow to you | reuse |
| `hub_personalization_next_button` | hub | Next | reuse |
| `hub_personalization_stage_emails_title` | hub | `How do you write your <1>emails?</1>` | reuse |
| `hub_personalization_stage_other_title` | hub | `How do you write in <1>other apps?</1>` | reuse |
| `hub_personalization_stage_personal_messages_title` | hub | `How do you write your <1>personal messages?</1>` | reuse |
| `hub_personalization_stage_work_messages_title` | hub | `How do you write your <1>work messages?</1>` | reuse |
| `hub_personalization_start_button` | hub | Start personalization | reuse |
| `hub_personalization_tab_all` | hub | All | reuse |
| `hub_personalization_tab_personal` | hub | Personal | reuse |
| `hub_personalization_tab_shared_with_team` | hub | Shared with team | drop |
| `hub_personalization_tab_shared_with_team_department` | hub | Shared with department | drop |
| `hub_style_auto_cleanup_banner_body_1` | hub | Choose the level of cleanup that's automatically applied every time, across all apps. | reuse |
| `hub_style_auto_cleanup_banner_body_2` | hub | Note your original dictation is never lost. Just go to the three dots next to a recent dictation in the Home tab, then click “Undo AI edit.” | reuse |
| `hub_style_auto_cleanup_banner_title` | hub | Auto Cleanup applies to all your dictations | reuse |
| `hub_style_banner_email_title` | hub | This style applies in all major email apps | reuse |
| `hub_style_banner_other_title` | hub | This style applies in all other apps | reuse |
| `hub_style_banner_personal_messages_title` | hub | This style applies in personal messengers | reuse |
| `hub_style_banner_work_messages_title` | hub | This style applies in workplace messengers | reuse |
| `hub_style_card_casual_subtitle` | hub | Caps + Less punctuation | reuse |
| `hub_style_card_casual_title` | hub | Casual | reuse |
| `hub_style_card_email_casual_content_rich` | hub | `<h>H</h>i Alex<c>,</c> it was great talking with you today. <h>L</h>ooking forward to our next chat<c>.</c><br /><br />Best,<br />Mary` | reuse |
| `hub_style_card_email_excited_content_rich` | hub | `<h>H</h>i Alex<c>,</c><br /><br /><h>I</h>t was great talking with you today. <h>L</h>ooking forward to our next chat<clg>!</clg><br /><br />Best,<br />Mary` | reuse |
| `hub_style_card_email_formal_content_rich` | hub | `<h>H</h>i Alex<c>,</c><br /><br /><h>I</h>t was great talking with you today. <h>L</h>ooking forward to our next chat<c>.</c><br /><br />Best,<br />Mary` | reuse |
| `hub_style_card_email_veryCasual_content_rich` | hub | `<h>h</h>i alex it was great talking with you today. <h>l</h>ooking forward to our next chat<br /><br />best,<br />mary` | reuse |
| `hub_style_card_excited_subtitle` | hub | More exclamations | reuse |
| `hub_style_card_excited_title` | hub | Excited! | reuse |
| `hub_style_card_formal_subtitle` | hub | Caps + Punctuation | reuse |
| `hub_style_card_formal_title` | hub | Formal. | reuse |
| `hub_style_card_other_casual_content_rich` | hub | `<h>S</h>o far <h>I</h> am enjoying the new workout routine.<br /><br /><h>I</h> am excited for tomorrow’s workout especially after a full night of rest.` | reuse |
| `hub_style_card_other_excited_content_rich` | hub | `<h>S</h>o far<c>,</c> <h>I</h> am enjoying the new workout routine.<br /><br /><h>I</h> am excited for tomorrow’s workout<c>,</c> especially after a full night of rest<clg>!</clg>` | reuse |
| `hub_style_card_other_formal_content_rich` | hub | `<h>S</h>o far<c>,</c> <h>I</h> am enjoying the new workout routine.<br /><br /><h>I</h> am excited for tomorrow’s workout<c>,</c> especially after a full night of rest.` | reuse |
| `hub_style_card_other_veryCasual_content_rich` | hub | `<h>s</h>o far <h>i</h> am enjoying the new workout routine.<br /><br /><h>i</h> am excited for tomorrow’s workout especially after a full night of rest` | reuse |
| `hub_style_card_personal_casual_content_rich` | hub | `<h>H</h>ey are you free for lunch tomorrow? <h>L</h>et’s do 12 if that works for you` | reuse |
| `hub_style_card_personal_excited_content_rich` | hub | `<h>H</h>ey<clg>!</clg> Are you free for lunch tomorrow? <h>L</h>et’s do 12 if that works for you<clg>!</clg>` | reuse |
| `hub_style_card_personal_formal_content_rich` | hub | `<h>H</h>ey<c>,</c> are you free for lunch tomorrow? <h>L</h>et’s do 12 if that works for you<c>.</c>` | reuse |
| `hub_style_card_personal_veryCasual_content_rich` | hub | `<h>h</h>ey are you free for lunch tomorrow? <h>l</h>et’s do 12 if that works for you` | reuse |
| `hub_style_card_very_casual_subtitle` | hub | No Caps + Less punctuation | reuse |
| `hub_style_card_very_casual_title` | hub | very casual | reuse |
| `hub_style_card_work_casual_content_rich` | hub | `<h>H</h>ey<c>,</c> if you’re free let’s chat about the great results` | reuse |
| `hub_style_card_work_excited_content_rich` | hub | `<h>H</h>ey<c>,</c> if you’re free<c>,</c> let’s chat about the great results<clg>!</clg>` | reuse |
| `hub_style_card_work_formal_content_rich` | hub | `<h>H</h>ey<c>,</c> if you’re free<c>,</c> let’s chat about the great results<c>.</c>` | reuse |
| `hub_style_card_work_veryCasual_content_rich` | hub | `<h>h</h>ey if you’re free let’s chat about the great results` | reuse |
| `hub_style_tab_auto_cleanup` | hub | Auto cleanup | reuse |
| `hub_style_tab_email` | hub | Email | reuse |
| `hub_style_tab_other` | hub | Other | reuse |
| `hub_style_tab_personal_messages` | hub | Personal messages | reuse |
| `hub_style_tab_work_messages` | hub | Work messages | reuse |
| `hub_style_title` | hub | Style | reuse |

#### Notes (26)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_notes_beta_badge` | hub | Beta | reuse |
| `hub_notes_delete_aria` | hub | Delete note | reuse |
| `hub_notes_delete_dialog_subtitle` | hub | Once deleted it cannot be recovered | reuse |
| `hub_notes_delete_dialog_title` | hub | Are you sure you want to delete this note? | reuse |
| `hub_notes_empty_state` | hub | No notes found | reuse |
| `hub_notes_flow_bar_toggle_label` | hub | Add to Flow Bar | reuse |
| `hub_notes_flow_bar_toggle_tooltip` | hub | Show a Scratchpad button on the flow bar so you can open notes from anywhere. | reuse |
| `hub_notes_last_refreshed_tooltip` | hub | Last refreshed {{relativeTime}} | reuse |
| `hub_notes_new_note_title` | hub | New note | reuse |
| `hub_notes_pin_aria` | hub | Pin note | reuse |
| `hub_notes_pinned_aria` | hub | Pinned | reuse |
| `hub_notes_recents_label` | hub | Recents | reuse |
| `hub_notes_search_placeholder` | hub | Search your notes | reuse |
| `hub_notes_shortcut_modal_disable_button` | hub | Disable shortcut | reuse |
| `hub_notes_shortcut_modal_subtitle` | hub | Press to open the scratchpad window | reuse |
| `hub_notes_shortcut_modal_title` | hub | Open Scratchpad | reuse |
| `hub_notes_shortcut_pill_aria_change` | hub | Change Open Scratchpad hotkey | reuse |
| `hub_notes_shortcut_pill_aria_set` | hub | Set Open Scratchpad hotkey | reuse |
| `hub_notes_shortcut_pill_empty` | hub | Click to enable shortcut | reuse |
| `hub_notes_shortcut_pill_label` | hub | to Open | reuse |
| `hub_notes_sync_disabled_tooltip` | hub | Your notes aren't syncing because Private Cloud Sync is off | drop |
| `hub_notes_title` | hub | Scratchpad | reuse |
| `hub_notes_toast_delete_failed` | hub | Failed to delete note | reuse |
| `hub_notes_toast_deleted_success` | hub | Deleted note | reuse |
| `hub_notes_toast_pin_update_failed` | hub | Failed to update pin | reuse |
| `hub_notes_unpin_aria` | hub | Unpin note | reuse |

#### Scratchpad (70)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_banner_scratchpad_card_body` | hub | The core principle is about agency and stakes. A progress bar says “you have a shrinking window to do something” — it puts the user in control of a timed decision. A fade says “just so you know” — it’s acknowledgment, not a call to action. | reuse |
| `hub_scratchpad_clear_search_aria` | hub | Clear search | reuse |
| `hub_scratchpad_close` | hub | Close | reuse |
| `hub_scratchpad_close_tab_aria` | hub | Close tab {{title}} | reuse |
| `hub_scratchpad_collapse_notes` | hub | Collapse Notes | reuse |
| `hub_scratchpad_compact_window` | hub | Compact window | reuse |
| `hub_scratchpad_copied_to_clipboard` | hub | Copied to clipboard | reuse |
| `hub_scratchpad_copy` | hub | Copy | reuse |
| `hub_scratchpad_delete_note` | hub | Delete note | reuse |
| `hub_scratchpad_dictate_aria` | hub | {{pttKey}} to dictate | reuse |
| `hub_scratchpad_drop_images` | hub | Drop images to attach | reuse |
| `hub_scratchpad_expand_window` | hub | Expand window | reuse |
| `hub_scratchpad_failed_delete_note` | hub | Failed to delete note | reuse |
| `hub_scratchpad_format_blockquote` | hub | Blockquote | reuse |
| `hub_scratchpad_format_bold` | hub | Bold (Cmd+B) | reuse |
| `hub_scratchpad_format_bullet_list` | hub | Bullet list | reuse |
| `hub_scratchpad_format_checklist` | hub | Checklist | reuse |
| `hub_scratchpad_format_inline_code` | hub | Inline code | reuse |
| `hub_scratchpad_format_insert_link` | hub | Insert link | reuse |
| `hub_scratchpad_format_insert_table` | hub | Insert table | reuse |
| `hub_scratchpad_format_italic` | hub | Italic (Cmd+I) | reuse |
| `hub_scratchpad_format_numbered_list` | hub | Numbered list | reuse |
| `hub_scratchpad_format_toggle` | hub | Toggle | reuse |
| `hub_scratchpad_format_underline` | hub | Underline (Cmd+U) | reuse |
| `hub_scratchpad_formatting` | hub | Formatting | reuse |
| `hub_scratchpad_link_apply` | hub | Apply | reuse |
| `hub_scratchpad_link_cancel` | hub | Cancel | reuse |
| `hub_scratchpad_link_remove` | hub | Remove | reuse |
| `hub_scratchpad_link_text_label` | hub | Text | reuse |
| `hub_scratchpad_link_text_placeholder` | hub | Link text | reuse |
| `hub_scratchpad_link_url_label` | hub | URL | reuse |
| `hub_scratchpad_link_url_placeholder` | hub | https://example.com | reuse |
| `hub_scratchpad_load_more` | hub | Load more | reuse |
| `hub_scratchpad_loading` | hub | Loading… | reuse |
| `hub_scratchpad_message_preview` | hub | Message Preview | reuse |
| `hub_scratchpad_new_note` | hub | New note | reuse |
| `hub_scratchpad_new_tab` | hub | New tab (⌘T) | reuse |
| `hub_scratchpad_no_matching_notes` | hub | No matching notes | reuse |
| `hub_scratchpad_no_notes_yet` | hub | No notes yet | reuse |
| `hub_scratchpad_note_deleted` | hub | Note deleted | reuse |
| `hub_scratchpad_recent_notes_aria` | hub | Recent notes | reuse |
| `hub_scratchpad_search_notes` | hub | Search notes | reuse |
| `hub_scratchpad_search_notes_aria` | hub | Search notes | reuse |
| `hub_scratchpad_search_placeholder` | hub | Search notes… | reuse |
| `hub_scratchpad_send` | hub | Send | reuse |
| `hub_scratchpad_send_in_app` | hub | Send in {{appName}} | reuse |
| `hub_scratchpad_submit_transform_aria` | hub | Submit | reuse |
| `hub_scratchpad_table_delete_column` | hub | Delete column | reuse |
| `hub_scratchpad_table_delete_row` | hub | Delete row | reuse |
| `hub_scratchpad_table_delete_table` | hub | Delete table | reuse |
| `hub_scratchpad_table_insert_column_left` | hub | Insert column left | reuse |
| `hub_scratchpad_table_insert_column_right` | hub | Insert column right | reuse |
| `hub_scratchpad_table_insert_row_above` | hub | Insert row above | reuse |
| `hub_scratchpad_table_insert_row_below` | hub | Insert row below | reuse |
| `hub_scratchpad_tabs_aria` | hub | Scratchpad tabs | reuse |
| `hub_scratchpad_to_dictate` | hub | ` to dictate` | reuse |
| `hub_scratchpad_transform_failed` | hub | Transform failed. Please try again. | reuse |
| `hub_scratchpad_transform_hint` | hub | `Press Enter or ` | reuse |
| `hub_scratchpad_transform_placeholder` | hub | Follow up or ask a question | reuse |
| `hub_scratchpad_transform_regenerate` | hub | Get new suggestions | reuse |
| `hub_scratchpad_transforms` | hub | Transforms | reuse |
| `hub_scratchpad_version_created` | hub | Created | reuse |
| `hub_scratchpad_version_custom_transform` | hub | Custom transform | reuse |
| `hub_scratchpad_version_dictated` | hub | Dictated | reuse |
| `hub_scratchpad_version_empty` | hub | No versions yet | reuse |
| `hub_scratchpad_version_history` | hub | Version history | reuse |
| `hub_scratchpad_version_history_aria` | hub | Version history | reuse |
| `hub_scratchpad_version_loading` | hub | Loading versions... | reuse |
| `hub_scratchpad_version_transform` | hub | Transform | reuse |
| `hub_scratchpad_version_typed` | hub | Typed edits | reuse |

#### Transforms (Polish), diff view, Command Mode, Instruct Mode (202)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_polish_autosave_failed` | set | Failed to save | reuse |
| `settings_polish_autosave_hours_ago_one` | set | {{count}}h ago | reuse |
| `settings_polish_autosave_hours_ago_other` | set | {{count}}h ago | reuse |
| `settings_polish_autosave_just_now` | set | just now | reuse |
| `settings_polish_autosave_last_saved` | set | Last saved {{timeAgo}} | reuse |
| `settings_polish_autosave_minutes_ago_one` | set | {{count}}m ago | reuse |
| `settings_polish_autosave_minutes_ago_other` | set | {{count}}m ago | reuse |
| `settings_polish_autosave_on` | set | Autosave On | reuse |
| `settings_polish_autosave_saved` | set | Saved | reuse |
| `settings_polish_autosave_saving` | set | Saving… | reuse |
| `settings_polish_autosave_seconds_ago_one` | set | {{count}}s ago | reuse |
| `settings_polish_autosave_seconds_ago_other` | set | {{count}}s ago | reuse |
| `settings_polish_custom_prompt_heading` | set | Customize your Polish prompt | reuse |
| `settings_polish_custom_prompt_placeholder` | set | Add in any polish prompt instructions | reuse |
| `settings_polish_name_input_label` | set | Name your Transform shortcut | reuse |
| `settings_polish_toast_max_samples` | set | Maximum of {{max}} writing samples allowed | reuse |
| `settings_polish_toast_sample_added` | set | Sample added! | reuse |
| `settings_polish_toast_sample_deleted` | set | Sample deleted | reuse |
| `settings_polish_toast_sample_updated` | set | Sample updated! | reuse |
| `settings_polish_toast_sync_failed` | set | Failed to sync, try again | reuse |
| `settings_polish_writing_examples_add` | set | Add an example | reuse |
| `settings_polish_writing_examples_description` | set | Add examples of your writing to help Flow learn your unique style. The more samples you provide, the better Flow can match your voice. | reuse |
| `settings_polish_writing_examples_heading` | set | Add writing examples | reuse |
| `settings_polish_writing_examples_upload` | set | Upload Example | reuse |
| `settings_polish_writing_sample_label` | set | Sample {{index}} | reuse |
| `settings_polish_writing_samples_count_one` | set | {{count}} writing sample | reuse |
| `settings_polish_writing_samples_count_other` | set | {{count}} writing samples | reuse |
| `command_mode_disabled_action_open_settings` | ntf | Go to settings | reuse |
| `command_mode_disabled_body` | ntf | Please turn it on to use it | reuse |
| `command_mode_disabled_title` | ntf | Command mode is toggled off | reuse |
| `command_mode_servers_are_busy_body` | ntf | Servers experiencing high demand. | rewrite |
| `command_mode_servers_are_busy_title` | ntf | Command Mode Servers Are Busy | rewrite |
| `first_time_using_command_mode_action_disable` | ntf | Disable | reuse |
| `first_time_using_command_mode_title` | ntf | Using Command Mode (beta) | reuse |
| `first_transform_completed_outside_flow_action_customize` | ntf | Customize transforms | reuse |
| `first_transform_completed_outside_flow_action_customize_transforms` | ntf | Customize transforms | reuse |
| `first_transform_completed_outside_flow_body` | ntf | Customize and create your own transforms in the Flow app | reuse |
| `first_transform_completed_outside_flow_title` | ntf | Congrats, you did your first transform! | reuse |
| `polish_activation_nudge_title` | ntf | Want to Transform this? Highlight and press {{shortcut}} | reuse |
| `polish_auto_edit_ready_action_reveal` | ntf | Reveal edit | reuse |
| `polish_auto_edit_ready_title` | ntf | We polished your dictation | reuse |
| `polish_cancelled_title` | ntf | {{name}} cancelled | reuse |
| `polish_disabled_during_dictation_title` | ntf | {{name}} doesn't work while dictating | reuse |
| `polish_empty_response_body` | ntf | Something went wrong. Please try again. | reuse |
| `polish_empty_response_title` | ntf | Transform returned no text | reuse |
| `polish_max_words_body` | ntf | Try again with under 1000 words | reuse |
| `polish_max_words_title` | ntf | Oops, too long to polish | reuse |
| `polish_running_warning_title` | ntf | Can't dictate while {{name}} is running | reuse |
| `polish_text_failed_body` | ntf | Servers experiencing high demand. | rewrite |
| `polish_text_failed_title` | ntf | {{name}} mode servers are busy | rewrite |
| `polish_text_no_changes_title` | ntf | Your text looks good! | reuse |
| `polish_text_no_selection_body` | ntf | Highlight any text, then press {{shortcut}} | reuse |
| `polish_text_no_selection_first_time_body` | ntf | First, highlight the text you want to transform, then press {{shortcut}} | reuse |
| `polish_text_no_selection_first_time_title` | ntf | Hey, select text first! | reuse |
| `polish_text_no_selection_title` | ntf | Select text to apply a transform | reuse |
| `polish_text_not_editable_title` | ntf | Flow can't paste right now. Text saved to clipboard | reuse |
| `polish_textbox_detection_failed_body` | ntf | Please click into your text box and try again. | reuse |
| `polish_textbox_detection_failed_title` | ntf | Couldn't detect text in your text box | reuse |
| `polish_timeout_body` | ntf | The request took too long. Please try again. | reuse |
| `polish_timeout_title` | ntf | Transform timed out | reuse |
| `use_hey_flow_for_command_mode_title` | ntf | No need to say “Hey Flow” anymore with command mode! | reuse |
| `using_command_mode_title` | ntf | Using Command Mode | reuse |
| `hub_banner_polish_cta_how_it_works` | hub | How it works | reuse |
| `hub_banner_polish_cta_try` | hub | Try it out | reuse |
| `hub_banner_polish_description` | hub | Apply a Transform to rewrite, clean up, or restructure text after you dictate. | reuse |
| `hub_banner_polish_title` | hub | `<1>Transform </1> works anywhere you write` | reuse |
| `hub_diff_accept_edits` | hub | Accept edits | reuse |
| `hub_diff_bad_result` | hub | Bad result | reuse |
| `hub_diff_changes_one` | hub | {{count}} Change | reuse |
| `hub_diff_changes_other` | hub | {{count}} Changes | reuse |
| `hub_diff_configure_polish` | hub | Configure Polish | reuse |
| `hub_diff_copied` | hub | Copied! | reuse |
| `hub_diff_copy_polished_text` | hub | Copy polished text | reuse |
| `hub_diff_good_result` | hub | Good result | reuse |
| `hub_diff_retry_polish` | hub | Retry polish | reuse |
| `hub_diff_undo` | hub | ← {{shortcut}} to Undo | reuse |
| `hub_instruct_chat_abort_processing_aria_label` | hub | Stop processing | reuse |
| `hub_instruct_chat_close_aria_label` | hub | Close | reuse |
| `hub_instruct_chat_default_draft_reply` | hub | `Open your inbox and say<1>"draft a reply to this"</1>` | reuse |
| `hub_instruct_chat_default_draft_reply_aria` | hub | Open your inbox and say draft a reply to this | reuse |
| `hub_instruct_chat_default_make_concise` | hub | `Highlight a sentence and say<1>"make this more concise"</1>` | reuse |
| `hub_instruct_chat_default_make_concise_aria` | hub | Highlight a sentence and say make this more concise | reuse |
| `hub_instruct_chat_default_polish` | hub | `Clean up a dictation by saying<1>"Polish this"</1>` | reuse |
| `hub_instruct_chat_default_polish_aria` | hub | Clean up a dictation by saying Polish this | reuse |
| `hub_instruct_chat_default_teach_style` | hub | `Teach Flow your style by saying<1>"No exclamations in email"</1>` | reuse |
| `hub_instruct_chat_default_teach_style_aria` | hub | Teach Flow your style by saying No exclamations in email | reuse |
| `hub_instruct_chat_dictate_hint` | hub | to instruct | reuse |
| `hub_instruct_chat_feedback_cancel` | hub | Cancel | reuse |
| `hub_instruct_chat_feedback_label_down` | hub | What went wrong | reuse |
| `hub_instruct_chat_feedback_optional` | hub | (optional) | reuse |
| `hub_instruct_chat_feedback_submit` | hub | Submit | reuse |
| `hub_instruct_chat_feedback_submitted` | hub | Submitted | reuse |
| `hub_instruct_chat_follow_up_placeholder` | hub | Follow up | reuse |
| `hub_instruct_chat_header_default` | hub | Try asking Instruct to: | reuse |
| `hub_instruct_chat_input_placeholder` | hub | Tell Instruct what to do | reuse |
| `hub_instruct_chat_processing_status` | hub | Processing | reuse |
| `hub_instruct_chat_submit_aria_label` | hub | Submit instruction | reuse |
| `hub_instruct_processing_comprehending` | hub | Comprehending | reuse |
| `hub_instruct_processing_figuring_it_out` | hub | Figuring it out | reuse |
| `hub_instruct_processing_finding_tool` | hub | Finding the right tool | reuse |
| `hub_instruct_processing_reading` | hub | Reading | reuse |
| `hub_instruct_read_context_from` | hub | Read context from: | reuse |
| `hub_instruct_routed_context_from` | hub | Routed context from {{app}} | reuse |
| `hub_instruct_tool_almost_there` | hub | Almost there | reuse |
| `hub_instruct_tool_filtering` | hub | Filtering | reuse |
| `hub_instruct_tool_instructing` | hub | Instructing | reuse |
| `hub_instruct_tool_querying_data` | hub | Querying data | reuse |
| `hub_instruct_tool_saving` | hub | Saving | reuse |
| `hub_instruct_tool_sorting` | hub | Sorting | reuse |
| `hub_instruct_tool_updating_settings` | hub | Updating settings | reuse |
| `hub_instruct_tool_writing` | hub | Writing | reuse |
| `hub_instruct_transcribing` | hub | Transcribing | reuse |
| `hub_polish_after_card_label` | hub | Polish 🪄 | reuse |
| `hub_polish_auto_apply_label` | hub | Auto Apply After Dictation | reuse |
| `hub_polish_auto_apply_subtitle` | hub | Run a transform on everything you dictate, automatically. | reuse |
| `hub_polish_auto_apply_tooltip` | hub | When on, the selected transform is applied to your dictation before it is pasted. You can also change this from the wand menu in the Flow Bar. | reuse |
| `hub_polish_auto_apply_transform_disabled_tooltip` | hub | Turn on Auto Apply to choose a transform. | reuse |
| `hub_polish_auto_apply_transform_placeholder` | hub | Choose a transform | reuse |
| `hub_polish_before_card_label` | hub | Original | reuse |
| `hub_polish_beta_badge` | hub | Beta | reuse |
| `hub_polish_card_create_own_subtitle` | hub | Upload your own prompt | reuse |
| `hub_polish_card_create_own_title` | hub | Create your own | reuse |
| `hub_polish_card_polish_subtitle` | hub | Improve clarity and conciseness | reuse |
| `hub_polish_card_polish_title` | hub | {{name}} | reuse |
| `hub_polish_config_base_description` | hub | Polish rewrites your text to sound clearer, in your voice. | reuse |
| `hub_polish_config_base_title` | hub | Polish | reuse |
| `hub_polish_config_choose_shortcut` | hub | Choose a keyboard shortcut | reuse |
| `hub_polish_config_custom_add` | hub | Add | reuse |
| `hub_polish_config_custom_cancel` | hub | Cancel | reuse |
| `hub_polish_config_custom_delete_aria` | hub | Delete rule | reuse |
| `hub_polish_config_custom_placeholder` | hub | Add in any polish prompt instructions | reuse |
| `hub_polish_config_custom_rule_exists_error` | hub | A custom rule with this text already exists | reuse |
| `hub_polish_config_custom_section_heading` | hub | Customize your Polish prompt | reuse |
| `hub_polish_config_error_regenerate_example` | hub | Couldn't regenerate the example. Try again. | reuse |
| `hub_polish_config_error_try_again` | hub | There was an error. Please try again | reuse |
| `hub_polish_config_example_transformed_text` | hub | Example of transformed text | reuse |
| `hub_polish_config_reset_button` | hub | Reset | reuse |
| `hub_polish_config_see_updates` | hub | See Updates | reuse |
| `hub_polish_config_select_rules` | hub | Select rules for Polish | reuse |
| `hub_polish_config_shortcut_to_use` | hub | to use | reuse |
| `hub_polish_configure_custom_prompt_description` | hub | Set up a keyboard shortcut to apply this Transform. | reuse |
| `hub_polish_configure_custom_prompt_name_placeholder` | hub | Boss Mode | reuse |
| `hub_polish_configure_custom_prompt_text_placeholder` | hub | How do you want this Transform to change your text? | reuse |
| `hub_polish_configure_prompt_engineer_description` | hub | Prompt Engineer takes messy, spoken, unstructured thoughts and converts them into a clean, optimized AI prompt. | reuse |
| `hub_polish_configure_prompt_engineer_example_before_text` | hub | I need help writing product descriptions for a skincare brand. The AI should be warm, aspirational, and concise | reuse |
| `hub_polish_controls_input_placeholder` | hub | Try “Make me sound like a CEO” or select a prompt | reuse |
| `hub_polish_controls_send_aria` | hub | Send | reuse |
| `hub_polish_controls_upload_writing_example` | hub | Upload Writing Example | reuse |
| `hub_polish_create_new_button` | hub | Create New | reuse |
| `hub_polish_customize_prompt_label` | hub | Customize prompt. (This is what the final output of the prompt will look like) | reuse |
| `hub_polish_diff_aria_copied` | hub | Copied | reuse |
| `hub_polish_diff_aria_copy` | hub | Copy | reuse |
| `hub_polish_diff_aria_thumbs_down` | hub | Thumbs down | reuse |
| `hub_polish_diff_aria_thumbs_up` | hub | Thumbs up | reuse |
| `hub_polish_diff_modal_subtitle` | hub | Press to see changes in text transforms | reuse |
| `hub_polish_diff_modal_title` | hub | See changes in diff | reuse |
| `hub_polish_example_after_text` | hub | Write a blog post about our new cold brew coffee. Highlight that it's smooth and less acidic. Keep the tone casual and fun. | reuse |
| `hub_polish_example_before_text` | hub | make a blog post about our new cold brew coffee, mention its smooth and less acidic, keep it casual and fun | reuse |
| `hub_polish_example_prompt_engineer_text` | hub | Role: Brand content writer.\n\nTask: Write a casual, fun blog post about a new cold brew coffee.\n\nKey points: Smooth taste, low acidity.\n\nTone: Casual and fun. | reuse |
| `hub_polish_examples_modal_add_title` | hub | Add writing sample | reuse |
| `hub_polish_examples_modal_cancel` | hub | Cancel | reuse |
| `hub_polish_examples_modal_edit_title` | hub | Edit writing sample | reuse |
| `hub_polish_examples_modal_field_label` | hub | Writing Sample | reuse |
| `hub_polish_examples_modal_helper` | hub | Minimum {{min}} words. Longer samples help us learn your style better. | reuse |
| `hub_polish_examples_modal_placeholder` | hub | Paste your writing sample here. This could be an email you've written, a message, a document, or any other text that represents your writing style. | reuse |
| `hub_polish_examples_modal_save` | hub | Save | reuse |
| `hub_polish_examples_modal_subtitle` | hub | Paste a sample of your writing to help build your voice profile. | reuse |
| `hub_polish_examples_modal_word_count_one` | hub | {{count}} word | reuse |
| `hub_polish_examples_modal_word_count_other` | hub | {{count}} words | reuse |
| `hub_polish_examples_modal_word_count_with_max_one` | hub | {{count}}/{{max}} word | reuse |
| `hub_polish_examples_modal_word_count_with_max_other` | hub | {{count}}/{{max}} words | reuse |
| `hub_polish_info_description` | hub | `<accent>Transform</accent> your text to\n<em>sound however you want</em>` | reuse |
| `hub_polish_info_extra_feature_optimize_for_llm` | hub | Optimize text for LLM. | reuse |
| `hub_polish_info_extra_feature_translate_any_language` | hub | Translate to any language | reuse |
| `hub_polish_info_feature_add_structure_readability` | hub | Add structure for readability | reuse |
| `hub_polish_info_feature_maintain_tone` | hub | Maintain your tone | reuse |
| `hub_polish_info_feature_make_concise` | hub | Make more concise | reuse |
| `hub_polish_info_feature_reorder_readability` | hub | Reorder for readability | reuse |
| `hub_polish_info_feature_reword_clarity` | hub | Reword for clarity | reuse |
| `hub_polish_modal_reset_cancel` | hub | Cancel | reuse |
| `hub_polish_modal_reset_confirm` | hub | Yes | reuse |
| `hub_polish_modal_reset_description` | hub | Built-in transforms are restored to their defaults, and all custom transforms are removed. | reuse |
| `hub_polish_modal_reset_title` | hub | Are you sure you want to reset? | reuse |
| `hub_polish_my_transforms_heading` | hub | My Transforms | reuse |
| `hub_polish_my_voice_subtitle` | hub | Auto generated | reuse |
| `hub_polish_opt_in_label` | hub | Opt in | reuse |
| `hub_polish_prompt_default_subtitle_constructs` | hub | Constructs optimal prompts | reuse |
| `hub_polish_prompt_default_subtitle_custom` | hub | Custom transform shortcut | reuse |
| `hub_polish_prompt_default_title_custom` | hub | Custom Prompt | reuse |
| `hub_polish_prompt_engineer_title` | hub | Prompt Engineer | reuse |
| `hub_polish_reset_defaults_button` | hub | Reset to defaults | reuse |
| `hub_polish_shortcut_pill_label` | hub | to view changes | reuse |
| `hub_polish_title` | hub | Transforms | reuse |
| `hub_polish_tiy_changes_pill` | hub | see what's changed | reuse |
| `hub_polish_tiy_finished_subheading` | hub | `You can always <shortcut></shortcut> to undo Transform anytime` | reuse |
| `hub_polish_tiy_finished_title` | hub | `<polished>Transformed!</polished> Press <changes></changes> or <shortcut></shortcut> to see changes` | reuse |
| `hub_polish_tiy_start_title` | hub | `<highlight>Highlight text</highlight>, then press <shortcut></shortcut> to Transform` | reuse |
| `hub_polish_tiy_turn_on_transforms` | hub | Turn on Transforms | reuse |
| `hub_polish_toast_save_error` | hub | Failed to save, try again | reuse |
| `hub_polish_toast_settings_reset` | hub | Settings reset | reuse |
| `hub_polish_toggle_tooltip` | hub | Toggles the Transforms feature to update your text with a single shortcut. Resets the shortcuts to default when disabled. | reuse |
| `hub_polish_writing_samples_hint` | hub | Set up the name, shortcut, and prompt above to add writing samples. | reuse |

### Notetaker (meetings)

#### Flow bar meeting pill, meeting reminders, meetings drawer and detected-meeting prompts (95)

Keys the status (flow bar) and contextMenu windows use for meetings: the calendar/meeting pill on the bar, the upcoming-meetings drawer, join/start actions and the switch-meeting prompt.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `meeting_recorder_switch_action_no` | ntf | No | reuse |
| `meeting_recorder_switch_action_start` | ntf | Start | reuse |
| `meeting_recorder_switch_action_switch` | ntf | Switch | reuse |
| `meeting_recorder_switch_action_switching` | ntf | Switching… | reuse |
| `meeting_recorder_switch_list_title` | ntf | Switch to another meeting? | reuse |
| `meeting_recorder_switch_new_note_title` | ntf | Start a new meeting note? | reuse |
| `meeting_recorder_switch_single_title` | ntf | Switch to "{{name}}"? | reuse |
| `hub_calendar_connect_hover_card_cta_connect` | hub | Connect calendar | reuse |
| `hub_calendar_connect_hover_card_cta_not_now` | hub | Not now | reuse |
| `hub_calendar_connect_hover_card_subtitle` | hub | See your upcoming meetings, and improve quality of post-meeting notes and action items | reuse |
| `hub_calendar_connect_hover_card_title` | hub | Connect your calendar | reuse |
| `hub_calendar_pill_action_starting` | hub | Starting… | reuse |
| `hub_calendar_pill_autostart_description` | hub | Starts automatically when the countdown ends | reuse |
| `hub_calendar_pill_countdown_minutes` | hub | In {{minutes}} min | reuse |
| `hub_calendar_pill_join_record` | hub | Join + Start | reuse |
| `hub_calendar_pill_menu_auto_start` | hub | Start Notetaker automatically | reuse |
| `hub_calendar_pill_menu_notification_settings` | hub | Notification settings | reuse |
| `hub_calendar_pill_menu_snooze` | hub | Snooze for 2 min | reuse |
| `hub_calendar_pill_menu_start_notetaker` | hub | Start Notetaker | reuse |
| `hub_calendar_pill_now` | hub | Now | reuse |
| `hub_calendar_pill_stack_count_aria_one` | hub | {{count}} meeting reminder | reuse |
| `hub_calendar_pill_stack_count_aria_other` | hub | {{count}} meeting reminders | reuse |
| `hub_calendar_reminder_dismiss_all_aria` | hub | Dismiss all reminders | reuse |
| `hub_calendar_reminder_dismiss_aria` | hub | Dismiss reminder | reuse |
| `hub_calendar_reminder_open_wispr_button` | hub | Open Wispr | reuse |
| `hub_calendar_reminder_title_autodetect` | hub | Meeting detected | reuse |
| `hub_calendar_reminder_title_scheduled` | hub | Meeting starting | reuse |
| `hub_meeting_pill_action_items` | hub | Action Items | reuse |
| `hub_meeting_pill_ai_summary` | hub | Summary | reuse |
| `hub_meeting_pill_ai_summary_generating` | hub | Generating Summary... | reuse |
| `hub_meeting_pill_artifacts` | hub | Artifacts | reuse |
| `hub_meeting_pill_calendar_connect` | hub | Connect calendar | reuse |
| `hub_meeting_pill_my_notes` | hub | My Notes | reuse |
| `hub_meeting_pill_my_notes_disabled_tooltip` | hub | This will scroll to notes you've manually taken | reuse |
| `hub_meeting_pill_popover_ai_summary_body` | hub | When your call is over, we’ll turn the transcript into action items and a summary for you. | reuse |
| `hub_meeting_pill_popover_ai_summary_title` | hub | We’re still listening | reuse |
| `hub_meeting_pill_popover_connect` | hub | Connect | reuse |
| `hub_meeting_pill_popover_connect_apps` | hub | Connect apps | reuse |
| `hub_meeting_pill_popover_connectors_aria` | hub | Connected apps | reuse |
| `hub_meeting_pill_popover_pre_read_example_label` | hub | Example Brief | reuse |
| `hub_meeting_pill_popover_pre_read_example_purpose_a` | hub | Intro call with Tanay Kothari, CEO of Wispr Flow. He’s going to introduce Wispr’s AI Notetaker to you. | reuse |
| `hub_meeting_pill_popover_pre_read_example_purpose_q` | hub | Who you’re meeting | reuse |
| `hub_meeting_pill_popover_pre_read_example_wants_a` | hub | `His goal is for you to fall in love with the Notetaker and understand how it works. See his notes <accent>here</accent>.` | reuse |
| `hub_meeting_pill_popover_pre_read_example_wants_q` | hub | Recent activity | reuse |
| `hub_meeting_pill_popover_pre_read_title` | hub | Want better context for your calls? | reuse |
| `hub_meeting_pill_pre_read` | hub | Brief | reuse |
| `hub_meeting_pill_row_aria` | hub | Meeting sections | reuse |
| `hub_meetings_drawer_collapse` | hub | Collapse | reuse |
| `hub_meetings_drawer_empty_done_title` | hub | You're all done for today! | reuse |
| `hub_meetings_drawer_join_meeting` | hub | Join meeting | reuse |
| `hub_meetings_drawer_join_start` | hub | Join + Start | reuse |
| `hub_meetings_drawer_start_new_note` | hub | Start new note | reuse |
| `hub_meetings_drawer_start_notes` | hub | Start notes | reuse |
| `hub_meetings_drawer_start_notetaker` | hub | & start Notetaker | reuse |
| `hub_meetings_preread_pill_label` | hub | Brief | reuse |
| `hub_meetings_preread_toggle_hide_aria` | hub | Hide brief | reuse |
| `hub_meetings_preread_toggle_show_aria` | hub | Show brief | reuse |
| `hub_meetings_switch_confirm_action_cancel` | hub | No | reuse |
| `hub_meetings_switch_confirm_action_stop` | hub | Stop and switch | reuse |
| `hub_meetings_switch_confirm_subtitle` | hub | Stop Notetaker for "{{title}}"? You can resume it later. | reuse |
| `hub_meetings_switch_confirm_subtitle_untitled` | hub | Stop Notetaker for the current recording? You can resume it later. | reuse |
| `hub_meetings_switch_confirm_title` | hub | Stop Notetaker? | reuse |
| `hub_meetings_upcoming_join_aria` | hub | Join {{title}} | reuse |
| `hub_meetings_upcoming_join_button` | hub | Join | reuse |
| `hub_meetings_upcoming_join_menu_close_aria` | hub | Close meeting actions menu | reuse |
| `hub_meetings_upcoming_join_menu_open_aria` | hub | Open meeting actions menu | reuse |
| `hub_meetings_upcoming_join_open_wispr` | hub | Just open Wispr | reuse |
| `hub_meetings_upcoming_join_open_wispr_aria` | hub | Open Wispr without joining the meeting | reuse |
| `hub_meetings_upcoming_join_primary_label` | hub | Join meeting | reuse |
| `hub_meetings_upcoming_join_secondary_label` | hub | & open Wispr | reuse |
| `hub_notetaker_hover_card_badge` | hub | New | reuse |
| `hub_notetaker_hover_card_cta_learn` | hub | See how it works | reuse |
| `hub_notetaker_hover_card_cta_start` | hub | Start note | reuse |
| `hub_notetaker_hover_card_dismiss_aria` | hub | Dismiss | reuse |
| `hub_notetaker_hover_card_subtitle` | hub | Get a full transcript with accurate notes and action items, all without typing. | reuse |
| `hub_notetaker_hover_card_title` | hub | Transcribe meetings with Notetaker | reuse |
| `hub_notetaker_new_recording` | hub | New note | reuse |
| `hub_notetaker_new_recording_limit_tooltip` | hub | Resets {{resetDate}} | reuse |
| `hub_notetaker_new_recording_tooltip` | hub | New note — opens notepad and starts Notetaker ({{shortcut}}) | reuse |
| `hub_notetaker_record` | hub | Start | reuse |
| `hub_notetaker_start_notetaker` | hub | Start Notetaker | reuse |
| `hub_notetaker_start_notetaker_tooltip` | hub | Opens the notepad and starts recording ({{shortcut}}) | reuse |
| `hub_status_meeting_pill_wrapping_up` | hub | Wrapping up… | reuse |
| `hub_status_stop_recording_tooltip` | hub | Stop Notetaker | reuse |
| `hub_status_tooltip_meeting_and_note` | hub | Meeting & Note | reuse |
| `hub_status_tooltip_mr_new_meeting` | hub | New meeting | reuse |
| `hub_status_tooltip_record_meeting` | hub | Take notes | reuse |
| `hub_status_tooltip_record_meeting_enterprise_blocked` | hub | Notetaker isn't available on Enterprise plans yet | drop |
| `hub_status_tooltip_record_meeting_finishing` | hub | Finishing up the last recording… | reuse |
| `hub_status_tooltip_record_meeting_triple` | hub | Start note triple-tap {{keys}} | reuse |
| `hub_status_tooltip_record_meeting_windows_blocked` | hub | Notetaker isn't available on Windows yet | drop |
| `hub_status_tooltip_show_note` | hub | Show Note | reuse |
| `hub_status_tooltip_show_notepad` | hub | Show Notepad | reuse |
| `hub_status_tooltip_start_notetaker_triple` | hub | Start Notetaker triple-tap {{keys}} | reuse |
| `recording_pill_label` | hub | Listening | reuse |

#### Notetaker setup gate, first-run tour, walkthrough and welcome (146)

`feature_tour` window and the setup gate shown before the first recording.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_explore_notetaker_coachmark_card_close` | hub | Dismiss | reuse |
| `hub_explore_notetaker_coachmark_card_cta` | hub | Check it out | reuse |
| `hub_explore_notetaker_coachmark_card_subtitle` | hub | Notetaker transcribes and takes notes for your meetings so you can stay present | reuse |
| `hub_explore_notetaker_coachmark_card_title` | hub | Explore Notetaker | reuse |
| `hub_explore_notetaker_sidebar_cta_button` | hub | Check it out | reuse |
| `hub_explore_notetaker_sidebar_cta_subtitle` | hub | Get a transcript, summary, and action items for every meeting | reuse |
| `hub_explore_notetaker_sidebar_cta_title` | hub | Explore Notetaker | reuse |
| `hub_first_real_reveal_banner_body` | hub | Connect a calendar for more accurate speaker names and detailed summaries. | reuse |
| `hub_first_real_reveal_banner_connected` | hub | Connected | reuse |
| `hub_first_real_reveal_banner_title` | hub | Get notes like this for every meeting | reuse |
| `hub_first_real_reveal_bar_complete` | hub | Meeting complete! | reuse |
| `hub_first_real_reveal_bar_summary` | hub | Your summary and action items | reuse |
| `hub_first_summary_celebration_cta` | hub | Explore Summary | reuse |
| `hub_first_summary_celebration_title_one` | hub | {{words}} word summarized | reuse |
| `hub_first_summary_celebration_title_other` | hub | {{words}} words summarized | reuse |
| `hub_meeting_coachmark_pre_read_connect` | hub | Check this out | reuse |
| `hub_meeting_nux_checklist_ask_anything` | hub | Click “What did I miss?” to catch up | reuse |
| `hub_meeting_nux_checklist_auto_notes` | hub | We'll generate notes when your meeting is over | reuse |
| `hub_meeting_nux_checklist_take_notes` | hub | Take notes here | reuse |
| `hub_meeting_nux_notes_header` | hub | Welcome to Notetaker | reuse |
| `hub_notetaker_enterprise_blocked_access_requested` | hub | Access requested | drop |
| `hub_notetaker_enterprise_blocked_contact_admin` | hub | Contact your admin if you have questions. | drop |
| `hub_notetaker_enterprise_blocked_description` | hub | Your organization's privacy settings don't allow access to Notetaker. | drop |
| `hub_notetaker_enterprise_blocked_request_access` | hub | Request access | drop |
| `hub_notetaker_enterprise_blocked_team_fallback` | hub | team | drop |
| `hub_notetaker_enterprise_blocked_title` | hub | Unavailable due to {{teamName}} settings | drop |
| `hub_notetaker_enterprise_plan_blocked_description` | hub | Our new meeting notetaker tool will become available for enterprise plans soon. | drop |
| `hub_notetaker_enterprise_plan_blocked_title` | hub | Notetaker is coming soon! | drop |
| `hub_notetaker_first_transcript_notes_coachmark_title` | hub | Take your own notes here | reuse |
| `hub_notetaker_seeded_tour_calendar_generic` | hub | your calendar | reuse |
| `hub_notetaker_seeded_tour_skip` | hub | Skip | reuse |
| `hub_notetaker_seeded_tour_start` | hub | Start | reuse |
| `hub_notetaker_seeded_tour_subtitle` | hub | 2 minute guided tour | reuse |
| `hub_notetaker_seeded_tour_title` | hub | Try Notetaker | reuse |
| `hub_notetaker_setup_card_calendar` | hub | Connect calendar | reuse |
| `hub_notetaker_setup_card_celebration_subtitle` | hub | Go crush your next meeting | reuse |
| `hub_notetaker_setup_card_celebration_title` | hub | All set! | reuse |
| `hub_notetaker_setup_card_import` | hub | Import from Granola or Otter | drop |
| `hub_notetaker_setup_card_mcp` | hub | Set up MCP | drop |
| `hub_notetaker_setup_card_progress_aria` | hub | Notetaker setup progress | reuse |
| `hub_notetaker_setup_card_skip_aria` | hub | Skip {{item}} | reuse |
| `hub_notetaker_setup_card_skip_confirm_calendar_body` | hub | Connecting your calendar allows you to join meetings more easily and get accurate labels for your teammates | reuse |
| `hub_notetaker_setup_card_skip_confirm_close` | hub | Close | reuse |
| `hub_notetaker_setup_card_skip_confirm_connect` | hub | Connect | reuse |
| `hub_notetaker_setup_card_skip_confirm_mcp_body` | hub | Our MCP connection allows your AI tools to search your notes, answer questions and take actions from your calls. | drop |
| `hub_notetaker_setup_card_skip_confirm_skip` | hub | Yes, skip | reuse |
| `hub_notetaker_setup_card_skip_confirm_title` | hub | Are you sure? | reuse |
| `hub_notetaker_setup_card_skip_tour_aria` | hub | Skip the tour | reuse |
| `hub_notetaker_setup_card_state_done` | hub | Done | reuse |
| `hub_notetaker_setup_card_state_skipped` | hub | Skipped | reuse |
| `hub_notetaker_setup_card_title` | hub | Set up Notetaker | reuse |
| `hub_notetaker_setup_card_try` | hub | Try Notetaker | reuse |
| `hub_notetaker_setup_card_try_tour` | hub | Take 2-min tour | reuse |
| `hub_notetaker_setup_card_undo_aria` | hub | Undo skipping {{item}} | reuse |
| `hub_notetaker_setup_card_undo_tour_aria` | hub | Undo skipping the tour | reuse |
| `hub_notetaker_setup_gate_all_set` | hub | All set! | reuse |
| `hub_notetaker_setup_gate_close_notetaker` | hub | Back | reuse |
| `hub_notetaker_setup_gate_microphone_subtitle` | hub | Capture what you say | reuse |
| `hub_notetaker_setup_gate_microphone_title` | hub | Enable Microphone | reuse |
| `hub_notetaker_setup_gate_microphone_title_done` | hub | Microphone enabled | reuse |
| `hub_notetaker_setup_gate_open_settings` | hub | Open Settings | reuse |
| `hub_notetaker_setup_gate_privacy_link` | hub | `Always ask for consent before transcribing. Read our <u>privacy policy</u>` | reuse |
| `hub_notetaker_setup_gate_restart_flow` | hub | Restart Wispr Flow | reuse |
| `hub_notetaker_setup_gate_subtitle_one` | hub | These are required settings | reuse |
| `hub_notetaker_setup_gate_subtitle_other` | hub | These are required settings | reuse |
| `hub_notetaker_setup_gate_subtitle_unsupported` | hub | Notetaker needs macOS 13 or later to record meetings | reuse |
| `hub_notetaker_setup_gate_system_audio_subtitle` | hub | Capture what others say | reuse |
| `hub_notetaker_setup_gate_system_audio_subtitle_denied` | hub | Allow Wispr Flow under System Audio Recording in System Settings | reuse |
| `hub_notetaker_setup_gate_system_audio_subtitle_restart` | hub | Restart the app after enabling system audio | reuse |
| `hub_notetaker_setup_gate_system_audio_subtitle_unsupported` | hub | Capturing what others say requires macOS 13 or later | reuse |
| `hub_notetaker_setup_gate_system_audio_title` | hub | Enable System Audio | reuse |
| `hub_notetaker_setup_gate_system_audio_title_done` | hub | System audio enabled | reuse |
| `hub_notetaker_setup_gate_system_audio_title_restart` | hub | Restart Wispr Flow to apply changes | reuse |
| `hub_notetaker_setup_gate_system_audio_title_unsupported` | hub | System audio not available | reuse |
| `hub_notetaker_setup_gate_title` | hub | Complete setup to start Notetaker | reuse |
| `hub_notetaker_setup_gate_turn_on` | hub | Turn on | reuse |
| `hub_notetaker_setup_gate_waiting` | hub | Waiting… | reuse |
| `hub_notetaker_unsupported_modal_body` | hub | Recording meetings requires macOS 13 or later | reuse |
| `hub_notetaker_unsupported_modal_cta` | hub | Got it | reuse |
| `hub_notetaker_unsupported_modal_title` | hub | Notetaker blocked | reuse |
| `hub_notetaker_windows_coming_soon_description` | hub | Our new meeting notetaker tool will become available on Windows soon. | drop |
| `hub_notetaker_windows_coming_soon_title` | hub | Notetaker is coming soon! | drop |
| `hub_notetaker_windows_connect_apps` | hub | Connect apps | drop |
| `hub_under5_banner_body` | hub | Connect your calendar to get speaker names and a full summary | reuse |
| `hub_under5_banner_body_connected` | hub | Try Notetaker for your next meeting to get a full summary with speaker names | reuse |
| `hub_under5_banner_connect` | hub | Connect calendar | reuse |
| `hub_under5_banner_example_body` | hub | `Creative direction and channel strategy locked ahead of the Q3 launch. <mikel>Mikel</mikel> presented revised assets; <hayle>Hayle</hayle> ran the session with <ruth>Ruth’s</ruth> approval as the remaining gate.` | reuse |
| `hub_under5_banner_example_label` | hub | Example summary | reuse |
| `hub_under5_banner_example_next_steps` | hub | Next Steps | reuse |
| `hub_under5_banner_example_step_1` | hub | `<ruth>Ruth</ruth> to deliver revised asset deck by Friday` | reuse |
| `hub_under5_banner_example_step_2` | hub | `<mikel>Mikel</mikel> to share updated paid brief with media team by EOD` | reuse |
| `hub_under5_banner_example_step_3` | hub | `<ruth>Ruth</ruth> final sign-off on creative by Monday before anything goes live` | reuse |
| `hub_under5_banner_example_title` | hub | Design review | reuse |
| `hub_under5_banner_title` | hub | Summaries shine in longer meetings. | reuse |
| `hub_walkthrough_back` | hub | Back | reuse |
| `hub_walkthrough_collapsed` | hub | We’ll improve the transcript and speaker names after the meeting | reuse |
| `hub_walkthrough_connect_body` | hub | We’ll pull in relevant context to improve speaker naming and summaries | reuse |
| `hub_walkthrough_connect_calendar` | hub | Connect calendar | reuse |
| `hub_walkthrough_connect_title` | hub | Help us get the details right | reuse |
| `hub_walkthrough_explore` | hub | Explore | reuse |
| `hub_walkthrough_finish` | hub | Finish | reuse |
| `hub_walkthrough_next` | hub | Next | reuse |
| `hub_walkthrough_preview` | hub | Example of an enhanced meeting transcript and summary | reuse |
| `hub_walkthrough_progress` | hub | Walkthrough progress | reuse |
| `hub_walkthrough_region` | hub | First meeting walkthrough | reuse |
| `hub_walkthrough_summary_body` | hub | After the meeting, we’ll generate a summary with decisions and next steps. | reuse |
| `hub_walkthrough_summary_title` | hub | Summary will appear here | reuse |
| `hub_walkthrough_transcript_body` | hub | We’ll identify each speaker and clean up the transcript once you stop | reuse |
| `hub_walkthrough_transcript_title` | hub | Speaker names are added later | reuse |
| `notetaker_beta_modal_badge` | hub | Beta | reuse |
| `notetaker_beta_modal_body` | hub | Get accurate transcripts and action-ready summaries | reuse |
| `notetaker_beta_modal_close_aria` | hub | Dismiss | reuse |
| `notetaker_beta_modal_cta` | hub | Check it out | reuse |
| `notetaker_beta_modal_title` | hub | Introducing Notetaker for meetings | reuse |
| `notetaker_enterprise_enabled_modal_title` | hub | Your organization has enabled Notetaker | drop |
| `notetaker_first_meeting_modal_accidental_start_body` | hub | Get notes on your next meeting by connecting your calendar, or take a quick tour of Notetaker first. | reuse |
| `notetaker_first_meeting_modal_accidental_start_connect_cta` | hub | Connect calendar | reuse |
| `notetaker_first_meeting_modal_accidental_start_title` | hub | Ready to give Wispr Notetaker a try? | reuse |
| `notetaker_first_meeting_modal_accidental_start_tour_cta` | hub | Take the guided tour | reuse |
| `notetaker_first_meeting_modal_close_aria` | hub | Dismiss | reuse |
| `notetaker_first_meeting_modal_notes_ready_body` | hub | “{{title}}” is summarized: key points, decisions, and next steps. | reuse |
| `notetaker_first_meeting_modal_notes_ready_body_untitled` | hub | Your meeting is summarized: key points, decisions, and next steps. | reuse |
| `notetaker_first_meeting_modal_notes_ready_cta` | hub | View your meeting notes | reuse |
| `notetaker_first_meeting_modal_notes_ready_title` | hub | Your meeting notes are ready | reuse |
| `notetaker_first_meeting_modal_sample_decision_1` | hub | Lead with the launch video across paid and organic | reuse |
| `notetaker_first_meeting_modal_sample_decision_2` | hub | Hold the Q3 date; no scope additions | reuse |
| `notetaker_first_meeting_modal_sample_decisions` | hub | Decisions | reuse |
| `notetaker_first_meeting_modal_sample_next_step_1` | hub | Ruth to deliver revised asset deck by Friday | reuse |
| `notetaker_first_meeting_modal_sample_next_step_2` | hub | Mikel to share updated paid brief with media team | reuse |
| `notetaker_first_meeting_modal_sample_next_steps` | hub | Next Steps | reuse |
| `notetaker_first_meeting_modal_sample_overview` | hub | Mikel locked creative direction for Q3; Ruth’s sign-off is the last gate. | reuse |
| `notetaker_first_meeting_modal_sample_title` | hub | Q3 launch planning | reuse |
| `notetaker_first_meeting_modal_short_connect_body` | hub | That was a quick meeting! Connect your calendar and Notetaker will be ready for your next meeting. | reuse |
| `notetaker_first_meeting_modal_short_connect_cta` | hub | Connect calendar | reuse |
| `notetaker_first_meeting_modal_short_connected_body` | hub | That was a quick meeting! Your next calendar meeting gets full notes, action items, and a transcript. | reuse |
| `notetaker_first_meeting_modal_short_title` | hub | Congrats on your first meeting! | reuse |
| `notetaker_first_meeting_modal_view_note_cta` | hub | View meeting note | reuse |
| `notetaker_tour_exit_confirm_body` | hub | Users who finish this 2-min tutorial get 2x more from Notetaker. | reuse |
| `notetaker_tour_exit_confirm_continue` | hub | Continue tutorial | reuse |
| `notetaker_tour_exit_confirm_quit` | hub | Yes, exit | reuse |
| `notetaker_tour_exit_confirm_title` | hub | Are you sure? | reuse |
| `notetaker_welcome_modal_body` | hub | Get accurate transcripts and action-ready summaries | reuse |
| `notetaker_welcome_modal_close_aria` | hub | Dismiss | reuse |
| `notetaker_welcome_modal_cta` | hub | Give it a try | reuse |
| `notetaker_welcome_modal_later` | hub | Later | reuse |
| `notetaker_welcome_modal_title` | hub | Try Notetaker for meetings | reuse |

#### Ask about meetings: in-meeting chat, Ask Wispr search chat, presets and skills (70)

Answered by the local LLM in the rebuild. Skills and MCP/AI-app connector rows are `drop`.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_ask_mcp_hint` | hub | Want to access your notes in [AI chat app], [AI chat app], [AI chat app] and more? | drop |
| `hub_ask_mcp_hint_cta` | hub | Set up MCP | drop |
| `hub_ask_mcp_hint_dismiss_aria` | hub | Dismiss | drop |
| `hub_ask_wispr_bar_aria` | hub | Ask Wispr about your meetings | reuse |
| `hub_ask_wispr_bar_placeholder` | hub | Ask anything | reuse |
| `hub_ask_wispr_chat_actions_aria` | hub | Chat actions | reuse |
| `hub_ask_wispr_chat_ready_aria` | hub | New response ready | reuse |
| `hub_ask_wispr_composer_placeholder` | hub | Ask a follow-up about your meetings | reuse |
| `hub_ask_wispr_empty_prompt` | hub | Ask Wispr anything about your meetings | reuse |
| `hub_ask_wispr_new_chat` | hub | New chat | reuse |
| `hub_ask_wispr_past_chats` | hub | Past chats | reuse |
| `hub_ask_wispr_prompt_coach_me` | hub | Coach me | reuse |
| `hub_ask_wispr_prompt_list_recent_todos` | hub | List recent todos | reuse |
| `hub_ask_wispr_prompt_weekly_recap` | hub | Write a weekly recap | rewrite |
| `hub_ask_wispr_sources_aria` | hub | Sources | reuse |
| `hub_ask_wispr_submit_aria` | hub | Submit query | reuse |
| `hub_meeting_ask_anything_placeholder` | hub | Ask anything | reuse |
| `hub_meeting_ask_prompt_follow_up_email` | hub | Write a follow-up email | rewrite |
| `hub_meeting_ask_prompt_identify_blind_spots` | hub | Identify blind spots | reuse |
| `hub_meeting_ask_prompt_make_notes_longer` | hub | Make notes longer | reuse |
| `hub_meeting_ask_prompt_sound_smart` | hub | Make me sound smart | reuse |
| `hub_meeting_ask_prompt_suggest_questions` | hub | Suggest questions | reuse |
| `hub_meeting_ask_summary_generating` | hub | Generating flow summary… | reuse |
| `hub_meeting_ask_what_did_i_miss` | hub | What did I miss? | reuse |
| `hub_meeting_ask_what_did_i_miss_empty` | hub | Nothing new since you last looked. | reuse |
| `hub_meeting_chat_artifact_created` | hub | Created artifact: {{title}} | reuse |
| `hub_meeting_chat_artifact_fallback_title` | hub | Artifact | reuse |
| `hub_meeting_chat_notes_updated` | hub | Updated meeting notes. | reuse |
| `hub_meeting_chat_send_failed` | hub | Something went wrong. Please try again. | reuse |
| `hub_notetaker_ask_close_aria` | hub | Close | reuse |
| `hub_notetaker_ask_copy_aria` | hub | Copy response | reuse |
| `hub_notetaker_ask_copy_copied` | hub | Response copied | reuse |
| `hub_notetaker_ask_copy_failed` | hub | Couldn't copy response | reuse |
| `hub_notetaker_ask_error` | hub | Something went wrong. Try again. | reuse |
| `hub_notetaker_ask_input_aria` | hub | Ask about your meetings | reuse |
| `hub_notetaker_ask_placeholder` | hub | open action items from yesterday | reuse |
| `hub_notetaker_ask_response_aria` | hub | Ask response | reuse |
| `hub_notetaker_ask_submit_aria` | hub | Ask | reuse |
| `hub_notetaker_ask_thinking` | hub | Thinking | reuse |
| `hub_notetaker_chat_ask_error` | hub | Could not get a response. Try again. | reuse |
| `hub_notetaker_chat_delete_confirm` | hub | Delete this chat? This cannot be undone. | reuse |
| `hub_notetaker_chat_history_empty` | hub | No chats yet | reuse |
| `hub_notetaker_chat_history_error` | hub | Could not load chat history. | reuse |
| `hub_notetaker_chat_history_load_more` | hub | Load more | reuse |
| `hub_notetaker_chat_history_loading` | hub | Loading chats… | reuse |
| `hub_notetaker_chat_history_months_ago` | hub | {{count}} months ago | reuse |
| `hub_notetaker_chat_history_one_month_ago` | hub | 1 month ago | reuse |
| `hub_notetaker_chat_history_two_weeks_ago` | hub | 2 weeks ago | reuse |
| `hub_notetaker_chat_loading` | hub | Loading chat… | reuse |
| `hub_notetaker_chat_new` | hub | New chat | reuse |
| `hub_notetaker_chat_rename_prompt` | hub | Rename chat | reuse |
| `hub_notetaker_chat_request_error` | hub | Something went wrong. Try again. | reuse |
| `hub_notetaker_chat_response_incomplete` | hub | This response did not complete. | reuse |
| `hub_notetaker_chat_response_stopped` | hub | [Request stopped] | reuse |
| `hub_notetaker_chat_retry` | hub | Retry | reuse |
| `hub_notetaker_chat_save_error` | hub | Could not save this message. Try again. | reuse |
| `hub_notetaker_chat_stop_aria` | hub | Stop processing | reuse |
| `hub_notetaker_chat_untitled` | hub | Untitled chat | reuse |
| `hub_skills_button` | hub | Skills | drop |
| `hub_skills_empty_prebuilt` | hub | No skills for this chat yet. | drop |
| `hub_skills_empty_search` | hub | No skills match “{{query}}”. | drop |
| `hub_skills_empty_yours` | hub | Skills you create will show up here. | drop |
| `hub_skills_error` | hub | Couldn't load skills. | drop |
| `hub_skills_loading` | hub | Loading skills… | drop |
| `hub_skills_retry` | hub | Try again | drop |
| `hub_skills_search_placeholder` | hub | Search skills | drop |
| `hub_skills_tab_prebuilt` | hub | Prebuilt | drop |
| `hub_skills_tab_yours` | hub | Your skills | drop |
| `hub_skills_turn_label` | hub | Skill: | drop |
| `notetaker_connect_ai_tools` | hub | Connect to your AI tools | drop |

#### Meeting window: header, notepad editor, recording controls, consent notice (165)

The `meeting_recorder` window (678 keys referenced) hosts the notepad, live transcript, summary and tasks for one meeting.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_meeting_action_items_add` | hub | Add action item | reuse |
| `hub_meeting_action_items_archive_all` | hub | Archive all | reuse |
| `hub_meeting_action_items_complete_all` | hub | Mark all as completed | reuse |
| `hub_meeting_action_items_empty` | hub | No remaining action items for this meeting | reuse |
| `hub_meeting_action_items_title` | hub | Action Items | reuse |
| `hub_meeting_action_items_view_all` | hub | View all in Tasks | reuse |
| `hub_meeting_append_added` | hub | {{sectionLabel}} added | reuse |
| `hub_meeting_append_failed` | hub | Couldn't generate {{sectionLabel}} | reuse |
| `hub_meeting_append_generating` | hub | Generating {{sectionLabel}}… | reuse |
| `hub_meeting_connect_callout_body` | hub | Connect to get briefs with context from all your tools. | reuse |
| `hub_meeting_connect_callout_dismiss` | hub | Dismiss | reuse |
| `hub_meeting_connect_callout_title` | hub | Prep for your next meeting | reuse |
| `hub_meeting_detail_region_aria` | hub | Meeting detail | reuse |
| `hub_meeting_drawer_chat_empty` | hub | Ask anything about this meeting | reuse |
| `hub_meeting_drawer_chat_empty_shared_hint` | hub | Chats for shared notes are not saved | drop |
| `hub_meeting_drawer_chat_scroll_to_bottom` | hub | Scroll to bottom | reuse |
| `hub_meeting_drawer_chat_switch_aria` | hub | Switch chat session | reuse |
| `hub_meeting_drawer_chat_switch_tooltip` | hub | Switch chat | reuse |
| `hub_meeting_drawer_chat_tab` | hub | Chat | reuse |
| `hub_meeting_drawer_copy_failed` | hub | Copy failed | reuse |
| `hub_meeting_drawer_copy_transcript_aria` | hub | Copy transcript | reuse |
| `hub_meeting_drawer_copy_transcript_tooltip` | hub | Copy transcript | reuse |
| `hub_meeting_drawer_minimize_aria` | hub | Minimize drawer | reuse |
| `hub_meeting_drawer_minimize_tooltip` | hub | Minimize | reuse |
| `hub_meeting_drawer_no_transcript` | hub | No transcript to copy | reuse |
| `hub_meeting_drawer_search_close_aria` | hub | Close search | reuse |
| `hub_meeting_drawer_search_placeholder` | hub | Search transcript… | reuse |
| `hub_meeting_drawer_search_transcript_aria` | hub | Search transcript | reuse |
| `hub_meeting_drawer_search_transcript_tooltip` | hub | Search transcript | reuse |
| `hub_meeting_drawer_speaker_others` | hub | Them | reuse |
| `hub_meeting_drawer_speaker_you` | hub | You | reuse |
| `hub_meeting_drawer_transcript_copied` | hub | Transcript copied | reuse |
| `hub_meeting_drawer_transcript_deleted` | hub | Transcript deleted based on your retention settings policy | reuse |
| `hub_meeting_drawer_transcript_deleted_settings_aria` | hub | Open retention settings | reuse |
| `hub_meeting_drawer_transcript_tab` | hub | Transcript | reuse |
| `hub_meeting_editor_dictate_aria` | hub | {{pttKey}} to dictate | reuse |
| `hub_meeting_editor_new_meeting` | hub | New note | reuse |
| `hub_meeting_editor_thoughts_placeholder` | hub | Write your notes here. We'll make a separate summary at the end. | reuse |
| `hub_meeting_editor_thoughts_summary_placeholder` | hub | `Your summary is ready. <1>Check it out →</1>` | reuse |
| `hub_meeting_editor_to_dictate_suffix` | hub | ` to dictate` | reuse |
| `hub_meeting_flow_summary_loading_generating` | hub | Generating summary... | reuse |
| `hub_meeting_flow_summary_loading_processing` | hub | Processing audio... | reuse |
| `hub_meeting_flow_summary_loading_refining` | hub | Refining content... | reuse |
| `hub_meeting_flow_summary_loading_summarizing` | hub | Summarizing meeting... | reuse |
| `hub_meeting_flow_summary_loading_title` | hub | Generating Summary... | reuse |
| `hub_meeting_flow_summary_loading_transcribing` | hub | Transcribing audio... | reuse |
| `hub_meeting_header_all_notes` | hub | All notes | reuse |
| `hub_meeting_header_home` | hub | Home | reuse |
| `hub_meeting_header_split_screen` | hub | Split screen with meeting | reuse |
| `hub_meeting_menu_report` | hub | Report | reuse |
| `hub_meeting_private_thoughts_share_disclosure` | hub | `<em>My thoughts</em> won’t be included when you share this note.` | drop |
| `hub_meeting_recorder_error_boundary_reload_button` | hub | Reload | reuse |
| `hub_meeting_recorder_error_boundary_title` | hub | Something went wrong. Reload to keep recording. | reuse |
| `hub_meeting_recording_consent` | hub | `Always get consent when transcribing others. <learnMoreLink>Learn more</learnMoreLink>` | reuse |
| `hub_meeting_save_failed_badge` | hub | Couldn't save changes | reuse |
| `hub_meeting_section_label_summary` | hub | summary | reuse |
| `hub_meeting_section_label_summary_capitalized` | hub | Summary | reuse |
| `hub_meeting_split_screen_accessibility_required` | hub | Allow Accessibility access for Wispr Flow to arrange windows. | reuse |
| `hub_meeting_system_audio_banner_action` | hub | Turn on | reuse |
| `hub_meeting_system_audio_banner_body` | hub | You're recording your mic only. Turn system audio back on and restart the meeting to capture others. | reuse |
| `hub_meeting_system_audio_banner_title` | hub | System audio turned off | reuse |
| `hub_meeting_window_close` | hub | Close | reuse |
| `hub_meeting_window_maximize` | hub | Maximize | reuse |
| `hub_meeting_window_minimize` | hub | Minimize | reuse |
| `hub_meeting_window_restore` | hub | Restore | reuse |
| `hub_meeting_window_zoom` | hub | Full Screen | reuse |
| `hub_meetings_close_search_aria` | hub | Close search | reuse |
| `hub_meetings_consent_confirm_action_cancel` | hub | Cancel | reuse |
| `hub_meetings_consent_confirm_action_confirm` | hub | Consent obtained | reuse |
| `hub_meetings_consent_confirm_subtitle` | hub | Your organization requires that you ask meeting participants for their permission to transcribe meetings. | rewrite |
| `hub_meetings_consent_confirm_title` | hub | Obtain consent to start Notetaker | reuse |
| `hub_meetings_new_meeting_aria` | hub | New note | reuse |
| `hub_meetings_new_meeting_title` | hub | New note | reuse |
| `hub_meetings_post_processing_complete` | hub | Complete | reuse |
| `hub_meetings_post_processing_generating` | hub | Generating summary | reuse |
| `hub_meetings_post_processing_parsing` | hub | Refining transcript | reuse |
| `hub_meetings_post_processing_row_abandoned` | hub | Abandoned. | reuse |
| `hub_meetings_post_processing_row_failed` | hub | Failed. | reuse |
| `hub_meetings_post_processing_row_generate` | hub | Generate summary | reuse |
| `hub_meetings_post_processing_row_generating` | hub | Generating summary… | reuse |
| `hub_meetings_post_processing_summarizing` | hub | Summarizing meeting | reuse |
| `hub_meetings_post_processing_transcribing` | hub | Transcribing audio | reuse |
| `hub_meetings_post_processing_uploading` | hub | Uploading audio | rewrite |
| `hub_meetings_resume_rejected_record_new_action` | hub | Record as new meeting | reuse |
| `hub_meetings_retry_rate_limited` | hub | Servers are busy. Flow will retry automatically. | rewrite |
| `hub_meetings_retry_rate_limited_at` | hub | Servers are busy. Flow will retry at {{time}}. | rewrite |
| `hub_meetings_transcription_connection_lost` | hub | Connection lost. Audio saved up to here. | reuse |
| `hub_notetaker_attendees_hide` | hub | Hide attendees | reuse |
| `hub_notetaker_attendees_show` | hub | Show attendees | reuse |
| `hub_notetaker_audio_close` | hub | Close audio settings | reuse |
| `hub_notetaker_audio_input` | hub | Input | reuse |
| `hub_notetaker_audio_settings_aria` | hub | Audio settings | reuse |
| `hub_notetaker_audio_title` | hub | Audio | reuse |
| `hub_notetaker_audio_unavailable` | hub | Audio levels unavailable | reuse |
| `hub_notetaker_blocked_admin_hipaa_action` | hub | Open Admin Portal | rewrite |
| `hub_notetaker_blocked_admin_hipaa_body` | hub | Your team's HIPAA Business Associate Agreement (BAA) blocks Notetaker. Revoke the BAA in the Admin Portal to unlock it for everyone. | drop |
| `hub_notetaker_blocked_admin_hipaa_title` | hub | Unlock Notetaker for your team | reuse |
| `hub_notetaker_blocked_close` | hub | Close | reuse |
| `hub_notetaker_blocked_domain_and_others` | hub | and others | reuse |
| `hub_notetaker_blocked_domain_attendees_one` | hub | The attendee that triggered the block for this meeting is: | reuse |
| `hub_notetaker_blocked_domain_attendees_other` | hub | The attendees that triggered the block for this meeting are: | reuse |
| `hub_notetaker_blocked_domain_body` | hub | Your organization's admin has blocked the use of Notetaker when certain attendees are listed on the calendar invite. | rewrite |
| `hub_notetaker_blocked_domain_count_one` | hub | 1 attendee on this invite matches a blocked domain. | reuse |
| `hub_notetaker_blocked_domain_count_other` | hub | {{count}} attendees on this invite match a blocked domain. | reuse |
| `hub_notetaker_blocked_domain_title` | hub | Notetaker blocked for this meeting | reuse |
| `hub_notetaker_blocked_member_action` | hub | Got it | drop |
| `hub_notetaker_blocked_member_hipaa_body` | hub | Your team's settings prevent access to Notetaker. Contact your admin if you have questions. | drop |
| `hub_notetaker_blocked_member_hipaa_title` | hub | Notetaker is unavailable | drop |
| `hub_notetaker_blocked_personal_hipaa_action` | hub | Open Settings | reuse |
| `hub_notetaker_blocked_personal_hipaa_body_v2` | hub | Your HIPAA Business Associate Agreement (BAA) blocks Notetaker. Revoke your BAA in Settings to use Notetaker. | drop |
| `hub_notetaker_blocked_personal_hipaa_title_v2` | hub | Revoke your BAA to use Notetaker | reuse |
| `hub_notetaker_consent_notice_copy_error` | hub | Couldn't copy the message | reuse |
| `hub_notetaker_consent_notice_copy_label` | hub | Copy consent message | reuse |
| `hub_notetaker_consent_notice_copy_success` | hub | Consent message copied | reuse |
| `hub_notetaker_consent_notice_discard_confirm_body` | hub | You'll lose the recording, notes, and transcript for this meeting. Nothing will be saved to Wispr and this can't be undone. | reuse |
| `hub_notetaker_consent_notice_discard_confirm_confirm` | hub | Confirm | reuse |
| `hub_notetaker_consent_notice_discard_confirm_error` | hub | Couldn't discard the meeting. Try again. | reuse |
| `hub_notetaker_consent_notice_discard_confirm_go_back` | hub | Go back | reuse |
| `hub_notetaker_consent_notice_discard_confirm_title` | hub | Discard this meeting? | reuse |
| `hub_notetaker_consent_notice_failed_body` | hub | We couldn’t post a consent message in the meeting chat. Send it yourself or ask participants for their permission to transcribe. | reuse |
| `hub_notetaker_consent_notice_failed_done` | hub | Done | reuse |
| `hub_notetaker_consent_notice_failed_quit_discard` | hub | Quit and discard meeting | reuse |
| `hub_notetaker_consent_notice_failed_title` | hub | Obtain consent | reuse |
| `hub_notetaker_consent_notice_permission_body` | hub | We couldn’t post a consent message in the meeting chat because we’re missing accessibility settings. Send it yourself or ask participants for their permission to transcribe. | reuse |
| `hub_notetaker_consent_notice_permission_open_settings` | hub | Open System Settings | reuse |
| `hub_notetaker_done_stats` | hub | • {{count}} meeting | reuse |
| `hub_notetaker_done_stats_plural` | hub | • {{count}} meetings | reuse |
| `hub_notetaker_done_stats_with_duration` | hub | • {{duration}} across {{count}} meeting | reuse |
| `hub_notetaker_done_stats_with_duration_plural` | hub | • {{duration}} across {{count}} meetings | reuse |
| `hub_notetaker_done_stats_with_words` | hub | • You captured {{words}} words across {{count}} meeting | reuse |
| `hub_notetaker_done_stats_with_words_plural` | hub | • You captured {{words}} words across {{count}} meetings | reuse |
| `hub_notetaker_done_title` | hub | Done for today | reuse |
| `hub_notetaker_done_title_empty` | hub | You're all done for today | reuse |
| `hub_notetaker_done_title_v1` | hub | Done for today | reuse |
| `hub_notetaker_done_title_v10` | hub | Time well spent | reuse |
| `hub_notetaker_done_title_v2` | hub | That's a wrap | reuse |
| `hub_notetaker_done_title_v3` | hub | Nice work today | reuse |
| `hub_notetaker_done_title_v4` | hub | You're all caught up | reuse |
| `hub_notetaker_done_title_v5` | hub | You crushed it today | reuse |
| `hub_notetaker_done_title_v6` | hub | All wrapped up | reuse |
| `hub_notetaker_done_title_v7` | hub | You made it | reuse |
| `hub_notetaker_done_title_v8` | hub | Smooth sailing | reuse |
| `hub_notetaker_done_title_v9` | hub | All squared away | reuse |
| `hub_notetaker_finish_setup_toast` | hub | Finish setup to use Notetaker | reuse |
| `hub_notetaker_guests_label` | hub | Attendees | reuse |
| `hub_notetaker_guests_less` | hub | Show less | reuse |
| `hub_notetaker_guests_more_one` | hub | +{{count}} more | reuse |
| `hub_notetaker_guests_more_other` | hub | +{{count}} more | reuse |
| `hub_notetaker_missing_context_body` | hub | Connect Slack to see relevant context from your messages in briefs. | rewrite |
| `hub_notetaker_missing_context_connect` | hub | Connect | reuse |
| `hub_notetaker_missing_context_dismiss_aria` | hub | Dismiss | reuse |
| `hub_notetaker_missing_context_title` | hub | Missing context from messages? | reuse |
| `hub_notetaker_tab_docs` | hub | Docs | reuse |
| `hub_notetaker_tab_notes` | hub | My thoughts | reuse |
| `hub_notetaker_tab_preread` | hub | Brief | reuse |
| `hub_notetaker_tab_summary` | hub | Summary | reuse |
| `hub_notetaker_tab_tasks` | hub | Tasks | reuse |
| `hub_notetaker_tab_transcript` | hub | Transcript | reuse |
| `hub_notetaker_tab_transcript_locked_tooltip` | hub | To view the transcript, {{ownerFirstName}} must invite you with your email | rewrite |
| `hub_notetaker_tab_transcript_locked_tooltip_no_owner` | hub | To view the transcript, the owner must invite you with your email | rewrite |
| `hub_notetaker_tab_transcript_locked_tooltip_org_policy` | hub | Transcripts aren’t shared for notes from this organization | drop |
| `meeting_markdown_copied` | hub | All meeting contents copied to clipboard | reuse |
| `meeting_markdown_copy_aria` | hub | Copy meeting to Markdown | reuse |
| `meeting_markdown_copy_button` | hub | Copy as Markdown | reuse |
| `meeting_markdown_copy_failed` | hub | Failed to copy meeting | reuse |

#### Live transcript, speakers and people (134)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `contact_info_modal_cancel` | hub | Cancel | reuse |
| `contact_info_modal_email_already_exists_error` | hub | A person with this email already exists | rewrite |
| `contact_info_modal_email_invalid_error` | hub | Enter a valid email | rewrite |
| `contact_info_modal_email_label` | hub | Email (optional) | rewrite |
| `contact_info_modal_email_placeholder` | hub | name@example.com | reuse |
| `contact_info_modal_name_label` | hub | Name | reuse |
| `contact_info_modal_name_placeholder` | hub | Maya Chen | reuse |
| `contact_info_modal_name_required_error` | hub | Enter a name | reuse |
| `contact_info_modal_network_error` | hub | Couldn't add this person. Check your connection and try again. | reuse |
| `contact_info_modal_rate_limited_error` | hub | Couldn't add this person. Try again in a minute. | reuse |
| `contact_info_modal_room_label` | hub | Room (optional) | reuse |
| `contact_info_modal_room_none` | hub | No room | reuse |
| `contact_info_modal_save` | hub | Add person | reuse |
| `contact_info_modal_submit_error` | hub | Couldn't add this person. Try again. | reuse |
| `contact_info_modal_title` | hub | Add person | reuse |
| `hub_assign_contact_add_new` | hub | Add new contact | reuse |
| `hub_assign_contact_add_new_named` | hub | Add new contact “{{name}}” | reuse |
| `hub_assign_contact_unnamed` | hub | Unnamed contact | reuse |
| `hub_assign_contact_which_speaker` | hub | Which {{name}} is this? | reuse |
| `hub_assign_speakers_add_new` | hub | Add new person | reuse |
| `hub_assign_speakers_add_new_named` | hub | Add new person “{{name}}” | reuse |
| `hub_assign_speakers_cancel` | hub | Cancel | reuse |
| `hub_assign_speakers_candidates_aria` | hub | Name suggestions | reuse |
| `hub_assign_speakers_close_aria` | hub | Close | reuse |
| `hub_assign_speakers_contacts_loading_aria` | hub | Searching your contacts | reuse |
| `hub_assign_speakers_in_meeting_tag` | hub | In this meeting | reuse |
| `hub_assign_speakers_keep_typing` | hub | Keep typing to see more matches | reuse |
| `hub_assign_speakers_merge_tag` | hub | Same person | reuse |
| `hub_assign_speakers_name_aria` | hub | Name for {{label}} | reuse |
| `hub_assign_speakers_name_placeholder` | hub | Type a name | reuse |
| `hub_assign_speakers_row_failed` | hub | Couldn’t assign this contact. Try saving again. | reuse |
| `hub_assign_speakers_row_unattempted` | hub | Skipped after an earlier failure. Try saving again. | reuse |
| `hub_assign_speakers_save` | hub | Save names | reuse |
| `hub_assign_speakers_shared_slot` | hub | This recording saved this voice and another one under the same name slot, so it can’t be renamed. Newer recordings aren’t affected. | drop |
| `hub_assign_speakers_subtitle` | hub | Name each voice and we’ll relabel the whole transcript. | reuse |
| `hub_assign_speakers_title` | hub | Assign speakers | reuse |
| `hub_l2_attendees_date_today` | hub | Today | reuse |
| `hub_l2_attendees_date_tomorrow` | hub | Tomorrow | reuse |
| `hub_l2_attendees_date_yesterday` | hub | Yesterday | reuse |
| `hub_l2_meeting_group_count_one` | hub | {{count}} person | reuse |
| `hub_l2_meeting_group_count_other` | hub | {{count}} people | reuse |
| `hub_l2_meeting_group_other` | hub | Other | reuse |
| `hub_l2_meeting_room_voice_count_one` | hub | {{count}} voice | reuse |
| `hub_l2_meeting_room_voice_count_other` | hub | {{count}} voices | reuse |
| `hub_l2_meeting_rooms_heading` | hub | Rooms | reuse |
| `hub_meeting_transcript_empty_prompt` | hub | Try saying “Hi Notetaker” | reuse |
| `hub_meeting_transcript_empty_welcome` | hub | Welcome to Notetaker! | reuse |
| `hub_meeting_transcript_granola_unavailable` | hub | No transcript from Granola. Availability depends on your Granola plan. | drop |
| `hub_meeting_transcript_import_unavailable` | hub | No transcript came with this import. | reuse |
| `hub_meeting_transcript_importing` | hub | Still importing. Check back later | reuse |
| `hub_meeting_transcript_offline_reassurance` | hub | You're offline. Don't worry, we're still recording! | rewrite |
| `hub_meeting_transcript_otter_unavailable` | hub | No transcript came with this Otter export. | drop |
| `hub_meeting_transcript_postprocess_hint` | hub | After the meeting, Wispr will improve the transcript & label speakers | reuse |
| `hub_meeting_transcript_toggle_aria` | hub | Toggle transcript | reuse |
| `hub_meeting_transcript_toggle_tooltip` | hub | Toggle transcript | reuse |
| `hub_meeting_transcript_update_available_notice` | hub | New recording since this transcript. | reuse |
| `hub_mention_assign_aria` | hub | Assign name for {{label}} | reuse |
| `hub_mention_save_failed` | hub | Couldn’t save the name. Try again. | reuse |
| `hub_mention_typeahead_aria` | hub | Mention someone | reuse |
| `hub_mention_typeahead_no_matches` | hub | No matches — keep typing to leave as text | reuse |
| `hub_mention_typeahead_results_one` | hub | {{count}} person | reuse |
| `hub_mention_typeahead_results_other` | hub | {{count}} people | reuse |
| `hub_mention_typeahead_search_failed` | hub | Couldn’t search contacts right now | reuse |
| `hub_mention_typeahead_section_contacts` | hub | Contacts | reuse |
| `hub_mention_typeahead_section_meeting` | hub | In this meeting | reuse |
| `hub_mention_who_is_this` | hub | Who is this? | reuse |
| `hub_room_rename_failure` | hub | Couldn’t rename the room. Try again. | reuse |
| `hub_speaker_assignment_add_speaker` | hub | Add “{{name}}” as speaker | reuse |
| `hub_speaker_assignment_failure` | hub | Couldn’t update the speaker. Try again. | reuse |
| `hub_speaker_assignment_search_aria` | hub | Search people | reuse |
| `hub_speaker_assignment_search_placeholder` | hub | Search people | reuse |
| `hub_speaker_assignment_update_block` | hub | Update only this block | reuse |
| `hub_speaker_assignment_update_speaker` | hub | Update everywhere | reuse |
| `hub_speaker_grouping_add_to_room` | hub | Add to {{room}} | reuse |
| `hub_speaker_grouping_combine` | hub | Combine all voices | reuse |
| `hub_speaker_grouping_combine_description` | hub | Everyone becomes “{{room}}” | reuse |
| `hub_speaker_grouping_not_a_room` | hub | Not a room | reuse |
| `hub_speaker_grouping_not_in_room` | hub | Not in this room | reuse |
| `hub_speaker_grouping_room_voice_title` | hub | Who is {{voice}} in {{room}}? | reuse |
| `hub_speaker_grouping_separate` | hub | Separate | reuse |
| `hub_speaker_grouping_separate_voices_one` | hub | Separate {{count}} voice | reuse |
| `hub_speaker_grouping_separate_voices_other` | hub | Separate {{count}} voices | reuse |
| `hub_speaker_grouping_stale` | hub | This transcript was updated. Try again. | reuse |
| `hub_speaker_grouping_voice_count_one` | hub | {{count}} voice | reuse |
| `hub_speaker_grouping_voice_count_other` | hub | {{count}} voices | reuse |
| `hub_transcript_assign_speaker_names_tooltip` | hub | Assign speaker names | reuse |
| `hub_transcript_assign_speakers` | hub | Assign | reuse |
| `hub_transcript_copied` | hub | Copied transcript | reuse |
| `hub_transcript_delete_action` | hub | Delete | reuse |
| `hub_transcript_deleted` | hub | Deleted | reuse |
| `hub_transcript_edit_action` | hub | Edit transcript | reuse |
| `hub_transcript_edit_cancel` | hub | Cancel edit | reuse |
| `hub_transcript_edit_conflict_error` | hub | This line changed elsewhere. | reuse |
| `hub_transcript_edit_empty_error` | hub | Transcript can’t be empty. | reuse |
| `hub_transcript_edit_field_aria` | hub | Edit transcript | reuse |
| `hub_transcript_edit_retry` | hub | Try again | reuse |
| `hub_transcript_edit_save` | hub | Save edit | reuse |
| `hub_transcript_edit_save_error` | hub | Couldn’t save edit. | reuse |
| `hub_transcript_edit_saving` | hub | Saving edit… | reuse |
| `hub_transcript_edited` | hub | Edited | reuse |
| `hub_transcript_jump_to_bottom` | hub | Jump to bottom | reuse |
| `hub_transcript_label_speaker` | hub | Label Speaker | reuse |
| `hub_transcript_line_deleted` | hub | Line deleted | reuse |
| `hub_transcript_offline_gap` | hub | Offline for {{duration}} — audio was captured and will be transcribed after the meeting | rewrite |
| `hub_transcript_original` | hub | Original transcript | reuse |
| `hub_transcript_play_speaker_clip` | hub | Play audio | reuse |
| `hub_transcript_play_speaker_clip_aria` | hub | Play {{speaker}}’s voice | reuse |
| `hub_transcript_revert` | hub | Revert | reuse |
| `hub_transcript_scroll_region_aria` | hub | Meeting transcript | reuse |
| `hub_transcript_search_count` | hub | {{current}}/{{total}} | reuse |
| `hub_transcript_search_next_aria` | hub | Next match | reuse |
| `hub_transcript_search_prev_aria` | hub | Previous match | reuse |
| `hub_transcript_sleep_gap` | hub | Your device slept for {{duration}} | reuse |
| `hub_transcript_speaker_count_one` | hub | {{count}} speaker | reuse |
| `hub_transcript_speaker_count_other` | hub | {{count}} speakers | reuse |
| `hub_transcript_speaker_names_after_meeting_tooltip` | hub | We’ll add speaker names after the meeting | reuse |
| `hub_transcript_stop_speaker_clip` | hub | Stop audio | reuse |
| `hub_transcript_stop_speaker_clip_aria` | hub | Stop playing {{speaker}}’s voice | reuse |
| `hub_transcript_translation_action` | hub | Translate transcript | reuse |
| `hub_transcript_translation_active` | hub | Translating to {{language}} | reuse |
| `hub_transcript_translation_beta_badge` | hub | Beta | reuse |
| `hub_transcript_translation_fallback` | hub | Translation unavailable. Showing the original language. | reuse |
| `hub_transcript_translation_offline` | hub | Unavailable while the transcript is offline. | rewrite |
| `hub_transcript_translation_original` | hub | Original | reuse |
| `hub_transcript_translation_original_language` | hub | Original language | reuse |
| `hub_transcript_translation_row_description` | hub | Translated from {{language}}. Original available. | reuse |
| `hub_transcript_translation_row_description_unknown` | hub | Translated. Original available. | reuse |
| `hub_transcript_translation_search_placeholder` | hub | Translate to… | reuse |
| `hub_transcript_translation_switch_error` | hub | Couldn’t change the translation language. Try again. | reuse |
| `hub_transcript_translation_switch_language_notice` | hub | Changing translation language. Transcript is still being captured | reuse |
| `hub_transcript_translation_switch_off_notice` | hub | Turning off translation. Transcript is still being captured | reuse |
| `hub_transcript_translation_switch_on_notice` | hub | Enabling translation. Transcript is still being captured | reuse |
| `hub_transcript_translation_switching` | hub | Changing language… | reuse |
| `hub_transcript_undo_delete` | hub | Undo | reuse |

#### Summaries, summary templates, reports and feedback (107)

`hub_meeting_report_*` and `hub_note_report_*` send a problem report to the vendor; the rebuild has no server, so those rows are `rewrite` (save a local diagnostic or open an issue).

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_meeting_report_category_auto_stop` | hub | Auto-stop | rewrite |
| `hub_meeting_report_category_data_loss` | hub | Missing data or stuck processing | rewrite |
| `hub_meeting_report_category_label` | hub | Issue type | rewrite |
| `hub_meeting_report_category_notifications` | hub | Notifications | rewrite |
| `hub_meeting_report_category_other` | hub | Other | rewrite |
| `hub_meeting_report_category_placeholder` | hub | Select an issue type | rewrite |
| `hub_meeting_report_category_speaker_labeling` | hub | Speaker labels | rewrite |
| `hub_meeting_report_category_summary_quality` | hub | Summary quality | rewrite |
| `hub_meeting_report_dialog_default_title` | hub | This meeting | rewrite |
| `hub_meeting_report_dialog_feedback_label` | hub | What went wrong? | rewrite |
| `hub_meeting_report_dialog_ml_button` | hub | Send for ML training | drop |
| `hub_meeting_report_dialog_ml_copy` | hub | Sends the meeting audio, transcript, summary, and context to the ML team. | drop |
| `hub_meeting_report_dialog_ml_failed` | hub | Failed to send for ML training. Try again after processing finishes. | drop |
| `hub_meeting_report_dialog_ml_success` | hub | Sent for ML training | drop |
| `hub_meeting_report_dialog_ml_title` | hub | Send for ML training | drop |
| `hub_meeting_report_dialog_report_failed` | hub | Failed to send report | rewrite |
| `hub_meeting_report_dialog_submit` | hub | Send feedback | rewrite |
| `hub_meeting_report_dialog_success_copy` | hub | Thanks for the feedback! | rewrite |
| `hub_meeting_summary_copy_aria` | hub | Copy summary | reuse |
| `hub_meeting_summary_empty_hint` | hub | Summaries appear when a meeting ends | reuse |
| `hub_meeting_summary_generate_action` | hub | Generate summary | reuse |
| `hub_meeting_summary_granola_heading` | hub | Summary (Granola AI) | drop |
| `hub_meeting_summary_no_audio` | hub | No transcript or audio available for a summary | reuse |
| `hub_meeting_summary_not_auto_label` | hub | Not auto-generated | reuse |
| `hub_meeting_summary_otter_heading` | hub | Summary (Otter AI) | drop |
| `hub_meeting_summary_read_time` | hub | {{minutes}} min read | reuse |
| `hub_meeting_summary_recovered` | hub | Your unsaved summary is in Docs | reuse |
| `hub_meeting_summary_search_placeholder` | hub | Search summary… | reuse |
| `hub_meeting_summary_section_label` | hub | Enhanced Summary | reuse |
| `hub_meeting_summary_stale_notice` | hub | New audio since this summary. | reuse |
| `hub_meeting_summary_too_short` | hub | The meeting was too short to summarize. | reuse |
| `hub_meeting_summary_update_action` | hub | Update Summary | reuse |
| `hub_meeting_summary_update_available_notice` | hub | New recording since this summary. | reuse |
| `hub_meeting_summary_update_pending` | hub | Updating summary… | reuse |
| `hub_note_report_dialog_cancel` | hub | Cancel | rewrite |
| `hub_note_report_dialog_disclaimer` | hub | When you submit this form, Wispr will review this meeting data to diagnose issues and may use anonymized data from this meeting to improve our products. We won’t use this data for model training unless you’ve chosen to share your data for model improvement. | rewrite |
| `hub_note_report_dialog_placeholder` | hub | What went wrong? | rewrite |
| `hub_note_report_dialog_sent_title` | hub | Report sent! | rewrite |
| `hub_note_report_dialog_title_line` | hub | Report This Line From Your Note | rewrite |
| `hub_note_report_dialog_title_note` | hub | Report This Note | rewrite |
| `hub_notetaker_gen_audio_unavailable` | hub | The full recording is no longer available to retry. | reuse |
| `hub_notetaker_gen_done_title` | hub | Your notes are ready | reuse |
| `hub_notetaker_gen_error_recoverable` | hub | We hit a snag processing your meeting | reuse |
| `hub_notetaker_gen_error_unrecoverable` | hub | We couldn't process your meeting | reuse |
| `hub_notetaker_gen_initial_summarize_title` | hub | Finding the action items and decisions | reuse |
| `hub_notetaker_gen_initial_summarize_title_alt1` | hub | Turning the conversation into your next steps | reuse |
| `hub_notetaker_gen_initial_summarize_title_alt2` | hub | Pulling out what you’ll actually act on | reuse |
| `hub_notetaker_gen_initial_transcribe_title` | hub | Every word down, none of them typed by you | reuse |
| `hub_notetaker_gen_initial_transcribe_title_alt1` | hub | Getting every word that was said | reuse |
| `hub_notetaker_gen_initial_transcribe_title_alt2` | hub | Catching every word, so nothing slips | reuse |
| `hub_notetaker_gen_initial_transcribe_title_speakers_one` | hub | Getting every word {{count}} speaker said | reuse |
| `hub_notetaker_gen_initial_transcribe_title_speakers_other` | hub | Getting every word {{count}} speakers said | reuse |
| `hub_notetaker_gen_initial_transcribe_title_words_one` | hub | {{words}} word down, none of them typed by you | reuse |
| `hub_notetaker_gen_initial_transcribe_title_words_other` | hub | {{words}} words down, none of them typed by you | reuse |
| `hub_notetaker_gen_initial_upload_title` | hub | Turning your meeting into a two-minute read | reuse |
| `hub_notetaker_gen_initial_upload_title_alt1` | hub | So you never replay this meeting again | reuse |
| `hub_notetaker_gen_initial_upload_title_alt2` | hub | You can stop trying to hold it all in your head | reuse |
| `hub_notetaker_gen_initial_upload_title_duration_one` | hub | Turning your {{count}}-minute meeting into a two-minute read | reuse |
| `hub_notetaker_gen_initial_upload_title_duration_other` | hub | Turning your {{count}}-minute meeting into a two-minute read | reuse |
| `hub_notetaker_gen_rerun_summarize_title` | hub | Updating your notes | reuse |
| `hub_notetaker_gen_rerun_transcribe_title` | hub | Updating your transcript | reuse |
| `hub_notetaker_gen_rerun_upload_title` | hub | Uploading your new audio | rewrite |
| `hub_notetaker_gen_retry` | hub | Retry | reuse |
| `hub_notetaker_gen_retry_aria` | hub | Retry processing | reuse |
| `hub_notetaker_gen_status_running` | hub | {{title}}, step {{n}} of {{total}} | reuse |
| `hub_notetaker_gen_step_counter` | hub | step {{n}} of {{total}} | reuse |
| `hub_notetaker_gen_transcribe_done` | hub | Transcript ready | reuse |
| `hub_notetaker_gen_update_failed` | hub | Update failed. Showing the previous summary. | reuse |
| `hub_notetaker_gen_upload_done` | hub | Audio uploaded | rewrite |
| `hub_notetaker_gen_waiting_for_connection` | hub | Waiting for a connection | reuse |
| `hub_summary_celebration_duration` | hub | {{duration}} meeting compressed to a 2 min read. | reuse |
| `hub_summary_celebration_generic_1` | hub | We wrote everything down so you don’t have to | reuse |
| `hub_summary_celebration_generic_2` | hub | Your summary is ready! | reuse |
| `hub_summary_celebration_recap` | hub | That was {{duration}}. Here’s the short version. | reuse |
| `hub_summary_celebration_words_one` | hub | {{words}} word in. One page out. | reuse |
| `hub_summary_celebration_words_other` | hub | {{words}} words in. One page out. | reuse |
| `hub_summary_compare_editing_disabled` | hub | Editing will be enabled when a summary is selected | drop |
| `hub_summary_compare_heading` | hub | Which summary do you prefer? | drop |
| `hub_summary_compare_hint` | hub | Choose the version that best captures your meeting. The one you pick becomes this meeting's summary. | drop |
| `hub_summary_compare_internal` | hub | Internal preview | drop |
| `hub_summary_compare_label_1` | hub | Summary 1 | drop |
| `hub_summary_compare_label_2` | hub | Summary 2 | drop |
| `hub_summary_compare_prefer_1` | hub | Prefer 1 | drop |
| `hub_summary_compare_prefer_2` | hub | Prefer 2 | drop |
| `hub_summary_compare_saved_1` | hub | You preferred Summary 1. Your choice is saved. | drop |
| `hub_summary_compare_saved_2` | hub | You preferred Summary 2. Your choice is saved. | drop |
| `hub_summary_compare_saved_neither` | hub | You found neither summary good. Your choice is saved. | drop |
| `hub_summary_compare_saved_tie` | hub | You had no clear preference. Your choice is saved. | drop |
| `hub_summary_compare_switch` | hub | Show summary | drop |
| `hub_summary_compare_vote_neither` | hub | Neither is good | drop |
| `hub_summary_compare_vote_tie` | hub | No clear preference | drop |
| `hub_summary_copied` | hub | Copied summary | reuse |
| `hub_summary_feedback_dialog_cancel` | hub | Cancel | rewrite |
| `hub_summary_feedback_dialog_changed` | hub | The summary was updated. Close this and rate the new version. | rewrite |
| `hub_summary_feedback_dialog_disclosure_v1` | hub | Your feedback can be used to improve Wispr Flow. | rewrite |
| `hub_summary_feedback_dialog_failed` | hub | Couldn’t send your feedback. Try again. | rewrite |
| `hub_summary_feedback_dialog_learn_more` | hub | Learn more | rewrite |
| `hub_summary_feedback_dialog_placeholder` | hub | Add a note (optional) | rewrite |
| `hub_summary_feedback_dialog_rate_limited` | hub | You’re sending feedback too quickly. Try again in a minute. | rewrite |
| `hub_summary_feedback_dialog_remove` | hub | Remove rating | rewrite |
| `hub_summary_feedback_dialog_remove_earlier` | hub | Remove earlier rating | rewrite |
| `hub_summary_feedback_dialog_submit` | hub | Send feedback | rewrite |
| `hub_summary_feedback_dialog_title_down` | hub | What could be improved? | rewrite |
| `hub_summary_feedback_dialog_title_up` | hub | What did you like? | rewrite |
| `hub_summary_feedback_group_aria` | hub | Rate this summary | rewrite |
| `hub_summary_feedback_removed_status` | hub | Rating removed | rewrite |
| `hub_summary_feedback_sent_status` | hub | Feedback sent | rewrite |

#### My Tasks (action items) (91)

Sending tasks to Linear/Notion/Slack and task automations need cloud connectors; those rows are `rewrite` or `drop`.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_tasks_add_calendar_add` | hub | Add to calendar | reuse |
| `hub_tasks_add_calendar_adding` | hub | Adding… | reuse |
| `hub_tasks_add_calendar_attendees` | hub | Guests | reuse |
| `hub_tasks_add_calendar_close_aria` | hub | Close | reuse |
| `hub_tasks_add_calendar_description` | hub | Description | reuse |
| `hub_tasks_add_calendar_end` | hub | End | reuse |
| `hub_tasks_add_calendar_start` | hub | Start | reuse |
| `hub_tasks_add_calendar_title` | hub | Add to calendar | reuse |
| `hub_tasks_add_calendar_title_field` | hub | Title | reuse |
| `hub_tasks_add_calendar_toast_error` | hub | Couldn't add event. Try again. | reuse |
| `hub_tasks_add_calendar_toast_needs_reauth` | hub | Reconnect Google Automations to add events | rewrite |
| `hub_tasks_add_calendar_toast_not_connected` | hub | Connect Google Automations to add events | rewrite |
| `hub_tasks_add_calendar_toast_success` | hub | Event added to calendar | reuse |
| `hub_tasks_add_task` | hub | Add task | reuse |
| `hub_tasks_archive` | hub | Archive | reuse |
| `hub_tasks_archive_all` | hub | Archive all | reuse |
| `hub_tasks_archive_all_confirm_body_one` | hub | You can restore it any time from the Archived tab. | reuse |
| `hub_tasks_archive_all_confirm_body_other` | hub | You can restore them any time from the Archived tab. | reuse |
| `hub_tasks_archive_all_confirm_title_one` | hub | Archive {{count}} task in {{sectionLabel}}? | reuse |
| `hub_tasks_archive_all_confirm_title_other` | hub | Archive {{count}} tasks in {{sectionLabel}}? | reuse |
| `hub_tasks_archived_empty_body` | hub | Tasks you archive show up here. | reuse |
| `hub_tasks_archived_empty_title` | hub | Nothing archived | reuse |
| `hub_tasks_archived_loading` | hub | Loading archived tasks… | reuse |
| `hub_tasks_automation_add_calendar` | hub | Creates a calendar event | rewrite |
| `hub_tasks_automation_send_email` | hub | Drafts an email | rewrite |
| `hub_tasks_bulk_archive_one` | hub | Archive {{count}} task | reuse |
| `hub_tasks_bulk_archive_other` | hub | Archive {{count}} tasks | reuse |
| `hub_tasks_bulk_cancel` | hub | Cancel | reuse |
| `hub_tasks_bulk_delete_confirm_body_one` | hub | This permanently removes the selected task and can't be undone. | reuse |
| `hub_tasks_bulk_delete_confirm_body_other` | hub | This permanently removes the selected tasks and can't be undone. | reuse |
| `hub_tasks_bulk_delete_confirm_title_one` | hub | Delete {{count}} task? | reuse |
| `hub_tasks_bulk_delete_confirm_title_other` | hub | Delete {{count}} tasks? | reuse |
| `hub_tasks_bulk_delete_one` | hub | Delete {{count}} | reuse |
| `hub_tasks_bulk_delete_other` | hub | Delete {{count}} | reuse |
| `hub_tasks_bulk_restore_one` | hub | Restore {{count}} | reuse |
| `hub_tasks_bulk_restore_other` | hub | Restore {{count}} | reuse |
| `hub_tasks_bulk_toolbar_aria` | hub | Bulk actions | reuse |
| `hub_tasks_checkbox_aria` | hub | Change status of {{title}} | reuse |
| `hub_tasks_checkbox_aria_untitled` | hub | Change status of untitled task | reuse |
| `hub_tasks_coachmark_card_close` | hub | Dismiss | reuse |
| `hub_tasks_coachmark_card_cta` | hub | Check it out | reuse |
| `hub_tasks_coachmark_card_subtitle` | hub | View and complete the action items from your notes and meetings. | reuse |
| `hub_tasks_coachmark_card_title` | hub | Your tasks live here! | reuse |
| `hub_tasks_connect_apps` | hub | Connect to apps | rewrite |
| `hub_tasks_connect_apps_tooltip` | hub | Sync your tasks with all your favorite apps, coming in a few weeks | rewrite |
| `hub_tasks_date_last_week` | hub | Last week | reuse |
| `hub_tasks_date_older` | hub | Older | reuse |
| `hub_tasks_date_yesterday` | hub | Yesterday | reuse |
| `hub_tasks_empty_body` | hub | Action items from your meetings show up here. | reuse |
| `hub_tasks_empty_title` | hub | No tasks yet | reuse |
| `hub_tasks_from_meeting` | hub | From {{meetingName}} | reuse |
| `hub_tasks_new_aria` | hub | New task title | reuse |
| `hub_tasks_new_placeholder` | hub | New task | reuse |
| `hub_tasks_open_source_note` | hub | Open meeting note | reuse |
| `hub_tasks_priority_soon_body` | hub | Soon you'll be able to sort your tasks by priority. | reuse |
| `hub_tasks_priority_soon_title` | hub | Priority is coming soon | reuse |
| `hub_tasks_row_menu_aria` | hub | Task actions | reuse |
| `hub_tasks_search_aria` | hub | Search tasks | reuse |
| `hub_tasks_search_clear_aria` | hub | Clear search | reuse |
| `hub_tasks_search_close_aria` | hub | Close search | reuse |
| `hub_tasks_search_empty` | hub | No tasks match your search. | reuse |
| `hub_tasks_search_placeholder` | hub | Search tasks | reuse |
| `hub_tasks_send_email_body` | hub | Body | rewrite |
| `hub_tasks_send_email_close_aria` | hub | Close | rewrite |
| `hub_tasks_send_email_send` | hub | Send | rewrite |
| `hub_tasks_send_email_sending` | hub | Sending… | rewrite |
| `hub_tasks_send_email_subject` | hub | Subject | rewrite |
| `hub_tasks_send_email_title` | hub | Send email | rewrite |
| `hub_tasks_send_email_to` | hub | To | rewrite |
| `hub_tasks_send_email_toast_error` | hub | Couldn't send email. Try again. | rewrite |
| `hub_tasks_send_email_toast_needs_reauth` | hub | Reconnect Google Automations to send emails | rewrite |
| `hub_tasks_send_email_toast_not_connected` | hub | Connect Google Automations to send emails | rewrite |
| `hub_tasks_send_email_toast_success` | hub | Email sent | rewrite |
| `hub_tasks_tab_archived` | hub | Archived | reuse |
| `hub_tasks_tab_date` | hub | By date created | reuse |
| `hub_tasks_tab_priority` | hub | By priority | reuse |
| `hub_tasks_title` | hub | My Tasks | reuse |
| `hub_tasks_title_placeholder` | hub | Untitled task | reuse |
| `hub_tasks_toast_archived_one` | hub | Archived 1 task | reuse |
| `hub_tasks_toast_archived_other` | hub | Archived {{count}} tasks | reuse |
| `hub_tasks_toast_deleted_one` | hub | Deleted 1 task | reuse |
| `hub_tasks_toast_deleted_other` | hub | Deleted {{count}} tasks | reuse |
| `hub_tasks_toast_restored_one` | hub | Restored 1 task | reuse |
| `hub_tasks_toast_restored_other` | hub | Restored {{count}} tasks | reuse |
| `hub_tasks_toast_task_archived` | hub | Archived task | reuse |
| `hub_tasks_toast_task_deleted` | hub | Deleted task | reuse |
| `hub_tasks_toast_task_restored` | hub | Restored task | reuse |
| `hub_tasks_toast_undo` | hub | Undo | reuse |
| `hub_tasks_toast_undo_done` | hub | Undone | reuse |
| `hub_tasks_toc_aria` | hub | Section navigation | reuse |
| `hub_tasks_unarchive` | hub | Unarchive | reuse |

#### Meetings library, search, Notetaker home and home widget (225)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `hub_meetings_calendar_connect_body` | hub | See your schedule and join meetings in one click. | reuse |
| `hub_meetings_calendar_connect_button` | hub | Connect Google Calendar | rewrite |
| `hub_meetings_calendar_connect_title` | hub | Connect your calendar | reuse |
| `hub_meetings_calendar_disconnected_title` | hub | Calendar disconnected | reuse |
| `hub_meetings_calendar_reconnect_body` | hub | Reconnect to keep your schedule in sync. | rewrite |
| `hub_meetings_calendar_waiting_auth` | hub | Waiting for auth… | reuse |
| `hub_meetings_day_tomorrow` | hub | Tomorrow | reuse |
| `hub_meetings_delete_cancel` | hub | Cancel | reuse |
| `hub_meetings_delete_dialog_body` | hub | This will permanently delete the note and transcript. This action cannot be undone | reuse |
| `hub_meetings_delete_dialog_title` | hub | Delete meeting? | reuse |
| `hub_meetings_delete_failed` | hub | Couldn't delete the meeting. Please try again. | reuse |
| `hub_meetings_empty_state` | hub | No meetings found | reuse |
| `hub_meetings_past_delete_aria` | hub | Delete meeting | reuse |
| `hub_meetings_past_heading` | hub | Past meetings | reuse |
| `hub_meetings_past_import_chip_aria_granola` | hub | Imported from Granola | drop |
| `hub_meetings_past_import_chip_aria_otter` | hub | Imported from Otter | drop |
| `hub_meetings_past_length_aria` | hub | Length {{length}} | reuse |
| `hub_meetings_past_participants_aria_one` | hub | {{count}} participant | reuse |
| `hub_meetings_past_participants_aria_other` | hub | {{count}} participants | reuse |
| `hub_meetings_past_participants_label_one` | hub | {{count}} person | reuse |
| `hub_meetings_past_participants_label_other` | hub | {{count}} people | reuse |
| `hub_meetings_past_section_aria` | hub | Past notes | reuse |
| `hub_meetings_past_summary_placeholder` | hub | No summary yet | reuse |
| `hub_meetings_past_tasks_chip_aria` | hub | Tasks: {{done}} of {{total}} complete | reuse |
| `hub_meetings_past_time_date` | hub | {{date}} at {{time}} | reuse |
| `hub_meetings_past_time_today` | hub | Today at {{time}} | reuse |
| `hub_meetings_past_time_weekday` | hub | {{weekday}} at {{time}} | reuse |
| `hub_meetings_past_time_yesterday` | hub | Yesterday at {{time}} | reuse |
| `hub_meetings_preview_overview_label` | hub | Overview | reuse |
| `hub_meetings_record_toggle_dictating_aria` | hub | Dictating… | reuse |
| `hub_meetings_record_toggle_dictation_cancel_aria` | hub | Cancel dictation | reuse |
| `hub_meetings_record_toggle_dictation_cancel_tooltip` | hub | Cancel | reuse |
| `hub_meetings_record_toggle_dictation_stop_aria` | hub | Finish dictation | reuse |
| `hub_meetings_record_toggle_dictation_stop_tooltip` | hub | Finish and paste | reuse |
| `hub_meetings_record_toggle_finishing_label` | hub | Finishing up… | reuse |
| `hub_meetings_record_toggle_mic_unavailable_aria` | hub | Mic unavailable | reuse |
| `hub_meetings_record_toggle_mic_unavailable_toast` | hub | Microphone unavailable — stop and resume the meeting to retry. | reuse |
| `hub_meetings_record_toggle_resume_aria` | hub | Take notes | reuse |
| `hub_meetings_record_toggle_resume_label` | hub | Resume | reuse |
| `hub_meetings_record_toggle_start_label` | hub | Start | reuse |
| `hub_meetings_record_toggle_stop_aria` | hub | Stop listening | reuse |
| `hub_meetings_record_toggle_stop_label` | hub | Stop | reuse |
| `hub_meetings_search_no_results` | hub | No notes found for "{{query}}" | reuse |
| `hub_meetings_search_past_aria` | hub | Search past meetings | reuse |
| `hub_meetings_search_past_placeholder` | hub | Search past notes | reuse |
| `hub_meetings_search_placeholder` | hub | Search your meetings | reuse |
| `hub_meetings_title` | hub | Meetings | reuse |
| `hub_meetings_upcoming_empty_disconnected_body` | hub | Connect Google Calendar in Settings → Internal to see your schedule. | rewrite |
| `hub_meetings_upcoming_empty_disconnected_title` | hub | No upcoming meetings | reuse |
| `hub_meetings_upcoming_empty_done_title` | hub | There are no more meetings today or tomorrow | reuse |
| `hub_meetings_upcoming_heading` | hub | Upcoming | reuse |
| `hub_meetings_upcoming_now_badge` | hub | Now | reuse |
| `hub_meetings_upcoming_start_aria` | hub | Open Wispr for {{title}} | reuse |
| `hub_meetings_upcoming_start_button` | hub | Start | reuse |
| `hub_meetings_upcoming_untitled` | hub | Untitled note | reuse |
| `hub_notetaker_connect_app_banner_apps_body` | hub | Get briefs before meetings with context from different apps. | reuse |
| `hub_notetaker_connect_app_banner_apps_title` | hub | Prep for your next meeting | reuse |
| `hub_notetaker_connect_app_banner_calendar_body` | hub | Allow Wispr to name each speaker in your transcripts and summaries. | reuse |
| `hub_notetaker_connect_app_banner_calendar_cta` | hub | Connect calendar | reuse |
| `hub_notetaker_connect_app_banner_calendar_title` | hub | See who said what | reuse |
| `hub_notetaker_empty_cold_body` | hub | Add calendar for accurate speaker names and richer summaries on all meetings | reuse |
| `hub_notetaker_empty_disconnected_body` | hub | Wispr Flow will remind you to start Notetaker automatically | reuse |
| `hub_notetaker_empty_disconnected_connect` | hub | Connect calendar | reuse |
| `hub_notetaker_empty_disconnected_title` | hub | No meetings found | reuse |
| `hub_notetaker_empty_unavailable_body` | hub | We'll let you know when {{calendar}} becomes available. | reuse |
| `hub_notetaker_empty_unavailable_title` | hub | No meetings | reuse |
| `hub_notetaker_gap_free_from` | hub | Free from {{from}} to {{to}} | reuse |
| `hub_notetaker_hero_carousel_label` | hub | Notetaker preview | reuse |
| `hub_notetaker_hero_cta_connect_calendar` | hub | Connect calendar | reuse |
| `hub_notetaker_hero_cta_start_note` | hub | Start note | reuse |
| `hub_notetaker_hero_cta_try` | hub | Try Notetaker | reuse |
| `hub_notetaker_hero_go_to_slide` | hub | Go to slide {{n}} | reuse |
| `hub_notetaker_hero_label_briefings` | hub | Pre-meeting briefings | reuse |
| `hub_notetaker_hero_label_search` | hub | Search past notes and meetings | reuse |
| `hub_notetaker_hero_label_summaries` | hub | Enhanced summaries | reuse |
| `hub_notetaker_hero_label_transcripts` | hub | Live transcripts | reuse |
| `hub_notetaker_hero_loading` | hub | Loading Notetaker | reuse |
| `hub_notetaker_hero_preview_briefings_history_body` | hub | You last spoke to Scott on Apr 2, 2026. He wants to pitch Bond as your recruiting partner to help you hire AEs fast. Expect: scoping your needs, showing his client roster as proof, discussing terms. | reuse |
| `hub_notetaker_hero_preview_briefings_history_label` | hub | History | reuse |
| `hub_notetaker_hero_preview_briefings_join_bottom` | hub | & open {{name}} | reuse |
| `hub_notetaker_hero_preview_briefings_join_top` | hub | Join meeting | reuse |
| `hub_notetaker_hero_preview_briefings_meeting_time` | hub | 1:30 – 2:00pm | reuse |
| `hub_notetaker_hero_preview_briefings_meeting_title` | hub | Meeting with Scott Mullin (Bond) | reuse |
| `hub_notetaker_hero_preview_search_ask_anything` | hub | What did I miss? | reuse |
| `hub_notetaker_hero_preview_search_day_label` | hub | Today Jun 1 | reuse |
| `hub_notetaker_hero_preview_search_query` | hub | What did Katie say about onboarding? | reuse |
| `hub_notetaker_hero_preview_search_row1_time` | hub | 1:30pm • 40 min | reuse |
| `hub_notetaker_hero_preview_search_row1_title` | hub | iOS Release Bug Bash | reuse |
| `hub_notetaker_hero_preview_search_row2_time` | hub | 2:30pm • 30 min | reuse |
| `hub_notetaker_hero_preview_search_row2_title` | hub | Design Review | reuse |
| `hub_notetaker_hero_preview_summaries_action_item_1` | hub | Katie — Send updated Q3 design priorities by Friday. | reuse |
| `hub_notetaker_hero_preview_summaries_action_item_2` | hub | Abigail — Scope a real Meeting Hub implementation spec next. | reuse |
| `hub_notetaker_hero_preview_summaries_action_items_label` | hub | Action items | reuse |
| `hub_notetaker_hero_preview_summaries_note_title` | hub | 1:1 with Katie | reuse |
| `hub_notetaker_hero_preview_summaries_open_note` | hub | Open Note | reuse |
| `hub_notetaker_hero_preview_summaries_summary_body` | hub | Walked through Maya's recent work on the snippet picker | reuse |
| `hub_notetaker_hero_preview_summaries_summary_label` | hub | Summary | reuse |
| `hub_notetaker_hero_preview_transcripts_chat_tab` | hub | Chat | reuse |
| `hub_notetaker_hero_preview_transcripts_others` | hub | Others | reuse |
| `hub_notetaker_hero_preview_transcripts_others_message` | hub | Can do! | reuse |
| `hub_notetaker_hero_preview_transcripts_transcript_tab` | hub | Transcript | reuse |
| `hub_notetaker_hero_preview_transcripts_you` | hub | You | reuse |
| `hub_notetaker_hero_preview_transcripts_you_message` | hub | Can you schedule this for me? | reuse |
| `hub_notetaker_hero_subtitle` | hub | Transcript, summary, and action items for every meeting | reuse |
| `hub_notetaker_hero_title` | hub | Take Notetaker for a test run | reuse |
| `hub_notetaker_jump_to_today_aria` | hub | Jump to Today | reuse |
| `hub_notetaker_loading_note_aria` | hub | Loading note | reuse |
| `hub_notetaker_meeting_controls_auto_share` | hub | Auto-share | drop |
| `hub_notetaker_meeting_controls_auto_share_all` | hub | All attendees | drop |
| `hub_notetaker_meeting_controls_auto_share_description` | hub | Auto-share this meeting's notes with the following group | drop |
| `hub_notetaker_meeting_controls_auto_share_description_short` | hub | Share notes with attendees | drop |
| `hub_notetaker_meeting_controls_auto_share_domain` | hub | @{{domain}} | drop |
| `hub_notetaker_meeting_controls_auto_share_off` | hub | No one | drop |
| `hub_notetaker_meeting_controls_calendar_notice` | hub | Calendar | reuse |
| `hub_notetaker_meeting_controls_calendar_notice_description` | hub | Mention you're taking notes with Wispr Flow in this event's description. Optionally include the notes link. | rewrite |
| `hub_notetaker_meeting_controls_calendar_notice_notice_and_link` | hub | Include link | rewrite |
| `hub_notetaker_meeting_controls_calendar_notice_notice_only` | hub | Notice only | reuse |
| `hub_notetaker_meeting_controls_calendar_notice_off` | hub | Off | reuse |
| `hub_notetaker_meeting_controls_calendar_notice_unavailable_organizer` | hub | Calendar notice is only available for events you organize | reuse |
| `hub_notetaker_meeting_controls_calendar_notice_unavailable_provider` | hub | Calendar notice only works with Google Calendar for now | rewrite |
| `hub_notetaker_meeting_controls_calendar_notice_unavailable_started` | hub | Calendar notice can't be changed after the meeting starts | reuse |
| `hub_notetaker_meeting_controls_error_ended` | hub | This meeting has already ended | reuse |
| `hub_notetaker_meeting_controls_error_failed` | hub | Couldn't update this meeting. Try again. | reuse |
| `hub_notetaker_meeting_controls_error_no_domain` | hub | Sharing with your domain isn't available for this account | rewrite |
| `hub_notetaker_meeting_controls_settings_link` | hub | Change default settings | reuse |
| `hub_notetaker_meeting_controls_trigger_aria` | hub | Meeting options | reuse |
| `hub_notetaker_meeting_status_auto_share_all` | hub | Notes will be shared with all attendees | drop |
| `hub_notetaker_meeting_status_auto_share_domain` | hub | Notes will be shared with @{{domain}} attendees | drop |
| `hub_notetaker_meeting_status_calendar_notice` | hub | Calendar notice is on | reuse |
| `hub_notetaker_meeting_status_calendar_notice_link` | hub | Calendar notice with notes link is on | rewrite |
| `hub_notetaker_more_join_options_aria` | hub | More join options | reuse |
| `hub_notetaker_next_page_aria` | hub | Next page | reuse |
| `hub_notetaker_notes_loading_aria` | hub | Loading your notes | reuse |
| `hub_notetaker_notes_tab_folders` | hub | Folders | reuse |
| `hub_notetaker_notes_tab_my` | hub | My notes | reuse |
| `hub_notetaker_notes_tab_my_past` | hub | Past notes | reuse |
| `hub_notetaker_notes_tab_shared` | hub | Shared with me | rewrite |
| `hub_notetaker_open_live_note_aria` | hub | Open live meeting note | reuse |
| `hub_notetaker_open_note` | hub | Open Note | reuse |
| `hub_notetaker_open_settings_tooltip` | hub | Open Notetaker settings | reuse |
| `hub_notetaker_previous_page_aria` | hub | Previous page | reuse |
| `hub_notetaker_retention_banner_action_go_to_notetaker` | hub | Go to Notetaker | drop |
| `hub_notetaker_retention_banner_body` | hub | Your admin has set Notetaker transcript retention to {{duration}}. Transcripts older than {{duration}} will be deleted within 24 hours | drop |
| `hub_notetaker_retention_banner_dismiss_aria` | hub | Dismiss | drop |
| `hub_notetaker_retention_banner_title` | hub | 24 hours before transcript removal | drop |
| `hub_notetaker_search_ask_about` | hub | Ask Wispr about "{{query}}" | reuse |
| `hub_notetaker_search_attendee_label` | hub | Attendee | reuse |
| `hub_notetaker_search_date_any` | hub | Any time | reuse |
| `hub_notetaker_search_date_last30` | hub | Last 30 days | reuse |
| `hub_notetaker_search_date_last7` | hub | Last 7 days | reuse |
| `hub_notetaker_search_date_menu_aria` | hub | Filter by date | reuse |
| `hub_notetaker_search_date_today` | hub | Today | reuse |
| `hub_notetaker_search_dialog_aria` | hub | Search meetings | reuse |
| `hub_notetaker_search_filter_by_attendee` | hub | Filter by attendee | reuse |
| `hub_notetaker_search_filter_by_attendee_selected` | hub | Filter by attendee: {{names}} | reuse |
| `hub_notetaker_search_filter_by_folder_selected` | hub | Folder: {{name}} | reuse |
| `hub_notetaker_search_filters_aria` | hub | Search filters | reuse |
| `hub_notetaker_search_folder_empty_body` | hub | Add notes to {{name}} from a note’s menu | reuse |
| `hub_notetaker_search_folder_empty_title` | hub | No notes in this folder yet | reuse |
| `hub_notetaker_search_folder_label` | hub | Folder | reuse |
| `hub_notetaker_search_folder_menu_aria` | hub | Filter by folder | reuse |
| `hub_notetaker_search_folder_section` | hub | Notes in {{name}} | reuse |
| `hub_notetaker_search_input_aria` | hub | Search meetings | reuse |
| `hub_notetaker_search_loading_more` | hub | Loading more… | reuse |
| `hub_notetaker_search_no_match_hint` | hub | Try a different search or ask wispr | reuse |
| `hub_notetaker_search_no_match_query` | hub | No match found | reuse |
| `hub_notetaker_search_no_notes_yet_body` | hub | Notes from your meetings will show up here | reuse |
| `hub_notetaker_search_no_notes_yet_title` | hub | No notes yet | reuse |
| `hub_notetaker_search_notes_section` | hub | Notes | reuse |
| `hub_notetaker_search_placeholder` | hub | Search personal or shared notes... | rewrite |
| `hub_notetaker_search_recent_notes` | hub | Recent notes | reuse |
| `hub_notetaker_search_source_all` | hub | All | reuse |
| `hub_notetaker_search_source_menu_aria` | hub | Filter by source | reuse |
| `hub_notetaker_search_source_mine` | hub | Mine | reuse |
| `hub_notetaker_search_source_shared` | hub | Shared | rewrite |
| `hub_notetaker_search_untitled` | hub | Untitled meeting | reuse |
| `hub_notetaker_search_warning_invalid_request` | hub | That search didn't have any searchable words | reuse |
| `hub_notetaker_search_warning_invalid_time_range` | hub | That date range couldn't be applied | reuse |
| `hub_notetaker_search_warning_limit_capped` | hub | Results were limited — try a more specific search | reuse |
| `hub_notetaker_search_warning_scan_capped` | hub | Some older notes weren't scanned yet | reuse |
| `hub_notetaker_search_warning_search_failed` | hub | Search isn't available right now. Try again in a moment | reuse |
| `hub_notetaker_show_less_meetings` | hub | Show less | reuse |
| `hub_notetaker_show_more_button` | hub | Show more | reuse |
| `hub_notetaker_show_more_meetings` | hub | Show {{count}} more | reuse |
| `hub_notetaker_start_tutorial` | hub | Start tutorial | reuse |
| `hub_notetaker_today_empty_done_title` | hub | Done for the day! 🎉 | reuse |
| `hub_notetaker_today_empty_no_meetings_title` | hub | No meetings today | reuse |
| `hub_notetaker_today_wrapup_v01_one` | hub | {{count}} meeting finished today. Great job! | reuse |
| `hub_notetaker_today_wrapup_v01_other` | hub | {{count}} meetings finished today. Great job! | reuse |
| `hub_notetaker_today_wrapup_v02` | hub | All done for today! {{timeCaptured}} of conversations, captured. | reuse |
| `hub_notetaker_today_wrapup_v03_one` | hub | {{count}} meeting finished today. You crushed it! | reuse |
| `hub_notetaker_today_wrapup_v03_other` | hub | {{count}} meetings finished today. You crushed it! | reuse |
| `hub_notetaker_today_wrapup_v04` | hub | Nice work! {{timeCaptured}} of meeting notes finished. | reuse |
| `hub_notetaker_today_wrapup_v05_one` | hub | You did it: {{count}} meeting, all captured. | reuse |
| `hub_notetaker_today_wrapup_v05_other` | hub | You did it: {{count}} meetings, all captured. | reuse |
| `hub_notetaker_today_wrapup_v06_one` | hub | {{count}} meeting down. You're done for the day! | reuse |
| `hub_notetaker_today_wrapup_v06_other` | hub | {{count}} meetings down. You're done for the day! | reuse |
| `hub_notetaker_today_wrapup_v07_one` | hub | You handled {{count}} meeting today. Nicely done. | reuse |
| `hub_notetaker_today_wrapup_v07_other` | hub | You handled {{count}} meetings today. Nicely done. | reuse |
| `hub_notetaker_today_wrapup_v08_one` | hub | {{count}} meeting later, and you’re all wrapped up! | reuse |
| `hub_notetaker_today_wrapup_v08_other` | hub | {{count}} meetings later, and you’re all wrapped up! | reuse |
| `hub_notetaker_today_wrapup_v09_one` | hub | Woohoo! {{count}} meeting finished today. | reuse |
| `hub_notetaker_today_wrapup_v09_other` | hub | Woohoo! {{count}} meetings finished today. | reuse |
| `hub_notetaker_today_wrapup_v10` | hub | All done! You captured {{timeCaptured}} of notes today. | reuse |
| `hub_notetaker_today_wrapup_v11_one` | hub | {{count}} meeting wrapped up today. Well done! | reuse |
| `hub_notetaker_today_wrapup_v11_other` | hub | {{count}} meetings wrapped up today. Well done! | reuse |
| `hub_notetaker_today_wrapup_v12_one` | hub | You crushed {{count}} meeting today! | reuse |
| `hub_notetaker_today_wrapup_v12_other` | hub | You crushed {{count}} meetings today! | reuse |
| `hub_notetaker_today_wrapup_v13` | hub | Done for today! {{timeCaptured}} of notes, captured. | reuse |
| `hub_notetaker_today_wrapup_v14` | hub | All done! You made {{timeCaptured}} of notetaking look easy. | reuse |
| `hub_notetaker_today_wrapup_v15_one` | hub | All wrapped up! {{count}} meeting and {{timeCaptured}} captured. | reuse |
| `hub_notetaker_today_wrapup_v15_other` | hub | All wrapped up! {{count}} meetings and {{timeCaptured}} captured. | reuse |
| `hub_notetaker_today_wrapup_v16_one` | hub | Done for today! You talked to {{peopleCount}} people across {{count}} meeting. | reuse |
| `hub_notetaker_today_wrapup_v16_other` | hub | Done for today! You talked to {{peopleCount}} people across {{count}} meetings. | reuse |
| `hub_notetaker_up_next` | hub | Up Next | reuse |
| `hub_notetaker_upcoming_conflict` | hub | Conflict | reuse |
| `hub_notetaker_upcoming_declined` | hub | Declined | reuse |
| `hub_notetaker_upcoming_maybe` | hub | Maybe | reuse |
| `hub_notetaker_upcoming_meetings_section_label` | hub | Upcoming meetings | reuse |
| `hub_notetaker_upcoming_today_personal` | hub | {{name}}'s day | reuse |
| `hub_notetaker_weekly_limit_reached_title` | hub | No meeting notes left this week | drop |
| `hub_notetaker_weekly_limit_reset` | hub | Resets {{resetDate}} | drop |
| `hub_notetaker_weekly_limit_upgrade` | hub | Upgrade | drop |
| `hub_notetaker_weekly_limit_warning_title_one` | hub | Only {{count}} note left this week | drop |
| `hub_notetaker_weekly_limit_warning_title_other` | hub | Only {{count}} notes left this week | drop |

#### Folders (local organisation in the rebuild) (128)

Folders become local collections. Grants, members, sharing, leaving and access rows are `drop`.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `folder_access_through` | hub | You have access through {{name}}. | drop |
| `folder_access_through_company` | hub | You have access because this folder is shared with your company. | drop |
| `folder_access_through_department` | hub | You have access because this folder is shared with your department. | drop |
| `folder_action_delete` | hub | Delete | reuse |
| `folder_action_delete_folder` | hub | Delete folder | reuse |
| `folder_action_edit` | hub | Edit | reuse |
| `folder_action_leave` | hub | Leave folder | drop |
| `folder_action_view` | hub | View | reuse |
| `folder_add_meeting_failed` | hub | Couldn’t add this note to the folder. Try again. | reuse |
| `folder_chip_blocked_member_hint` | hub | {{name}}. Sharing is turned off by the folder owner’s admin. | drop |
| `folder_chip_blocked_owner_hint` | hub | {{name}}. Sharing is turned off by your admin. | drop |
| `folder_chip_edit_label` | hub | Change folders ({{name}}) | reuse |
| `folder_chip_open_label` | hub | Open folder: {{name}} | reuse |
| `folder_chip_view_label` | hub | View folders ({{name}}) | reuse |
| `folder_delete_confirm_body` | hub | Only the folder is deleted. Your notes stay in your library. | reuse |
| `folder_delete_confirm_body_shared` | hub | Only the folder is deleted. Your notes stay in your library. Members lose access to notes they could see only through this folder, and so do you. | reuse |
| `folder_delete_confirm_title` | hub | Delete the folder “{{name}}”? | reuse |
| `folder_delete_failed` | hub | Couldn’t delete the folder. Try again. | reuse |
| `folder_detail_add` | hub | Add folder | reuse |
| `folder_detail_description_heading` | hub | Description | reuse |
| `folder_detail_members_load_failed` | hub | Couldn’t load who this folder is shared with. | drop |
| `folder_detail_note_count_one` | hub | {{count}} note | reuse |
| `folder_detail_note_count_other` | hub | {{count}} notes | reuse |
| `folder_detail_only_you` | hub | Only you | reuse |
| `folder_detail_owner_heading` | hub | Owner | reuse |
| `folder_detail_owner_unnamed` | hub | Unnamed owner | reuse |
| `folder_detail_people_heading` | hub | People | reuse |
| `folder_detail_region_aria` | hub | Folder details | reuse |
| `folder_detail_shared_with_heading` | hub | Shared with | drop |
| `folder_empty_action` | hub | Create folder | reuse |
| `folder_empty_body` | hub | Organize your notes | reuse |
| `folder_empty_title` | hub | No folders | reuse |
| `folder_error_cloud_sync` | hub | Folders need Cloud Sync turned on for your organization. | rewrite |
| `folder_error_unavailable` | hub | Folders aren’t available on your account. | rewrite |
| `folder_grant_add_failed` | hub | Couldn’t share the folder. Try again. | drop |
| `folder_grant_company_caption` | hub | Company | drop |
| `folder_grant_company_caption_count_one` | hub | Company · {{count}} person | drop |
| `folder_grant_company_caption_count_other` | hub | Company · {{count}} people | drop |
| `folder_grant_company_confirm_action` | hub | Add | drop |
| `folder_grant_company_confirm_body_one` | hub | {{count}} person at {{company}}, and anyone who joins later, will be able to see and add notes in this folder. | drop |
| `folder_grant_company_confirm_body_other` | hub | {{count}} people at {{company}}, and anyone who joins later, will be able to see and add notes in this folder. | drop |
| `folder_grant_company_confirm_title` | hub | Share with everyone at {{company}}? | drop |
| `folder_grant_department_caption` | hub | Department | drop |
| `folder_grant_department_caption_count_one` | hub | Department · {{count}} person | drop |
| `folder_grant_department_caption_count_other` | hub | Department · {{count}} people | drop |
| `folder_grant_everyone` | hub | Everyone at {{company}} | drop |
| `folder_grant_inactive_caption` | hub | Department no longer exists | drop |
| `folder_grant_load_failed` | hub | Couldn’t load departments. | drop |
| `folder_grant_not_allowed` | hub | Your organization doesn’t allow sharing with departments or the whole company. | drop |
| `folder_grant_not_eligible` | hub | Your organization doesn’t allow sharing this folder. | drop |
| `folder_grant_people_count_one` | hub | {{count}} person | drop |
| `folder_grant_people_count_other` | hub | {{count}} people | drop |
| `folder_grant_remove_confirm_action` | hub | Stop sharing | drop |
| `folder_grant_remove_confirm_body` | hub | They lose access to this folder. Notes they already added stay in it. | drop |
| `folder_grant_remove_confirm_title` | hub | Stop sharing with {{name}}? | drop |
| `folder_grant_remove_confirm_title_company` | hub | Stop sharing with everyone at {{company}}? | drop |
| `folder_grant_remove_failed` | hub | Couldn’t stop sharing. Try again. | drop |
| `folder_grant_remove_label` | hub | Stop sharing with {{name}} | drop |
| `folder_leave_dialog_body` | hub | You’ll lose access to the notes shared through this folder. | drop |
| `folder_leave_dialog_title` | hub | Leave “{{name}}”? | drop |
| `folder_leave_failed` | hub | Couldn’t leave the folder. Try again. | drop |
| `folder_member_add_failed` | hub | Couldn’t add people. Try again. | drop |
| `folder_member_already_member` | hub | Already in this folder: {{emails}} | drop |
| `folder_member_invalid` | hub | Not a valid email address: {{emails}} | drop |
| `folder_member_no_account` | hub | No Wispr account yet: {{emails}} | drop |
| `folder_member_not_eligible` | hub | Can’t be added to this folder: {{emails}} | drop |
| `folder_member_own_address` | hub | You own this folder, so you’re already in it. | drop |
| `folder_member_remove_confirm_action` | hub | Remove | drop |
| `folder_member_remove_confirm_body` | hub | Their notes leave this folder. | drop |
| `folder_member_remove_confirm_title` | hub | Remove {{name}}? | drop |
| `folder_member_remove_confirm_title_anon` | hub | Remove this person? | drop |
| `folder_members_load_failed` | hub | Couldn’t load members. Close and try again. | drop |
| `folder_members_remove_failed` | hub | Couldn’t remove that person. Try again. | drop |
| `folder_members_too_many` | hub | Remove some addresses. You can add up to {{max}} people at a time. | drop |
| `folder_modal_cancel` | hub | Cancel | reuse |
| `folder_modal_close` | hub | Close | reuse |
| `folder_modal_create` | hub | Create | reuse |
| `folder_modal_create_failed` | hub | Couldn’t create the folder. Try again. | reuse |
| `folder_modal_create_title` | hub | Create folder | reuse |
| `folder_modal_description_help` | hub | Helps Wispr automatically suggest when to use this folder | reuse |
| `folder_modal_description_label` | hub | Description | reuse |
| `folder_modal_edit_title` | hub | Edit folder | reuse |
| `folder_modal_name_label` | hub | Name | reuse |
| `folder_modal_name_placeholder` | hub | Folder name | reuse |
| `folder_modal_save` | hub | Save | reuse |
| `folder_modal_save_failed` | hub | Couldn’t save the folder. Try again. | reuse |
| `folder_modal_view_title` | hub | Folder details | reuse |
| `folder_picker_create_new` | hub | Create new folder | reuse |
| `folder_picker_empty` | hub | No folders yet. | reuse |
| `folder_picker_group_personal` | hub | Personal folders | reuse |
| `folder_picker_group_shared` | hub | Shared folders | rewrite |
| `folder_picker_heading_private` | hub | Private | reuse |
| `folder_picker_heading_shared` | hub | Shared | rewrite |
| `folder_picker_load_failed` | hub | Couldn’t load your folders. Try again. | reuse |
| `folder_picker_no_matches` | hub | No folders match that name. | reuse |
| `folder_picker_search_label` | hub | Search folders | reuse |
| `folder_picker_search_placeholder` | hub | Search folders | reuse |
| `folder_picker_title` | hub | Add to folder | reuse |
| `folder_picker_title_shared` | hub | Folders for this note | reuse |
| `folder_remove_copy_of` | hub | Remove {{name}}’s copy from folder | reuse |
| `folder_remove_meeting_failed` | hub | Couldn’t remove this note from the folder. Try again. | reuse |
| `folder_remove_note` | hub | Remove from folder | reuse |
| `folder_remove_your_copy` | hub | Remove your copy from folder | reuse |
| `folder_row_chip_create` | hub | Create folder | reuse |
| `folder_row_locked_aria` | hub | {{name}}, shared with you. Only the folder owner can remove this note. | drop |
| `folder_row_meeting_count_one` | hub | {{count}} meeting | reuse |
| `folder_row_meeting_count_other` | hub | {{count}} meetings | reuse |
| `folder_row_menu_add` | hub | Add to folder | reuse |
| `folder_row_menu_aria` | hub | Folder options for {{name}} | reuse |
| `folder_row_shared_aria` | hub | {{name}}, shared with you | drop |
| `folder_row_shared_tooltip` | hub | Shared with you | drop |
| `folder_rule_add_failed` | hub | Couldn’t add this meeting to the folder. Try again. | drop |
| `folder_rule_remove_failed` | hub | Couldn’t remove this meeting from the folder. Try again. | drop |
| `folder_share_section_company` | hub | Company | drop |
| `folder_share_section_departments` | hub | Departments | drop |
| `folder_share_section_people` | hub | People | drop |
| `folder_sharing_blocked_member` | hub | Sharing is turned off by the folder owner’s admin. You can’t file notes here or see the owner’s notes right now. | drop |
| `folder_sharing_blocked_owner` | hub | Sharing is turned off by your admin. People stay in this folder, but they can’t see your notes here right now, and you can’t add anyone. | drop |
| `folder_sharing_blocked_short` | hub | Sharing is turned off by the folder owner’s admin | drop |
| `folder_sharing_heading` | hub | Sharing | drop |
| `folder_versions_count_one` | hub | {{count}} copy | reuse |
| `folder_versions_count_other` | hub | {{count}} copies | reuse |
| `folder_versions_dialog_description` | hub | More than one person added this meeting. Choose the copy to open. | reuse |
| `folder_versions_in_folders` | hub | In {{folders}} | reuse |
| `folder_versions_title` | hub | Versions | reuse |
| `folder_view_empty` | hub | No notes in this folder yet. | reuse |
| `folder_view_owned_by` | hub | Owned by {{name}} | reuse |
| `folder_view_owned_by_you` | hub | Owned by {{name}} (you) | reuse |

#### Calendar (EventKit in the rebuild) (49)

Flow connects Google and Outlook calendars over OAuth. The rebuild reads the system calendars with EventKit, so rows that name a provider, a browser or sign-in are `rewrite`.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_connectors_description_calendar` | set | Accurate reminders for Google meetings before they begin | rewrite |
| `settings_connectors_disconnect_subtitle_calendar` | set | Wispr Flow will stop using Google Calendar for reminders, meeting context, and briefs. You can reconnect anytime. | rewrite |
| `calendar_connect_waiting_modal_benefit_recordings` | hub | Start notes for scheduled meetings | reuse |
| `calendar_connect_waiting_modal_benefit_reminders` | hub | Never be late to a meeting | reuse |
| `calendar_connect_waiting_modal_benefit_titles` | hub | Improve notes with meeting title and participant names | reuse |
| `calendar_connect_waiting_modal_close` | hub | Close | reuse |
| `calendar_connect_waiting_modal_coming_soon_icloud` | hub | iCloud (coming soon) | rewrite |
| `calendar_connect_waiting_modal_coming_soon_outlook` | hub | Outlook (coming soon) | rewrite |
| `calendar_connect_waiting_modal_connect_error` | hub | Something went wrong starting the connection. Please try again. | reuse |
| `calendar_connect_waiting_modal_continue_google` | hub | Continue with Google | rewrite |
| `calendar_connect_waiting_modal_continue_outlook` | hub | Continue with Outlook | rewrite |
| `calendar_connect_waiting_modal_done` | hub | Done | reuse |
| `calendar_connect_waiting_modal_failed` | hub | We couldn’t finish connecting. Try again. | reuse |
| `calendar_connect_waiting_modal_preview_meeting_title` | hub | Katie & Manvi 1:1 | reuse |
| `calendar_connect_waiting_modal_provider_title` | hub | Connect your calendar | reuse |
| `calendar_connect_waiting_modal_subtitle` | hub | Quickly join meetings and start transcribing. | reuse |
| `calendar_connect_waiting_modal_success` | hub | Google Calendar connected | rewrite |
| `calendar_connect_waiting_modal_success_outlook` | hub | Outlook Calendar connected | rewrite |
| `calendar_connect_waiting_modal_success_subtitle` | hub | You’re all set! We will remind you before each meeting, with one click to join and start Notetaker. | reuse |
| `calendar_connect_waiting_modal_title` | hub | Connect Google Calendar to… | rewrite |
| `calendar_incomplete_permissions_modal_body` | hub | Your calendar didn’t finish connecting. Click “Select all” to see upcoming meetings, get reminders, and improved notes. | reuse |
| `calendar_incomplete_permissions_modal_body_outlook` | hub | Your calendar didn’t finish connecting. Allow calendar access on Microsoft’s permission screen to see upcoming meetings, get reminders, and improved notes. | rewrite |
| `calendar_incomplete_permissions_modal_close_aria` | hub | Dismiss | reuse |
| `calendar_incomplete_permissions_modal_connect_error` | hub | Couldn't open the browser. Please try again. | rewrite |
| `calendar_incomplete_permissions_modal_continue` | hub | Continue | reuse |
| `calendar_incomplete_permissions_modal_title` | hub | Finish connecting Google Calendar | rewrite |
| `calendar_incomplete_permissions_modal_title_outlook` | hub | Finish connecting Outlook Calendar | rewrite |
| `outlook_calendar_recovery_ask_admin_body` | hub | Your organization needs to approve {{provider}} before you can connect it. | rewrite |
| `outlook_calendar_recovery_ask_admin_title` | hub | Ask your admin | rewrite |
| `outlook_calendar_recovery_disconnect_account_title` | hub | Disconnect {{account}} first | rewrite |
| `outlook_calendar_recovery_disconnect_body` | hub | Open Connectors in Settings to manage the connected account. | rewrite |
| `outlook_calendar_recovery_disconnect_current_title` | hub | Disconnect your current {{provider}} account first | rewrite |
| `outlook_calendar_recovery_finish_action` | hub | Finish connecting | reuse |
| `outlook_calendar_recovery_finish_google_body` | hub | Click “Select all” on Google’s permission screen, then try again. | rewrite |
| `outlook_calendar_recovery_finish_outlook_body` | hub | Review the requested Microsoft permissions, then try again. | rewrite |
| `outlook_calendar_recovery_finish_title` | hub | Finish connecting | reuse |
| `outlook_calendar_recovery_google_provider` | hub | Google Calendar | rewrite |
| `outlook_calendar_recovery_open_settings_action` | hub | Open Settings | reuse |
| `outlook_calendar_recovery_outlook_provider` | hub | Outlook Calendar | rewrite |
| `outlook_calendar_recovery_reconnect_action` | hub | Reconnect | reuse |
| `outlook_calendar_recovery_reconnect_body` | hub | Reconnect {{provider}} to keep your calendar in sync. | reuse |
| `outlook_calendar_recovery_reconnect_title` | hub | Reconnect your calendar | reuse |
| `outlook_calendar_recovery_try_again_action` | hub | Try again | reuse |
| `outlook_calendar_recovery_try_again_body` | hub | We couldn’t connect {{provider}}. Try again. | reuse |
| `outlook_calendar_recovery_try_again_title` | hub | Try again | reuse |
| `outlook_calendar_recovery_unavailable_body` | hub | This Microsoft account doesn’t have an Outlook mailbox available. | rewrite |
| `outlook_calendar_recovery_unavailable_title` | hub | This account can’t be connected | rewrite |
| `outlook_launch_modal_body` | hub | Connect your Outlook calendar to quickly join meetings and start transcribing. | rewrite |
| `outlook_launch_modal_title` | hub | Outlook for Notetaker! | rewrite |

#### Notetaker notifications and toasts (detection, recording, check-ins, audio, consent) (149)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `conference_switch_offer_action_keep` | ntf | Keep recording | reuse |
| `conference_switch_offer_action_switch` | ntf | Switch | reuse |
| `conference_switch_offer_title` | ntf | Looks like a new meeting. Switch? | reuse |
| `first_meeting_complete_with_incoming_summary_action_done` | ntf | Done | reuse |
| `first_meeting_complete_with_incoming_summary_action_got_it` | ntf | Got it | reuse |
| `first_meeting_complete_with_incoming_summary_body` | ntf | It will take ~2 minutes to clean up your transcript, identify speakers, and generate your summary. | reuse |
| `first_meeting_complete_with_incoming_summary_title` | ntf | Meeting complete! Your summary will be ready shortly | reuse |
| `first_meeting_complete_with_incoming_summary_title_auto_open` | ntf | Meeting complete! We'll open your summary shortly | reuse |
| `long_dictation_notetaker_prompt_action_explore` | ntf | Explore Notetaker | reuse |
| `long_dictation_notetaker_prompt_action_learn_more` | ntf | Learn more | reuse |
| `long_dictation_notetaker_prompt_action_try` | ntf | Try Notetaker | reuse |
| `long_dictation_notetaker_prompt_body_if_recording` | ntf | If you were recording, Notetaker can transcribe it and take notes. | reuse |
| `long_dictation_notetaker_prompt_body_next_time` | ntf | Next time, try Notetaker for a transcript and notes. | reuse |
| `long_dictation_notetaker_prompt_body_what_was_said` | ntf | Notetaker can transcribe what was said and write up notes. | reuse |
| `long_dictation_notetaker_prompt_title_long_one` | ntf | That was a long one! | reuse |
| `long_dictation_notetaker_prompt_title_recording` | ntf | Were you recording something? | reuse |
| `meeting_auto_ended_action_resume` | ntf | Resume | reuse |
| `meeting_auto_ended_title` | ntf | Notetaker stopped | reuse |
| `meeting_auto_ended_title_sleep` | ntf | Notetaker stopped when your Mac went to sleep | reuse |
| `meeting_detection_re_enable_prompt_action_not_now` | ntf | Not now | reuse |
| `meeting_detection_re_enable_prompt_action_yes` | ntf | Yes, remind me | reuse |
| `meeting_detection_re_enable_prompt_body` | ntf | Turn meeting notifications back on and we'll remind you to start Notetaker when we detect a meeting. | reuse |
| `meeting_detection_re_enable_prompt_title` | ntf | Never miss meeting notes | reuse |
| `meeting_live_transcript_unavailable_action_cancel` | ntf | Cancel | reuse |
| `meeting_live_transcript_unavailable_action_record` | ntf | Record offline | rewrite |
| `meeting_live_transcript_unavailable_body` | ntf | You can still record offline. Your audio will be saved on this device and transcribed when you’re back online. | rewrite |
| `meeting_live_transcript_unavailable_title` | ntf | Live transcript unavailable | reuse |
| `meeting_notice_auto_disabled_action_keep_off` | ntf | Got it | reuse |
| `meeting_notice_auto_disabled_action_turn_on` | ntf | Turn back on | reuse |
| `meeting_notice_auto_disabled_body` | ntf | Looks like these aren't helpful right now. Turn on notifications to transcribe and generate notes for meetings. | reuse |
| `meeting_notice_auto_disabled_title` | ntf | Meeting notifications turned off | reuse |
| `meeting_notice_ignored_opt_out_prompt_action_manage` | ntf | Manage notifications | reuse |
| `meeting_notice_ignored_opt_out_prompt_action_no_thanks` | ntf | Keep as is | reuse |
| `meeting_notice_ignored_opt_out_prompt_body` | ntf | You've ignored the past few Notetaker notifications. You can change how we notify you. | reuse |
| `meeting_notice_ignored_opt_out_prompt_title` | ntf | Turn off meeting notifications? | reuse |
| `meeting_notice_opt_out_prompt_action_manage` | ntf | Manage notifications | reuse |
| `meeting_notice_opt_out_prompt_action_no_thanks` | ntf | Keep as is | reuse |
| `meeting_notice_opt_out_prompt_body` | ntf | You've closed the last few Notetaker meeting notifications. You can change when we notify you about meetings. | reuse |
| `meeting_notice_opt_out_prompt_title` | ntf | Turn off meeting notifications? | reuse |
| `meeting_recorder_nudge_action_later` | ntf | Another time | reuse |
| `meeting_recorder_nudge_action_maybe_later` | ntf | Maybe later | reuse |
| `meeting_recorder_nudge_action_start_notetaker` | ntf | Yes | reuse |
| `meeting_recorder_nudge_action_yes_take_notes` | ntf | Yes, take notes for me | reuse |
| `meeting_recorder_nudge_action_yes_transcribe` | ntf | Yes, transcribe | reuse |
| `meeting_recorder_nudge_consent_label` | ntf | Enable Private Cloud Sync | rewrite |
| `meeting_recorder_nudge_consent_label_blocking` | ntf | Enable Private Cloud Sync to start | rewrite |
| `meeting_recorder_nudge_first_body_preview` | ntf | Wispr Notetaker transcribes meetings, and generates accurate notes and action items when you're done! | reuse |
| `meeting_recorder_nudge_first_body_sync_on` | ntf | Wispr Notetaker captures names, speakers, and decisions, so your recaps and follow-ups come out right. | reuse |
| `meeting_recorder_nudge_first_title` | ntf | Transcribe this meeting with Wispr? | reuse |
| `meeting_recorder_nudge_first_title_notes` | ntf | Want notes for this meeting? | reuse |
| `meeting_recorder_nudge_second_never_tried_action_get_action_items` | ntf | Get action items | reuse |
| `meeting_recorder_nudge_second_never_tried_action_no_thanks` | ntf | No thanks | reuse |
| `meeting_recorder_nudge_second_never_tried_action_not_this_one` | ntf | Not this one | reuse |
| `meeting_recorder_nudge_second_never_tried_action_own_notes` | ntf | I'll take my own | reuse |
| `meeting_recorder_nudge_second_never_tried_action_start_notetaker` | ntf | Start Notetaker | reuse |
| `meeting_recorder_nudge_second_never_tried_action_take_notes` | ntf | Take notes for me | reuse |
| `meeting_recorder_nudge_second_never_tried_body_action_items` | ntf | Transcribes while you talk, then pulls out the decisions and to-dos. Nothing joins the call. | reuse |
| `meeting_recorder_nudge_second_never_tried_body_take_notes` | ntf | It transcribes while you talk and writes detailed notes when the call ends, so you can stay present. | reuse |
| `meeting_recorder_nudge_second_never_tried_body_try_it` | ntf | Transcribes quietly in the background, then writes notes and action items when the call ends. Stop it any time. | reuse |
| `meeting_recorder_nudge_second_never_tried_title_action_items` | ntf | Want the action items from this meeting? | reuse |
| `meeting_recorder_nudge_second_never_tried_title_take_notes` | ntf | Wispr Notetaker can take notes on this call | reuse |
| `meeting_recorder_nudge_second_never_tried_title_try_it` | ntf | Try out Wispr Notetaker on this meeting | reuse |
| `meeting_recorder_nudge_second_under_5_action_take_notes` | ntf | Take notes for me | reuse |
| `meeting_recorder_nudge_second_under_5_body` | ntf | Wispr Notetaker transcribes the call and writes notes after. | reuse |
| `meeting_recorder_nudge_second_under_5_title` | ntf | Want notes and action items\nfor this meeting? | reuse |
| `meeting_recording_connection_lost_body` | ntf | We lost the connection. Your audio was saved. | reuse |
| `meeting_recording_connection_lost_title` | ntf | Connection lost | reuse |
| `meeting_recording_failed_action_discard` | ntf | Discard | reuse |
| `meeting_recording_failed_action_retry` | ntf | Try again | reuse |
| `meeting_recording_failed_body` | ntf | We couldn't capture any audio, so nothing was saved. | reuse |
| `meeting_recording_failed_body_saved` | ntf | We couldn't start live transcription. Your audio was saved on this device. | reuse |
| `meeting_recording_failed_title` | ntf | Couldn't start recording | reuse |
| `meeting_started_by_mistake_action_discard` | ntf | Discard | reuse |
| `meeting_started_by_mistake_action_save` | ntf | Keep | reuse |
| `meeting_started_by_mistake_body` | ntf | Only a few words were captured. Keep this meeting or discard it. | reuse |
| `meeting_started_by_mistake_title` | ntf | Started by mistake? | reuse |
| `meeting_stopped_action_view_meeting` | ntf | View meeting | reuse |
| `meeting_stopped_no_save_body` | ntf | No audio was recorded. | reuse |
| `meeting_stopped_no_save_title` | ntf | Stopped meeting | reuse |
| `meeting_summary_ready_action_view` | ntf | View summary | reuse |
| `meeting_summary_ready_body` | ntf | From {{meeting}} | reuse |
| `meeting_summary_ready_body_untitled` | ntf | Synthesized your notes | reuse |
| `meeting_summary_ready_title` | ntf | Your summary is ready! | reuse |
| `notetaker_auto_hide_enabled_action_undo` | ntf | Undo | reuse |
| `notetaker_auto_hide_enabled_title` | ntf | Notepad will be hidden next time | reuse |
| `notetaker_auto_hide_offer_action_accept` | ntf | Hide it | reuse |
| `notetaker_auto_hide_offer_action_keep` | ntf | Keep as is | reuse |
| `notetaker_auto_hide_offer_body` | ntf | We noticed you close the Notepad when starting Notetaker. You can hide it by default. | reuse |
| `notetaker_auto_hide_offer_title` | ntf | Hide Notepad when Notetaker starts? | reuse |
| `notetaker_auto_start_opt_in_action_not_now` | ntf | Not now | reuse |
| `notetaker_auto_start_opt_in_action_turn_on` | ntf | Turn on | reuse |
| `notetaker_auto_start_opt_in_body` | ntf | This will turn on Notetaker as soon as your meeting begins | reuse |
| `notetaker_auto_start_opt_in_title` | ntf | Want Notetaker to start automatically? | reuse |
| `notetaker_mic_mismatch_action_check_settings` | ntf | Open settings | reuse |
| `notetaker_mic_mismatch_action_dont_show_again` | ntf | Don't show again | reuse |
| `notetaker_mic_mismatch_bar_body` | ntf | `{{meetingApp}} is using <strong>{{meetingMic}}</strong> but Wispr Flow is using your <strong>{{wisprMic}}</strong>. Change your system mic so Notetaker captures the correct audio.` | reuse |
| `notetaker_mic_mismatch_body` | ntf | `{{meetingApp}} is using <strong>{{meetingMic}}</strong> but Wispr Flow is using your <strong>{{wisprMic}}</strong>. If you're not seeing your words captured in Notetaker, change your system mic to <strong>{{meetingMic}}</strong>.` | reuse |
| `notetaker_mic_mismatch_title` | ntf | We might not be capturing your words | reuse |
| `notetaker_mic_no_audio_detected_action_ignore` | ntf | Ignore | reuse |
| `notetaker_mic_no_audio_detected_action_switch` | ntf | Microphone settings | reuse |
| `notetaker_mic_no_audio_detected_body` | ntf | No sound from {{micLabel}} for the past 3 minutes. Check that it's the right mic and that you're not muted. | reuse |
| `notetaker_mic_no_audio_detected_escalated_action_ignore` | ntf | Ignore | reuse |
| `notetaker_mic_no_audio_detected_escalated_action_switch` | ntf | Microphone settings | reuse |
| `notetaker_mic_no_audio_detected_escalated_body` | ntf | Maybe you're muted? We still haven't heard any audio from {{micLabel}}. | reuse |
| `notetaker_mic_no_audio_detected_escalated_title` | ntf | Still there? Notetaker isn't hearing anything | reuse |
| `notetaker_mic_no_audio_detected_title` | ntf | Notetaker isn't hearing audio from your mic | reuse |
| `notetaker_retention_notice_action_go_to_notetaker` | ntf | Go to Notetaker | drop |
| `notetaker_retention_notice_body` | ntf | Your admin has set Notetaker transcript retention to {{duration}}. Transcripts older than {{duration}} will be deleted within 24 hours | drop |
| `notetaker_retention_notice_title` | ntf | 24 hours to save old transcripts | drop |
| `notetaker_screen_share_education_action_update_settings` | ntf | Update settings | reuse |
| `notetaker_screen_share_education_body` | ntf | Your Flow Bar and Notepad show up in screen shares and screenshots. | reuse |
| `notetaker_screen_share_education_title` | ntf | Notetaker screen share | reuse |
| `notetaker_setup_idle_blocked_action_close` | ntf | Close Notetaker | reuse |
| `notetaker_setup_idle_blocked_action_finish` | ntf | Finish Setup | reuse |
| `notetaker_setup_idle_blocked_body` | ntf | Finish setup to start recording your meeting. | reuse |
| `notetaker_setup_idle_blocked_title` | ntf | Notetaker isn't recording yet | reuse |
| `notetaker_system_audio_not_enabled_action_enable` | ntf | Turn on system audio | reuse |
| `notetaker_system_audio_not_enabled_body` | ntf | Turn on system audio to capture what others say in your meeting. | reuse |
| `notetaker_system_audio_not_enabled_title` | ntf | System audio turned off | reuse |
| `notetaker_unsupported_language_detected_action_got_it` | ntf | Got it | reuse |
| `notetaker_unsupported_language_detected_action_learn_more` | ntf | Learn more | reuse |
| `notetaker_unsupported_language_detected_body` | ntf | Notetaker currently supports {{languageCount}} languages. The transcript may have errors with other languages. | reuse |
| `notetaker_unsupported_language_detected_title` | ntf | This sounds like a language we don't support yet | reuse |
| `recording_checkin_max_length_action_dismiss` | ntf | Dismiss | reuse |
| `recording_checkin_max_length_action_end` | ntf | End recording | reuse |
| `recording_checkin_max_length_action_save` | ntf | Save | reuse |
| `recording_checkin_max_length_action_yes` | ntf | Yes | reuse |
| `recording_checkin_max_length_body_offer` | ntf | We'll auto-end transcriptions at {{limit}}. Would you like to extend this meeting? | reuse |
| `recording_checkin_max_length_body_picker` | ntf | We'll still check with you before ending it | reuse |
| `recording_checkin_max_length_body_top_rung` | ntf | {{limit}} is the limit for transcriptions. | reuse |
| `recording_checkin_max_length_countdown` | ntf | {{time}} min | reuse |
| `recording_checkin_max_length_limit_minutes_one` | ntf | {{count}} minute | reuse |
| `recording_checkin_max_length_limit_minutes_other` | ntf | {{count}} minutes | reuse |
| `recording_checkin_max_length_title` | ntf | Approaching time limit | reuse |
| `recording_checkin_max_length_title_continue` | ntf | Continue transcribing? | reuse |
| `recording_checkin_max_length_title_picker` | ntf | Change auto-end time? | reuse |
| `recording_checkin_max_length_title_top_rung` | ntf | Transcription will end soon | reuse |
| `recording_checkin_still_transcribing_title` | ntf | Still taking notes | reuse |
| `recording_stopped_action_keep` | ntf | Keep going | reuse |
| `recording_stopped_action_stop` | ntf | Stop | reuse |
| `recording_stopped_title` | ntf | Notetaker stopping | reuse |
| `silence_stop_still_going_title` | ntf | Meeting still going? | reuse |
| `suggest_notetaker_action_try` | ntf | Try Notetaker | reuse |
| `suggest_notetaker_body` | ntf | Record long thoughts and conversations with Notetaker to get a transcript and summary. | reuse |
| `suggest_notetaker_title` | ntf | That was a long one… try Notetaker next time! | reuse |
| `notetaker_auto_start_banner_description` | hub | This will turn on Notetaker as soon as your meeting begins | reuse |
| `notetaker_auto_start_banner_not_now` | hub | Not now | reuse |
| `notetaker_auto_start_banner_title` | hub | Want Notetaker to start automatically? | reuse |
| `notetaker_auto_start_banner_turn_on` | hub | Turn on | reuse |

### Settings

#### Settings sidebar and update status (13)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_sidebar_badge_label` | set | Needs attention | reuse |
| `settings_sidebar_page_data_privacy` | set | Data and Privacy | reuse |
| `settings_sidebar_page_experimental` | set | Experimental | reuse |
| `settings_sidebar_page_general` | set | General | reuse |
| `settings_sidebar_page_notetaker` | set | Notetaker | reuse |
| `settings_sidebar_page_system` | set | System | reuse |
| `settings_sidebar_page_vibe_coding` | set | Vibe coding | reuse |
| `settings_sidebar_settings_section` | set | SETTINGS | reuse |
| `settings_sidebar_update_checking` | set | Checking for updates... | reuse |
| `settings_sidebar_update_downloading` | set | Update downloading... | reuse |
| `settings_sidebar_update_error_restart` | set | Error updating, please restart | reuse |
| `settings_sidebar_update_ready_restart` | set | Click to update and restart Flow | reuse |
| `settings_sidebar_update_up_to_date` | set | Up to date; check again? | reuse |

#### General (21)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_general_app_language_description` | set | Select your preferred Wispr Flow Hub language | reuse |
| `settings_general_app_language_label` | set | App Language | reuse |
| `settings_general_app_language_no_results` | set | No matches found | reuse |
| `settings_general_app_language_search_placeholder` | set | Search language | reuse |
| `settings_general_app_language_system_default` | set | System Default | reuse |
| `settings_general_change_button` | set | Change | reuse |
| `settings_general_dictation_languages_label` | set | Dictation Languages | reuse |
| `settings_general_languages_and_more` | set | {{preview}} and {{count}} more | reuse |
| `settings_general_languages_auto_detect` | set | Auto-detect (99 languages) | reuse |
| `settings_general_languages_label` | set | Languages | reuse |
| `settings_general_languages_none_selected` | set | No languages selected | reuse |
| `settings_general_learn_more` | set | Learn more → | reuse |
| `settings_general_microphone_dialog_subtitle` | set | Used for dictation. Notetaker always uses Auto-detect. | reuse |
| `settings_general_microphone_dialog_title` | set | Microphone | reuse |
| `settings_general_microphone_label` | set | Microphone | reuse |
| `settings_general_page_title` | set | General | reuse |
| `settings_general_shortcuts_dialog_subtitle` | set | Choose your preferred shortcuts for using Flow. | reuse |
| `settings_general_shortcuts_dialog_title` | set | Shortcuts | reuse |
| `settings_general_shortcuts_hint_prefix` | set | Hold | reuse |
| `settings_general_shortcuts_hint_suffix` | set | and speak. | reuse |
| `settings_general_shortcuts_label` | set | Shortcuts | reuse |

#### Shortcuts dialog and shortcut recorder (57)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_hotkey_dialog_add_another` | set | Add another | reuse |
| `settings_hotkey_dialog_back_to_shortcuts` | set | Back to Shortcuts | reuse |
| `settings_hotkey_dialog_banner_cta` | set | Set it up | reuse |
| `settings_hotkey_dialog_banner_dismiss_aria` | set | Dismiss banner | reuse |
| `settings_hotkey_dialog_banner_new_tag` | set | New | reuse |
| `settings_hotkey_dialog_banner_subtitle_generic` | set | Start Flow with your mouse to make dictating even easier | reuse |
| `settings_hotkey_dialog_banner_subtitle_with_name` | set | Start Flow with your {{mouseName}} mouse to make dictating even easier | reuse |
| `settings_hotkey_dialog_banner_title` | set | Introducing: Mouse Shortcuts | reuse |
| `settings_hotkey_dialog_cancel_description` | set | Dismiss dictation and notifications | reuse |
| `settings_hotkey_dialog_cancel_title` | set | Cancel | reuse |
| `settings_hotkey_dialog_command_mode_description` | set | Select text and ask Flow or [AI chat app] | rewrite |
| `settings_hotkey_dialog_command_mode_title` | set | Command Mode | reuse |
| `settings_hotkey_dialog_copy_last_transcript_description` | set | Copy the last thing you dictated | reuse |
| `settings_hotkey_dialog_copy_last_transcript_title` | set | Copy last transcript | reuse |
| `settings_hotkey_dialog_done` | set | Done | reuse |
| `settings_hotkey_dialog_enter_rebind_description` | set | Trigger enter with a mouse shortcut (or another key) to send messages faster | reuse |
| `settings_hotkey_dialog_enter_rebind_title` | set | Press Enter | reuse |
| `settings_hotkey_dialog_hands_free_description` | set | Dictate hands-free by pressing this hotkey to start and stop | reuse |
| `settings_hotkey_dialog_hands_free_double_tap_hint` | set | `Double tap <keys></keys>` | reuse |
| `settings_hotkey_dialog_hands_free_title` | set | Hands-free mode | reuse |
| `settings_hotkey_dialog_instruct_mode_description` | set | Dictate instructions to draft replies using screen context | reuse |
| `settings_hotkey_dialog_instruct_mode_title` | set | Instruct Mode | reuse |
| `settings_hotkey_dialog_open_scratchpad_description` | set | Open the scratchpad window | reuse |
| `settings_hotkey_dialog_open_scratchpad_title` | set | Open Scratchpad | reuse |
| `settings_hotkey_dialog_paste_last_transcript_description` | set | Paste the last thing you dictated | reuse |
| `settings_hotkey_dialog_paste_last_transcript_title` | set | Paste last transcript | reuse |
| `settings_hotkey_dialog_ptt_description` | set | Hold to say something short | reuse |
| `settings_hotkey_dialog_ptt_suggestion` | set | `We recommend <pill>control</pill> + <pill>space</pill>` | reuse |
| `settings_hotkey_dialog_ptt_title` | set | Push to talk | reuse |
| `settings_hotkey_dialog_reset_to_default` | set | Reset to default | reuse |
| `settings_hotkey_dialog_start_notetaker_description` | set | Open Notetaker and start recording | reuse |
| `settings_hotkey_dialog_start_recording_description` | set | Open the Notetaker and start a new note | reuse |
| `settings_hotkey_dialog_start_recording_title` | set | Join meeting / start Notetaker | reuse |
| `settings_hotkey_dialog_start_setup` | set | Start setup | reuse |
| `settings_hotkey_dialog_toast_finish_recording_first` | set | Please stop the Notetaker first | reuse |
| `settings_hotkey_dialog_toast_mouse_flow_setup_complete` | set | Mouse Flow setup complete! | reuse |
| `settings_hotkey_dialog_toast_reset_to_default` | set | Reset to default | reuse |
| `settings_hotkey_dialog_tooltip_add_new_shortcut` | set | Click here to add a new shortcut | reuse |
| `settings_hotkey_dialog_tooltip_click_mouse_button` | set | Click your mouse button to add the shortcut | reuse |
| `settings_hotkey_dialog_tooltip_enter_rebind_mouse_button` | set | You can bind another mouse button to trigger enter and send messages faster | reuse |
| `settings_hotkey_dialog_transform_description` | set | Configure polish, custom, and more in the Transform tab | reuse |
| `settings_hotkey_dialog_transform_title` | set | Transform | reuse |
| `settings_hotkey_dialog_view_diff_description` | set | Opens window to view diffs after a Transform | reuse |
| `settings_hotkey_dialog_view_diff_title` | set | Transform view changes | reuse |
| `settings_hotkey_dialog_warning_ptt_hands_free_overlap` | set | Warning: Your Hands-free mode shortcut is a part of a Push-to-talk shortcut. This may lead to conflicts. | reuse |
| `settings_shortcut_cancel_recording` | set | Cancel | reuse |
| `settings_shortcut_click_to_add` | set | Click to add a shortcut | reuse |
| `settings_shortcut_edit` | set | Edit shortcut | reuse |
| `settings_shortcut_enter_new_hotkey` | set | Enter new hotkey | reuse |
| `settings_shortcut_error_blocked` | set | This shortcut is not allowed: {{keyString}} | reuse |
| `settings_shortcut_error_in_use` | set | This shortcut is already in use | reuse |
| `settings_shortcut_error_left_right_same` | set | Shortcut cannot contain both left and right version of the same key | reuse |
| `settings_shortcut_error_no_modifier` | set | Shortcut must include a modifier key or a valid mouse button | reuse |
| `settings_shortcut_error_too_many_keys` | set | Shortcut must contain 3 or fewer keys | reuse |
| `settings_shortcut_press_key_or_mouse` | set | Press key or mouse button | reuse |
| `settings_shortcut_remove` | set | Remove shortcut | reuse |
| `settings_shortcut_toast_saved` | set | Shortcut saved | reuse |

#### Microphone (10)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_microphone_airpods_warning` | set | AirPods may be slow to start and have more errors in dictation. We recommend the built in microphone. | reuse |
| `settings_microphone_built_in_recommended` | set | Built-in mic (recommended) | reuse |
| `settings_microphone_clamshell_unavailable` | set | Laptop lid is closed | reuse |
| `settings_microphone_default_overrides_description` | set | From computer settings | reuse |
| `settings_microphone_ranking_description` | set | Drag to reorder microphone preference ranking | reuse |
| `settings_microphone_ranking_edit` | set | Edit Ranking | reuse |
| `settings_microphone_ranking_forget` | set | Forget device | reuse |
| `settings_microphone_ranking_hide` | set | Done Editing | reuse |
| `settings_microphone_unknown` | set | unknown | reuse |
| `settings_microphone_virtual_devices_toggle` | set | Show other devices ({{count}}) | reuse |

#### Languages (13)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_languages_auto_detect_count` | set | 99 languages | reuse |
| `settings_languages_auto_detect_description` | set | Auto-detect is on. Flow will try to detect the language you are speaking. | reuse |
| `settings_languages_auto_detect_toggle` | set | Auto-detect | reuse |
| `settings_languages_hinglish_note_dismiss_aria` | set | Dismiss Hinglish tip | reuse |
| `settings_languages_hinglish_note_switch` | set | Switch to Hinglish | reuse |
| `settings_languages_hinglish_note_title` | set | Want Hindi in English letters? | reuse |
| `settings_languages_hinglish_tile_subtitle` | set | Hindi in English letters | reuse |
| `settings_languages_save_and_close` | set | Save and close | reuse |
| `settings_languages_search_placeholder` | set | Search for any languages | reuse |
| `settings_languages_select_one_or_auto_detect_error` | set | Please select at least one language or turn on auto-detect | reuse |
| `settings_languages_selected_title` | set | Selected | reuse |
| `settings_languages_subtitle` | set | Choose the languages you want to dictate in. Notetaker autodetects languages separately. | reuse |
| `settings_languages_title` | set | Dictation languages | reuse |

#### Notetaker (Settings › Notetaker pane and the Notetaker rows of System) (119)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_notetaker_page_title` | set | Notetaker | reuse |
| `settings_notetaker_start_tutorial` | set | Start tutorial | reuse |
| `settings_system_auto_detect_meetings_description` | set | Notetaker asks if you want to start a note when you join a call | reuse |
| `settings_system_auto_detect_meetings_label` | set | Auto Detect | reuse |
| `settings_system_hide_meeting_recorder_in_screen_share` | set | Make Flow Bar and Notepad invisible while screen sharing | reuse |
| `settings_system_notetaker_attribute_names` | set | Speaker names | reuse |
| `settings_system_notetaker_attribute_names_description` | set | Show who said what by labeling each speaker in the transcript | reuse |
| `settings_system_notetaker_auto_detect` | set | Automatically detect any call | reuse |
| `settings_system_notetaker_auto_detect_do_nothing` | set | Do nothing | reuse |
| `settings_system_notetaker_auto_detect_names` | set | Auto-detect speaker names | reuse |
| `settings_system_notetaker_auto_detect_names_description` | set | Read participant names from the meeting so the transcript shows who's speaking | reuse |
| `settings_system_notetaker_auto_detect_notify` | set | Notify me | reuse |
| `settings_system_notetaker_auto_end` | set | Stop Notetaker when a call ends | reuse |
| `settings_system_notetaker_auto_end_description` | set | Notetaker stops automatically so you don't have to | reuse |
| `settings_system_notetaker_auto_share_attendees` | set | Auto-share notes with invited attendees after the meeting ends | drop |
| `settings_system_notetaker_auto_share_attendees_description` | set | Invited attendees get access to the notes when the recording ends | drop |
| `settings_system_notetaker_auto_share_audience_all` | set | all attendees | drop |
| `settings_system_notetaker_auto_share_audience_domain` | set | @{{domain}} attendees | drop |
| `settings_system_notetaker_auto_share_audience_off` | set | no one | drop |
| `settings_system_notetaker_auto_share_meetings` | set | Which meetings | drop |
| `settings_system_notetaker_auto_share_meetings_all` | set | all meetings | drop |
| `settings_system_notetaker_auto_share_meetings_notice` | set | meetings with a calendar notice | drop |
| `settings_system_notetaker_auto_share_meetings_notice_disabled` | set | Turn on calendar notice first | drop |
| `settings_system_notetaker_auto_share_notes` | set | Auto-share notes | drop |
| `settings_system_notetaker_auto_share_notes_all` | set | Auto-share notes with all attendees | drop |
| `settings_system_notetaker_auto_share_notes_description` | set | Choose which invited attendees get access when notes are ready | drop |
| `settings_system_notetaker_auto_share_notes_domain` | set | Auto-share notes with attendees with @{{domain}} emails | drop |
| `settings_system_notetaker_auto_share_notes_off` | set | Off | drop |
| `settings_system_notetaker_auto_share_sentence` | set | `When notes are ready, share them with <audience></audience> for <scope></scope>` | drop |
| `settings_system_notetaker_auto_share_sentence_audience_only` | set | `When notes are ready, share them with <audience></audience>` | drop |
| `settings_system_notetaker_auto_share_toast_all_all` | set | Notes will be shared with all attendees after every meeting. | drop |
| `settings_system_notetaker_auto_share_toast_all_calendar_notice` | set | Notes will be shared with all attendees after meetings with a calendar notice. | drop |
| `settings_system_notetaker_auto_share_toast_domain_all` | set | Notes will be shared with @{{domain}} attendees after every meeting. | drop |
| `settings_system_notetaker_auto_share_toast_domain_calendar_notice` | set | Notes will be shared with @{{domain}} attendees after meetings with a calendar notice. | drop |
| `settings_system_notetaker_auto_share_toast_off` | set | Notes won't be shared automatically. | drop |
| `settings_system_notetaker_auto_start` | set | Start Notetaker automatically | reuse |
| `settings_system_notetaker_auto_start_description` | set | Start Notetaker when a meeting begins | reuse |
| `settings_system_notetaker_auto_start_needs_detection` | set | Turn on “Automatically detect any call” to use this | reuse |
| `settings_system_notetaker_calendar_notice` | set | Calendar notice | reuse |
| `settings_system_notetaker_calendar_notice_auto_share_description` | set | Notes will be auto-shared to attendees after the meeting. | drop |
| `settings_system_notetaker_calendar_notice_connect_body` | set | Wispr adds notices to events you organize, so it needs your calendar connected. Connect it in Connectors, then turn this on. | rewrite |
| `settings_system_notetaker_calendar_notice_connect_cta` | set | Go to Connectors | rewrite |
| `settings_system_notetaker_calendar_notice_connect_failed` | set | Couldn't connect Google Calendar. Try again. | rewrite |
| `settings_system_notetaker_calendar_notice_connect_now_cta` | set | Connect | reuse |
| `settings_system_notetaker_calendar_notice_connect_title` | set | Connect Google Calendar first | rewrite |
| `settings_system_notetaker_calendar_notice_description` | set | Indicate you'll be using notetaker in the description of your calendar events | reuse |
| `settings_system_notetaker_calendar_notice_disable` | set | Disable | reuse |
| `settings_system_notetaker_calendar_notice_notice_and_auto_share` | set | Auto-share with emails | drop |
| `settings_system_notetaker_calendar_notice_notice_and_link` | set | Notice and notes link | rewrite |
| `settings_system_notetaker_calendar_notice_notice_only` | set | Notice only | reuse |
| `settings_system_notetaker_calendar_notice_off` | set | Off | reuse |
| `settings_system_notetaker_calendar_notice_outlook_body` | set | You have {{setting}} turned on. Calendar notices only work with Google Calendar for now. | rewrite |
| `settings_system_notetaker_calendar_notice_outlook_title` | set | Not available for Outlook yet | rewrite |
| `settings_system_notetaker_calendar_notice_preview_event_title` | set | Team standup | reuse |
| `settings_system_notetaker_calendar_notice_preview_event_when` | set | Tomorrow, 10:00am | reuse |
| `settings_system_notetaker_calendar_notice_preview_existing` | set | Bring last week's notes and the sprint board. | reuse |
| `settings_system_notetaker_calendar_notice_preview_guests` | set | Guests | reuse |
| `settings_system_notetaker_calendar_notice_preview_title` | set | Example calendar event with notice | reuse |
| `settings_system_notetaker_calendar_notice_preview_you` | set | You | reuse |
| `settings_system_notetaker_calendar_notice_reconnect_body` | set | Reconnect Calendar and click “Select all” so Wispr can add a notice to events you organize. | reuse |
| `settings_system_notetaker_calendar_notice_reconnect_cta` | set | Reconnect | reuse |
| `settings_system_notetaker_calendar_notice_reconnect_title` | set | Reconnect Google Calendar | rewrite |
| `settings_system_notetaker_calendar_notice_required_body` | set | You have {{setting}} turned on. Connect Google Calendar so Wispr can add a notice to events you organize. | rewrite |
| `settings_system_notetaker_calendar_notice_required_title` | set | Connect Google Calendar | rewrite |
| `settings_system_notetaker_calendar_notice_sample` | set | Example: “{{sample}}” | reuse |
| `settings_system_notetaker_calendar_notice_toast_notice_and_link` | set | Calendar events you organize will include a notice and notes link. | rewrite |
| `settings_system_notetaker_calendar_notice_toast_notice_only` | set | Calendar events you organize will include a notice. | reuse |
| `settings_system_notetaker_calendar_notice_toast_off` | set | Calendar events you organize won't include a notice. | reuse |
| `settings_system_notetaker_calendar_notice_write_scope_missing` | set | Wispr still can't add notices. Reconnect and click “Select all”. | reuse |
| `settings_system_notetaker_calendar_notifications` | set | Notify before scheduled meetings start | reuse |
| `settings_system_notetaker_calendar_notifications_1_minute` | set | 1 minute before | reuse |
| `settings_system_notetaker_calendar_notifications_1_minute_short` | set | 1 min | reuse |
| `settings_system_notetaker_calendar_notifications_2_minutes` | set | 2 minutes before | reuse |
| `settings_system_notetaker_calendar_notifications_2_minutes_short` | set | 2 min | reuse |
| `settings_system_notetaker_calendar_notifications_description` | set | Choose when to get a heads-up before a meeting on your calendar starts | reuse |
| `settings_system_notetaker_calendar_notifications_never` | set | Never | reuse |
| `settings_system_notetaker_calendar_notifications_right_before` | set | Right before the meeting | reuse |
| `settings_system_notetaker_calendar_notifications_right_before_short` | set | 15 sec | reuse |
| `settings_system_notetaker_change_shortcut` | set | Change shortcut | reuse |
| `settings_system_notetaker_consent` | set | Consent | reuse |
| `settings_system_notetaker_consent_chat` | set | Post a consent notice in the meeting chat | reuse |
| `settings_system_notetaker_consent_chat_description` | set | When the Notetaker starts, lets everyone in the call know you're transcribing it | reuse |
| `settings_system_notetaker_consent_chat_message` | set | Consent notice | reuse |
| `settings_system_notetaker_consent_chat_message_description` | set | The message posted in the meeting chat. Leave it as is to use the default. | reuse |
| `settings_system_notetaker_consent_chat_message_locked` | set | Set by your organization. You can't edit this message. | rewrite |
| `settings_system_notetaker_consent_chat_message_reset` | set | Reset to default | reuse |
| `settings_system_notetaker_hide_in_screen_share` | set | Don't show Notepad and Flow Bar in screen capture | reuse |
| `settings_system_notetaker_hide_in_screen_share_description` | set | Notepad and Flow Bar won't appear in screenshots or when you share your screen. Always ask for consent before transcribing. | reuse |
| `settings_system_notetaker_join_shortcut_prefix` | set | Press | reuse |
| `settings_system_notetaker_join_shortcut_suffix` | set | to join a meeting or start the Notetaker | reuse |
| `settings_system_notetaker_live_transcript` | set | Show live transcript | reuse |
| `settings_system_notetaker_live_transcript_description` | set | See the words appear on screen when the Notetaker is on | reuse |
| `settings_system_notetaker_live_transcript_next_meeting_toast` | set | Live transcript will be available in your next meeting. | reuse |
| `settings_system_notetaker_max_length` | set | Maximum recording length | reuse |
| `settings_system_notetaker_max_length_1hr` | set | 1 hour | reuse |
| `settings_system_notetaker_max_length_2hr` | set | 2 hours | reuse |
| `settings_system_notetaker_max_length_30min` | set | 30 minutes | reuse |
| `settings_system_notetaker_max_length_3hr` | set | 3 hours | reuse |
| `settings_system_notetaker_max_length_description` | set | Notetaker stops automatically at this length, with a warning shortly before | reuse |
| `settings_system_notetaker_meeting_indicator` | set | While Notetaker is active | reuse |
| `settings_system_notetaker_menu_bar_meeting` | set | Show your next meeting in the menu bar | reuse |
| `settings_system_notetaker_menu_bar_meeting_description` | set | Shows the meeting name and a countdown next to the Wispr Flow icon. Turning it off keeps the icon and its meeting menu. | reuse |
| `settings_system_notetaker_notifications_detection` | set | Meeting detection | reuse |
| `settings_system_notetaker_open_window` | set | Open Notepad when starting Notetaker | reuse |
| `settings_system_notetaker_open_window_description` | set | Opens your notes when you start the Notetaker | reuse |
| `settings_system_notetaker_org_insights` | set | Org insights for new meetings | drop |
| `settings_system_notetaker_org_insights_body` | set | When on, new meetings start visible to your org’s AI for insights. You can still switch any meeting on or off from its header. | drop |
| `settings_system_notetaker_recording_window` | set | Notepad | reuse |
| `settings_system_notetaker_set_shortcut_hint` | set | Set a shortcut to join a meeting or start the Notetaker | reuse |
| `settings_system_notetaker_sharing` | set | Sharing | reuse |
| `settings_system_notetaker_shortcut` | set | Keyboard shortcut | reuse |
| `settings_system_notetaker_split_screen` | set | Split the screen when joining | reuse |
| `settings_system_notetaker_split_screen_accessibility_required` | set | Accessibility access is required for split-screen on join. | reuse |
| `settings_system_notetaker_split_screen_description` | set | Puts your meeting on the left and your Notepad on the right, side by side | reuse |
| `settings_system_notetaker_transcription` | set | Transcript | reuse |
| `settings_system_notetaker_triple_tap_shortcut` | set | Triple tap {{dictation_key}} for Notetaker | reuse |
| `settings_system_notetaker_triple_tap_shortcut_description` | set | Press your dictation key three times quickly to join a meeting or start a new note | reuse |
| `settings_system_notetaker_triple_tap_start_notetaker_description` | set | Press your dictation key three times quickly to join a meeting or start Notetaker | reuse |
| `settings_system_section_notetaker` | set | Notetaker | reuse |

#### System (69)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_system_auto_cleanup_moved_prefix` | set | Smart Formatting has moved to the | reuse |
| `settings_system_auto_cleanup_moved_suffix` | set | tab. | reuse |
| `settings_system_auto_cleanup_tab` | set | Auto Cleanup | reuse |
| `settings_system_cancel` | set | Cancel | reuse |
| `settings_system_contextual_mode_custom` | set | Enabled in specific apps | reuse |
| `settings_system_contextual_mode_disabled` | set | Off | reuse |
| `settings_system_contextual_mode_enabled` | set | Enabled in all apps | reuse |
| `settings_system_contextual_mode_not_set` | set | Not configured | reuse |
| `settings_system_contextual_mode_previously_used` | set | Enabled in apps you've used Flow in before | reuse |
| `settings_system_creator_mode_description` | set | Show "Dictating with Wispr Flow" when dictating | reuse |
| `settings_system_creator_mode_label` | set | Creator mode | reuse |
| `settings_system_customize` | set | Customize | reuse |
| `settings_system_dictation_reminder` | set | Dictation reminder | reuse |
| `settings_system_dictation_reminder_disabled_12h` | set | Disabled for 12 hours | reuse |
| `settings_system_dictation_sounds_label` | set | Dictation and notification sounds | reuse |
| `settings_system_flow_bar_hidden_for_hour` | set | Hidden for one hour | reuse |
| `settings_system_launch_at_login` | set | Launch app at login | reuse |
| `settings_system_learn_more` | set | Learn more → | reuse |
| `settings_system_mute_music_auto_off_toast` | set | Mute all audio while dictating is now off. Flow pauses your music instead. | reuse |
| `settings_system_mute_music_label` | set | Mute all audio while dictating | reuse |
| `settings_system_mute_music_pause_tooltip` | set | Want Flow to pause your music instead? Turn on Pause music while dictating in Experimental settings. | reuse |
| `settings_system_notifications_announcements_description` | set | New features or capabilities | reuse |
| `settings_system_notifications_announcements_label` | set | Announcements | reuse |
| `settings_system_notifications_milestones_description` | set | Word-count milestones, streaks, and referral activity | drop |
| `settings_system_notifications_milestones_label` | set | Milestones | reuse |
| `settings_system_notifications_suggestions_description` | set | Tips about getting set up or improving how you use Flow. | reuse |
| `settings_system_notifications_suggestions_label` | set | Suggestions | reuse |
| `settings_system_page_title` | set | System | reuse |
| `settings_system_pause_music_auto_off_toast` | set | Pause music while dictating is now off. Flow mutes all audio instead. | reuse |
| `settings_system_pause_music_label` | set | Pause music while dictating | reuse |
| `settings_system_reset_app_description` | set | Reset only if advised by Flow support. | reuse |
| `settings_system_reset_app_label` | set | Reset app | reuse |
| `settings_system_reset_dialog_subtitle` | set | Deletes local data, but your dictionary, stats, and settings stay saved and re-sync on restart. Reset only if advised by Flow support. | rewrite |
| `settings_system_reset_dialog_title` | set | Reset and restart? | reuse |
| `settings_system_reset_restart_button` | set | Reset & restart | reuse |
| `settings_system_restart_tutorial_button` | set | Restart tutorial | reuse |
| `settings_system_restart_tutorial_confirm_cancel` | set | Cancel | reuse |
| `settings_system_restart_tutorial_confirm_cta` | set | Restart tutorial | reuse |
| `settings_system_restart_tutorial_confirm_subtitle` | set | You'll walk through the setup steps again. Your dictation history, settings, and plan stay as they are. | reuse |
| `settings_system_restart_tutorial_confirm_title` | set | Restart tutorial? | reuse |
| `settings_system_restart_tutorial_description` | set | Walk through the microphone, shortcut, and dictation setup steps again. | reuse |
| `settings_system_restart_tutorial_label` | set | Restart tutorial | reuse |
| `settings_system_scratchpad_open_behavior_default` | set | Resume last note | reuse |
| `settings_system_scratchpad_open_behavior_label` | set | Scratchpad open behavior | reuse |
| `settings_system_scratchpad_open_behavior_last_pinned` | set | Open last active pinned note | reuse |
| `settings_system_scratchpad_open_behavior_new_tab` | set | Open in new tab | reuse |
| `settings_system_scratchpad_open_behavior_subtitle` | set | Choose what happens when you open the scratchpad | reuse |
| `settings_system_section_app_settings` | set | App settings | reuse |
| `settings_system_section_data` | set | Data | reuse |
| `settings_system_section_extras` | set | Extras | reuse |
| `settings_system_section_notifications` | set | Notifications | reuse |
| `settings_system_section_scratchpad` | set | Scratchpad | reuse |
| `settings_system_section_sound` | set | Sound | reuse |
| `settings_system_show_flow_bar` | set | Show Flow Bar at all times | reuse |
| `settings_system_show_flow_bar_coachmark` | set | Show the Flow Bar to move it around | reuse |
| `settings_system_show_in_dock` | set | Show app in dock | reuse |
| `settings_system_smart_formatting_description` | set | Automatically formats your dictation. | reuse |
| `settings_system_smart_formatting_label` | set | Smart Formatting | reuse |
| `settings_system_typing_reminder_ai_apps` | set | AI apps | reuse |
| `settings_system_typing_reminder_all_apps` | set | All apps | reuse |
| `settings_system_typing_reminder_disabled` | set | Disabled | reuse |
| `settings_system_typing_reminder_documents_notes` | set | Document and notes | reuse |
| `settings_system_typing_reminder_email` | set | Email | reuse |
| `settings_system_typing_reminder_personal_messaging` | set | Personal messengers | reuse |
| `settings_system_typing_reminder_previously_used` | set | Any app I've used Flow in before | reuse |
| `settings_system_typing_reminder_specific_apps` | set | Specific app types | reuse |
| `settings_system_typing_reminder_subtitle` | set | Select where the Flow Bar reminder appears to remind you to dictate instead of typing | reuse |
| `settings_system_typing_reminder_title` | set | Dictation Reminder Settings | reuse |
| `settings_system_typing_reminder_work_messaging` | set | Work messengers | reuse |

#### Data and Privacy (39)

Rows that only make sense with a server (cloud storage, HIPAA, exports) are in the dropped summary.

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_data_cancel` | set | Cancel | reuse |
| `settings_data_confirm_autodelete_subtitle` | set | This will delete transcripts and polish history older than 24 hours across all your devices. | rewrite |
| `settings_data_confirm_autodelete_title` | set | Are you sure you want to auto-delete data? | reuse |
| `settings_data_confirm_delete_all` | set | Delete all data | reuse |
| `settings_data_confirm_enable_autodelete` | set | Enable auto-delete | reuse |
| `settings_data_confirm_never_store_subtitle` | set | This will delete all your transcripts and polish history across all your devices, and stop storing new ones. | rewrite |
| `settings_data_confirm_never_store_title` | set | Are you sure you want to never store data? | reuse |
| `settings_data_context_awareness_description` | set | Allow Flow to use limited, relevant text content from the app you're dictating in to spell names correctly and better understand you. | reuse |
| `settings_data_context_awareness_label` | set | Context awareness | reuse |
| `settings_data_data_sharing_description` | set | Share usage data to help us evaluate, train, and improve Flow and its AI models. | drop |
| `settings_data_data_sharing_label` | set | Data Sharing | drop |
| `settings_data_hard_refresh_description` | set | Force a full one-time sync to rescan and retrieve all your notes from the cloud. | drop |
| `settings_data_hard_refresh_label` | set | Hard refresh all notes | drop |
| `settings_data_local_storage_autodelete` | set | Auto-delete local data every 24hrs | reuse |
| `settings_data_local_storage_description` | set | Control how your transcripts are stored locally. This setting applies to all your devices. | rewrite |
| `settings_data_local_storage_description_notetaker` | set | Control how your dictation transcripts are stored locally. This setting applies to all your devices. Notetaker transcripts are managed separately. | rewrite |
| `settings_data_local_storage_label` | set | Local data storage | reuse |
| `settings_data_local_storage_never_store` | set | Never store data locally | reuse |
| `settings_data_local_storage_restricted` | set | Some options are restricted by your organization. | rewrite |
| `settings_data_local_storage_store` | set | Store data locally | reuse |
| `settings_data_page_title` | set | Data and Privacy | reuse |
| `settings_data_privacy_mode_description` | set | Allow your data, including audio, transcripts, edits, to be used to evaluate and improve AI models, by Wispr. | drop |
| `settings_data_privacy_mode_label` | set | Improve the model for everyone | drop |
| `settings_data_read_data_controls` | set | Read about our Data Controls | drop |
| `settings_data_transcript_retention_180_days` | set | 180 days | reuse |
| `settings_data_transcript_retention_1_day` | set | 1 day | reuse |
| `settings_data_transcript_retention_30_days` | set | 30 days | reuse |
| `settings_data_transcript_retention_365_days` | set | 365 days | reuse |
| `settings_data_transcript_retention_7_days` | set | 7 days | reuse |
| `settings_data_transcript_retention_90_days` | set | 90 days | reuse |
| `settings_data_transcript_retention_confirm_cta` | set | Delete older transcripts | reuse |
| `settings_data_transcript_retention_confirm_error` | set | Couldn't update your retention setting. Please try again. | reuse |
| `settings_data_transcript_retention_confirm_subtitle` | set | Transcripts older than {{duration}} will be deleted within 24 hours. This can't be undone. | reuse |
| `settings_data_transcript_retention_confirm_success` | set | Retention updated. | reuse |
| `settings_data_transcript_retention_confirm_title` | set | Auto-delete older transcripts? | reuse |
| `settings_data_transcript_retention_description` | set | Transcripts older than this are deleted from your devices and Wispr’s servers. | rewrite |
| `settings_data_transcript_retention_label` | set | Notetaker transcript retention | reuse |
| `settings_data_transcript_retention_never` | set | Never delete | reuse |
| `settings_data_view` | set | View | reuse |

#### Experimental (12)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_experimental_bulk_import_description` | set | Import snippets and dictionary items from files | reuse |
| `settings_experimental_bulk_import_label` | set | Bulk import | reuse |
| `settings_experimental_command_mode_description` | set | Enable advanced voice commands. | reuse |
| `settings_experimental_command_mode_label` | set | Command Mode | reuse |
| `settings_experimental_instruct_mode_section` | set | Instruct Mode | reuse |
| `settings_experimental_pause_music_description` | set | Pauses media instead of muting it. This feature is experimental. | reuse |
| `settings_experimental_press_enter_description` | set | Automatically press enter when you say 'press enter' at the end of a dictation | reuse |
| `settings_experimental_press_enter_label` | set | Press Enter command | reuse |
| `settings_experimental_stacked_messages_description` | set | Split dictation into separate messages in messaging apps | reuse |
| `settings_experimental_stacked_messages_label` | set | Stacked messages | reuse |
| `settings_experimental_style_detection_description` | set | Automatically set messaging style | reuse |
| `settings_experimental_style_detection_label` | set | Style Detection | reuse |

#### Vibe coding (14)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `settings_vibe_coding_file_tagging_description_prefix` | set | Tags files in your IDE (like | reuse |
| `settings_vibe_coding_file_tagging_description_suffix` | set | ). | reuse |
| `settings_vibe_coding_file_tagging_label` | set | File Tagging in Chat (Cursor & Windsurf) | reuse |
| `settings_vibe_coding_variable_recognition_description` | set | Better understands variables in code. | reuse |
| `settings_vibe_coding_variable_recognition_dialog_step1` | set | Open the Command Palette | reuse |
| `settings_vibe_coding_variable_recognition_dialog_step2` | set | Search for and run | reuse |
| `settings_vibe_coding_variable_recognition_dialog_step3` | set | Confirm the | reuse |
| `settings_vibe_coding_variable_recognition_dialog_step3_code` | set | Screen Reader Optimized | reuse |
| `settings_vibe_coding_variable_recognition_dialog_step3_suffix` | set | flag appears in the bottom bar | reuse |
| `settings_vibe_coding_variable_recognition_dialog_steps_label` | set | In Cursor or Windsurf: | reuse |
| `settings_vibe_coding_variable_recognition_dialog_subtitle` | set | Variable recognition reads your open file to better understand code as you dictate. It requires Screen Reader mode to be enabled in your IDE. | reuse |
| `settings_vibe_coding_variable_recognition_dialog_title` | set | Set up variable recognition | reuse |
| `settings_vibe_coding_variable_recognition_label` | set | Variable recognition (VS Code, Cursor, Windsurf) | reuse |
| `settings_vibe_coding_variable_recognition_setup_button` | set | Set up | reuse |

### Notifications and toasts

#### Microphone and audio (45)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `air_pods_warning_action_change_mic` | ntf | Switch microphone | reuse |
| `air_pods_warning_action_dismiss` | ntf | Don't show again | reuse |
| `air_pods_warning_body` | ntf | They can add delay and hurt accuracy. | reuse |
| `air_pods_warning_title` | ntf | AirPods aren't the best for dictation | reuse |
| `audio_context_recovery_body` | ntf | Try again in a moment. | reuse |
| `audio_context_recovery_title` | ntf | Flow is getting audio ready | reuse |
| `disable_mute_music_action_open_settings` | ntf | Open Settings | reuse |
| `disable_mute_music_body` | ntf | Flow can mute all audio while you dictate. | reuse |
| `disable_mute_music_title` | ntf | Mute all audio while dictating | reuse |
| `disable_pause_music_body` | ntf | Flow will auto-pause music when you dictate. | reuse |
| `disable_pause_music_title` | ntf | Auto-pause music | reuse |
| `mic_device_unavailable_action_choose_microphone` | ntf | Choose Microphone | reuse |
| `mic_device_unavailable_body` | ntf | The microphone you previously selected isn't connected. Choose a different microphone to continue. | reuse |
| `mic_device_unavailable_title` | ntf | Selected microphone is unavailable | reuse |
| `mic_disconnected_action_insert` | ntf | Insert | reuse |
| `mic_disconnected_body` | ntf | Click below to insert the text recorded up to this point. | reuse |
| `mic_disconnected_title` | ntf | Microphone disconnected | reuse |
| `mic_not_found_action_open_settings` | ntf | Open Sound Settings | reuse |
| `mic_not_found_body` | ntf | Flow couldn't find a microphone. Connect one or check that an input device is selected in Sound Settings. | reuse |
| `mic_not_found_title` | ntf | No microphone detected | reuse |
| `mic_not_readable_action_troubleshoot` | ntf | Troubleshoot | reuse |
| `mic_not_readable_body` | ntf | Flow couldn't access your microphone. Another app may be using it, or the audio driver may be stuck. Close other apps that use your mic, then try again. | reuse |
| `mic_not_readable_title` | ntf | Microphone unavailable | reuse |
| `mic_switched_title` | ntf | Using {{micLabel}} | reuse |
| `new_mic_detected_body` | ntf | Would you like to use this mic for Flow? | reuse |
| `new_mic_detected_dont_switch` | ntf | Don't Switch | reuse |
| `new_mic_detected_switch` | ntf | Switch | reuse |
| `new_mic_detected_title` | ntf | {{name}} detected | reuse |
| `no_audio_action_select_microphone` | ntf | Select microphone | reuse |
| `no_audio_action_troubleshoot` | ntf | Troubleshoot | reuse |
| `no_audio_body` | ntf | We didn't pick up any audio from {{micLabel}} | reuse |
| `no_audio_during_dictation_action_contact` | ntf | Contact us | reuse |
| `no_audio_during_dictation_body` | ntf | We're not hearing anything. There may be an issue with your mic or permissions. | reuse |
| `no_audio_during_dictation_escalated_action_contact` | ntf | Contact us | reuse |
| `no_audio_during_dictation_escalated_action_select_microphone` | ntf | Select microphone | reuse |
| `no_audio_during_dictation_escalated_body` | ntf | Your mic isn't picking up any audio. Stop and check your microphone settings. | reuse |
| `no_audio_during_dictation_escalated_title` | ntf | Microphone is not working | reuse |
| `no_audio_during_dictation_title` | ntf | No audio received | reuse |
| `no_audio_title` | ntf | Is your microphone muted? | reuse |
| `no_clamshell_built_in_mic_action_select_microphone` | ntf | Select microphone | reuse |
| `no_clamshell_built_in_mic_body` | ntf | The built-in mic cannot be used while the lid is closed | reuse |
| `no_clamshell_built_in_mic_title` | ntf | Your laptop lid is closed | reuse |
| `suggest_wired_mic_action_select_microphone` | ntf | Select microphone | reuse |
| `suggest_wired_mic_body` | ntf | Flow works best with a wired mic. | reuse |
| `suggest_wired_mic_title` | ntf | Use a wired microphone | reuse |

#### Dictation progress, limits and recovery (20)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `debounce_body` | ntf | Hold down {{shortcut}} while speaking, release to see text. | reuse |
| `debounce_title` | ntf | Don't tap. Hold down {{shortcut}}. | reuse |
| `dictating_with_wispr_flow_title` | ntf | Dictating with Wispr Flow | reuse |
| `dictation_cancelled_other_shortcut_body` | ntf | Another key was pressed while starting. Hold only {{shortcut}} to dictate. | reuse |
| `dictation_cancelled_other_shortcut_title` | ntf | Dictation cancelled | reuse |
| `dictation_duration_warning_title` | ntf | `You have <1 minute left before you reach the 20 minute limit!` | reuse |
| `dictation_max_duration_reached_action_recover` | ntf | Recover text | reuse |
| `dictation_max_duration_reached_body` | ntf | Flow supports up to 20 minutes per session. | reuse |
| `dictation_max_duration_reached_title` | ntf | Transcription session ended. | reuse |
| `helper_not_ready_title` | ntf | Just a moment - Flow is getting ready... | reuse |
| `low_confidence_stop_prompt_title` | ntf | Stop taking notes? | reuse |
| `no_internet_body` | ntf | Your audio will be saved for retry if the transcription fails. | reuse |
| `no_internet_title` | ntf | Is your internet connected? | rewrite |
| `processing_delay_notification_action_dismiss` | ntf | Don't show again | reuse |
| `processing_delay_notification_body` | ntf | Your audio is saved for retrying | reuse |
| `processing_delay_notification_title` | ntf | Taking longer than usual… | reuse |
| `raw_transcript_title` | ntf | Formatting may be missing. Tap to retry | reuse |
| `transcript_currently_processing_action_cancel` | ntf | Cancel | reuse |
| `transcript_currently_processing_body` | ntf | If you'd like to cancel, press {{shortcut}} or click below. | reuse |
| `transcript_currently_processing_title` | ntf | Flow was processing your last transcript | reuse |

#### Formatting, language and feature tips (43)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `canadian_english_nudge_action_open_settings` | ntf | Open settings | reuse |
| `canadian_english_nudge_body` | ntf | You're dictating English in Canada. Add Canadian English in your language settings for Canadian spelling and phrasing. | reuse |
| `canadian_english_nudge_title` | ntf | Try Canadian English | reuse |
| `feature_translate_action_save` | ntf | Save | reuse |
| `fetch_activation_nudge_action_view` | ntf | View | reuse |
| `fetch_activation_nudge_title` | ntf | Next time, ask Flow to Fetch your link | reuse |
| `language_notification_action_open_settings` | ntf | Open Settings | reuse |
| `language_notification_body` | ntf | You can change the output language | reuse |
| `language_notification_title` | ntf | We auto-detected your language. | reuse |
| `mouse_flow_discovery_action_try` | ntf | Try it out | reuse |
| `mouse_flow_discovery_body` | ntf | Add a mouse button shortcut to Flow even faster | reuse |
| `mouse_flow_discovery_reminder_action_dismiss` | ntf | Don't show again | reuse |
| `mouse_flow_discovery_reminder_action_try` | ntf | Try it out | reuse |
| `mouse_flow_discovery_reminder_body` | ntf | Bind your shortcut to one of the buttons on your mouse so you can Flow even faster | reuse |
| `mouse_flow_discovery_reminder_title` | ntf | You can Flow with your mouse! | reuse |
| `mouse_flow_discovery_title` | ntf | Want to Flow with your mouse? | reuse |
| `press_enter_command_prompt_action_disable` | ntf | Disable | reuse |
| `press_enter_command_prompt_action_enable` | ntf | Great | reuse |
| `press_enter_command_prompt_body` | ntf | To send immediately, say "press enter" at the end of your dictation. Note: this will automatically send the message, prompt, or anything else. | reuse |
| `press_enter_command_prompt_title` | ntf | Say "Press enter" to automatically press enter | reuse |
| `smart_formatting_backtrack_action_learn_more` | ntf | Learn more | reuse |
| `smart_formatting_backtrack_body` | ntf | Flow can auto correct mistakes: "How's 6, no 7?" → "How's 7?" | reuse |
| `smart_formatting_backtrack_reminder_title` | ntf | Backtrack caught! | reuse |
| `smart_formatting_backtrack_title` | ntf | Change your mind with Flow | reuse |
| `smart_formatting_emails_body` | ntf | Start with a greeting and Flow formats as email. | reuse |
| `smart_formatting_emails_reminder_title` | ntf | Email formatted! | reuse |
| `smart_formatting_emails_title` | ntf | Flow formats emails for you | reuse |
| `smart_formatting_file_tagging_body` | ntf | Speak a file name, and Flow automatically tags it. Available in Cursor and Windsurf. | reuse |
| `smart_formatting_file_tagging_reminder_title` | ntf | File tagged! | reuse |
| `smart_formatting_file_tagging_title` | ntf | Flow tags files for you | reuse |
| `smart_formatting_list_body` | ntf | Dictate numbers for Flow to format as a list. | reuse |
| `smart_formatting_list_reminder_title` | ntf | Listed! | reuse |
| `smart_formatting_list_title` | ntf | Flow formats lists for you | reuse |
| `suggest_paste_last_text_body` | ntf | Use shortcut {{shortcut}} to paste last dictation. | reuse |
| `suggest_paste_last_text_title` | ntf | Paste last text | reuse |
| `suggest_popo_body` | ntf | Double tap {{shortcut}} to start hands-free mode. | reuse |
| `suggest_popo_title` | ntf | Switch to hands-free mode | reuse |
| `use_case_app_dictation_nudge_body` | ntf | Use your voice to type faster | reuse |
| `use_case_app_dictation_nudge_title` | ntf | Try dictating in this app | reuse |
| `wrong_language_setting_action_dismiss` | ntf | Don't show again | reuse |
| `wrong_language_setting_action_open_settings` | ntf | Open language settings | reuse |
| `wrong_language_setting_body_generic` | ntf | Add it to your preferred languages so Flow always transcribes it correctly. | reuse |
| `wrong_language_setting_title` | ntf | Speaking a different language? | reuse |

#### Errors (database, helper, audio engine, updates, crashes) (33)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `audio_worklet_load_error_action_contact` | ntf | Contact us | reuse |
| `audio_worklet_load_error_action_restart` | ntf | Restart Flow | reuse |
| `audio_worklet_load_error_body` | ntf | Please restart Flow to continue using dictation | reuse |
| `audio_worklet_load_error_title` | ntf | Audio system failed to load | reuse |
| `database_corruption_error_action_contact` | ntf | Contact us | reuse |
| `database_corruption_error_action_restart` | ntf | Restart Flow | reuse |
| `database_corruption_error_body` | ntf | Some of your local data is corrupted. | reuse |
| `database_corruption_error_title` | ntf | Local database corruption | reuse |
| `database_generic_error_action_contact` | ntf | Contact us | reuse |
| `database_generic_error_action_restart` | ntf | Restart Flow | reuse |
| `database_generic_error_body` | ntf | Restarting the app should fix it | reuse |
| `database_generic_error_title` | ntf | There was an error | reuse |
| `database_storage_full_action_contact` | ntf | Contact us | reuse |
| `database_storage_full_action_restart` | ntf | Restart Flow | reuse |
| `database_storage_full_body` | ntf | You are running out of space on your computer | reuse |
| `database_storage_full_title` | ntf | Storage Full | reuse |
| `helper_loading_error_action_contact` | ntf | Contact us | reuse |
| `helper_loading_error_action_restart` | ntf | Restart Flow | reuse |
| `helper_loading_error_body` | ntf | Please try restarting Flow or contact support if the issue persists | reuse |
| `helper_loading_error_title` | ntf | Flow is having trouble loading | reuse |
| `helper_persistent_failure_action_contact` | ntf | Contact us | reuse |
| `helper_persistent_failure_action_restart` | ntf | Restart Flow | reuse |
| `helper_persistent_failure_body` | ntf | Please try restarting Flow or contact support if this persists. | reuse |
| `helper_persistent_failure_title` | ntf | Flow is having trouble starting | reuse |
| `update_error_action_contact` | ntf | Contact us | reuse |
| `update_error_action_restart` | ntf | Restart Flow | reuse |
| `update_error_body` | ntf | Please try restarting Flow or contact support if the issue persists | reuse |
| `update_error_title` | ntf | There was an error updating Flow | reuse |
| `hub_error_boundary_contact_support_button` | hub | Contact support | reuse |
| `hub_error_boundary_image_alt` | hub | Flow error | reuse |
| `hub_error_boundary_restart_button` | hub | Restart Flow | reuse |
| `hub_error_boundary_subtitle` | hub | Your data is safe and we’re looking into the issue. Try again, or restart Flow if the issue persists. | reuse |
| `hub_error_boundary_title` | hub | Flow hit a snag | reuse |

### Insights and stats

#### Insights page and stats tiles (272)

| Key | NS | English | Rebuild |
|---|---|---|---|
| `insights_corrections_dictionary_fixes` | ntf | dictionary fixes | reuse |
| `insights_corrections_dictionary_fixes_tooltip` | ntf | Corrections from your snippets and dictionary | reuse |
| `insights_corrections_tile_subtitle` | ntf | Fixes made by Flow | reuse |
| `insights_corrections_words_corrected_one` | ntf | word corrected | reuse |
| `insights_corrections_words_corrected_other` | ntf | words corrected | reuse |
| `insights_corrections_words_corrected_tooltip` | ntf | Filler words like "um," "like," and other corrections | reuse |
| `insights_desktop_usage_title` | ntf | Desktop usage | reuse |
| `insights_desktop_usage_total_apps_used` | ntf | TOTAL APPS USED \| {{count}} | reuse |
| `insights_eligible_banner_badge` | ntf | NEW | reuse |
| `insights_eligible_banner_title_first` | ntf | Discover your Voice Profile | reuse |
| `insights_eligible_banner_title_update` | ntf | Update your Voice Profile | reuse |
| `insights_eligible_body_first` | ntf | Explore the unique ways you use Flow! | reuse |
| `insights_eligible_body_update` | ntf | See what's new in how you use Flow. | reuse |
| `insights_eligible_cta_first` | ntf | See profile | reuse |
| `insights_eligible_cta_update` | ntf | Update profile | reuse |
| `insights_ready_body` | ntf | Your insights are ready! | reuse |
| `insights_ready_cta` | ntf | View insights | reuse |
| `insights_ready_prefix_a` | ntf | You're a | reuse |
| `insights_ready_prefix_an` | ntf | You're an | reuse |
| `insights_total_words_delta_badge` | ntf | {{percent}}% this month | reuse |
| `insights_total_words_delta_tooltip` | ntf | Compared to {{words}} words this time last month | reuse |
| `insights_total_words_desktop` | ntf | Desktop | reuse |
| `insights_total_words_title` | ntf | Total words dictated | reuse |
| `insights_total_words_words_label` | ntf | {{count}} words | reuse |
| `insights_usage_category_ai` | ntf | AI | reuse |
| `insights_usage_category_document` | ntf | document | reuse |
| `insights_usage_category_email` | ntf | email | reuse |
| `insights_usage_category_other` | ntf | other | reuse |
| `insights_usage_category_personal_messaging` | ntf | personal messaging | reuse |
| `insights_usage_category_work` | ntf | work | reuse |
| `insights_usage_intensity_light` | ntf | Light usage | reuse |
| `insights_usage_intensity_moderate` | ntf | Moderate usage | reuse |
| `insights_usage_intensity_power` | ntf | Power usage | reuse |
| `insights_usage_words_tooltip` | ntf | {{count}} words | reuse |
| `stats_total_words_empty_tagline` | ntf | You've written nothing yet—start dictating! | reuse |
| `stats_total_words_label` | ntf | words | reuse |
| `stats_total_words_object_book_chapter` | ntf | book chapter | reuse |
| `stats_total_words_object_college_essay` | ntf | college essay | reuse |
| `stats_total_words_object_complete_book` | ntf | complete book | reuse |
| `stats_total_words_object_cover_letter` | ntf | cover letter | reuse |
| `stats_total_words_object_dr_seuss_book` | ntf | Dr. Seuss book | reuse |
| `stats_total_words_object_email_newsletter` | ntf | email newsletter | reuse |
| `stats_total_words_object_folk_tale` | ntf | folk tale | reuse |
| `stats_total_words_object_instruction_manual` | ntf | instruction manual | reuse |
| `stats_total_words_object_meme_caption` | ntf | meme caption | reuse |
| `stats_total_words_object_news_article` | ntf | news article | reuse |
| `stats_total_words_object_podcast_season` | ntf | podcast season | reuse |
| `stats_total_words_object_postcard` | ntf | postcard | reuse |
| `stats_total_words_object_short_film_script` | ntf | short film script | reuse |
| `stats_total_words_object_thank_you_note` | ntf | thank-you note | reuse |
| `stats_total_words_object_tweet` | ntf | tweet | reuse |
| `stats_total_words_object_wedding_vow` | ntf | wedding vow | reuse |
| `stats_total_words_tagline` | ntf | You've written {{count}} {{object}}! | reuse |
| `stats_total_words_title` | ntf | Total Words Dictated | reuse |
| `insights_app` | ins | App | reuse |
| `insights_apps` | ins | apps | reuse |
| `insights_average_speed` | ins | Average Speed | reuse |
| `insights_corrections_dictionary_fixes_with_count_one` | ins | {{display}} dictionary fix | reuse |
| `insights_corrections_dictionary_fixes_with_count_other` | ins | {{display}} dictionary fixes | reuse |
| `insights_corrections_fixes_made_by_flow` | ins | Fixes made by Flow | reuse |
| `insights_corrections_words_corrected_with_count_one` | ins | {{display}} word corrected | reuse |
| `insights_corrections_words_corrected_with_count_other` | ins | {{display}} words corrected | reuse |
| `insights_daily_streak` | ins | Daily Streak | reuse |
| `insights_day` | ins | Day | reuse |
| `insights_days` | ins | Days | reuse |
| `insights_desktop_usage_total_apps_one` | ins | TOTAL APPS USED \| {{count}} | reuse |
| `insights_desktop_usage_total_apps_other` | ins | TOTAL APPS USED \| {{count}} | reuse |
| `insights_gauge_top` | ins | Top | reuse |
| `insights_heatmap_current_streak_label` | ins | Current streak | reuse |
| `insights_heatmap_current_streak_one` | ins | {{count}} day streak | reuse |
| `insights_heatmap_current_streak_other` | ins | {{count}} day streak | reuse |
| `insights_heatmap_day_fri` | ins | Fri | reuse |
| `insights_heatmap_day_mon` | ins | Mon | reuse |
| `insights_heatmap_day_sat` | ins | Sat | reuse |
| `insights_heatmap_day_sun` | ins | Sun | reuse |
| `insights_heatmap_day_thu` | ins | Thu | reuse |
| `insights_heatmap_day_tue` | ins | Tue | reuse |
| `insights_heatmap_day_wed` | ins | Wed | reuse |
| `insights_heatmap_less` | ins | Less | reuse |
| `insights_heatmap_longest_streak_one` | ins | Longest streak \| {{count}} day | reuse |
| `insights_heatmap_longest_streak_other` | ins | Longest streak \| {{count}} days | reuse |
| `insights_heatmap_month_apr` | ins | Apr | reuse |
| `insights_heatmap_month_aug` | ins | Aug | reuse |
| `insights_heatmap_month_dec` | ins | Dec | reuse |
| `insights_heatmap_month_feb` | ins | Feb | reuse |
| `insights_heatmap_month_jan` | ins | Jan | reuse |
| `insights_heatmap_month_jul` | ins | Jul | reuse |
| `insights_heatmap_month_jun` | ins | Jun | reuse |
| `insights_heatmap_month_mar` | ins | Mar | reuse |
| `insights_heatmap_month_may` | ins | May | reuse |
| `insights_heatmap_month_nov` | ins | Nov | reuse |
| `insights_heatmap_month_oct` | ins | Oct | reuse |
| `insights_heatmap_month_sep` | ins | Sep | reuse |
| `insights_heatmap_more` | ins | More | reuse |
| `insights_heatmap_navigate_earlier` | ins | Navigate earlier | reuse |
| `insights_heatmap_navigate_later` | ins | Navigate later | reuse |
| `insights_heatmap_top_app` | ins | Top app | reuse |
| `insights_heatmap_total_apps_used` | ins | Total apps used | reuse |
| `insights_heatmap_total_words` | ins | Total words | reuse |
| `insights_metric_daily_streak_short` | ins | STREAK | reuse |
| `insights_metric_wpm_short` | ins | WPM | reuse |
| `insights_ok` | ins | OK | reuse |
| `insights_page_title` | ins | Insights | reuse |
| `insights_retry` | ins | Retry | reuse |
| `insights_see_team_usage` | ins | See team usage | drop |
| `insights_stats_apps_tagline_almost_mastery` | ins | You are almost at flow mastery! | reuse |
| `insights_stats_apps_tagline_always_flow` | ins | You are always in flow state! | reuse |
| `insights_stats_apps_tagline_few_away` | ins | Full Flow is just a few apps away | reuse |
| `insights_stats_apps_tagline_nearly_everywhere` | ins | You’re flowing nearly everywhere! | reuse |
| `insights_stats_apps_tagline_try_flow` | ins | Try Flow in Slack, Docs, or Notion! | reuse |
| `insights_stats_header_subtitle` | ins | Here's a personal snapshot of your productivity with Flow. | reuse |
| `insights_stats_header_title` | ins | You've been Flowing. Hard. | reuse |
| `insights_stats_label_app` | ins | app | reuse |
| `insights_stats_label_apps` | ins | apps | reuse |
| `insights_stats_label_day` | ins | day | reuse |
| `insights_stats_label_days` | ins | days | reuse |
| `insights_stats_label_week` | ins | week | reuse |
| `insights_stats_label_weeks` | ins | weeks | reuse |
| `insights_stats_label_words` | ins | words | reuse |
| `insights_stats_label_wpm` | ins | WPM | reuse |
| `insights_stats_most_used_app_tagline` | ins | This is where your ideas come to life | reuse |
| `insights_stats_streak_daily_almost_fifty` | ins | Almost 50 days. Think about that. | reuse |
| `insights_stats_streak_daily_almost_hundred` | ins | Almost 100 days. The countdown is on. | reuse |
| `insights_stats_streak_daily_almost_month` | ins | Almost a full month. | reuse |
| `insights_stats_streak_daily_almost_two_weeks` | ins | Almost two weeks strong. | reuse |
| `insights_stats_streak_daily_almost_week` | ins | Almost a full week! | reuse |
| `insights_stats_streak_daily_beyond_year` | ins | Beyond a year of daily Flow. There are no words. | reuse |
| `insights_stats_streak_daily_compounding` | ins | Daily effort, compounding results. | reuse |
| `insights_stats_streak_daily_consistency` | ins | Consistency looks good on you. | reuse |
| `insights_stats_streak_daily_day_one` | ins | Day one — momentum begins. | reuse |
| `insights_stats_streak_daily_double_digits` | ins | Double digits. You're locked in. | reuse |
| `insights_stats_streak_daily_few_make_it` | ins | Few people make it this far. | reuse |
| `insights_stats_streak_daily_fifty_days` | ins | 50 days of non-stop Flow. Unreal. | reuse |
| `insights_stats_streak_daily_five_days` | ins | Five days — that's commitment. | reuse |
| `insights_stats_streak_daily_forty_days` | ins | Forty days. That's serious dedication. | reuse |
| `insights_stats_streak_daily_four_months` | ins | Four months straight. This is genuinely rare. | reuse |
| `insights_stats_streak_daily_four_weeks` | ins | Four weeks strong. Amazing. | reuse |
| `insights_stats_streak_daily_full_month` | ins | A full month. You showed up every single day. | reuse |
| `insights_stats_streak_daily_getting_solid` | ins | Your habit is getting solid. | reuse |
| `insights_stats_streak_daily_going_to_hundred` | ins | You're going to hit 100. It's inevitable. | reuse |
| `insights_stats_streak_daily_habits_thriving` | ins | Most habits don't survive this long. Yours is thriving. | reuse |
| `insights_stats_streak_daily_half_year` | ins | Half a year of daily Flow. We're in awe. | reuse |
| `insights_stats_streak_daily_half_year_sight` | ins | Half a year is within sight. | reuse |
| `insights_stats_streak_daily_halfway_thirty` | ins | Halfway to 30 — stay sharp. | reuse |
| `insights_stats_streak_daily_hundred_days` | ins | 100 days. You are a legend. Full stop. | reuse |
| `insights_stats_streak_daily_in_the_zone` | ins | You're in the zone. | reuse |
| `insights_stats_streak_daily_kickoff` | ins | Let's kick off a new streak with Flow! | reuse |
| `insights_stats_streak_daily_month_two` | ins | Going strong into month two. | reuse |
| `insights_stats_streak_daily_nearing_two_months` | ins | You're nearing 2 months of daily Flow! | reuse |
| `insights_stats_streak_daily_new_baseline` | ins | You're setting a new baseline. | reuse |
| `insights_stats_streak_daily_nice_rhythm` | ins | Nice rhythm building. | reuse |
| `insights_stats_streak_daily_nine_days` | ins | Nine days — impressive focus. | reuse |
| `insights_stats_streak_daily_nineteen_days` | ins | Nineteen days — keep the chain alive. | reuse |
| `insights_stats_streak_daily_one_fifty` | ins | 150 days. You're in a category of your own. | reuse |
| `insights_stats_streak_daily_one_week` | ins | One full week. Habit unlocked. | reuse |
| `insights_stats_streak_daily_one_year` | ins | One full year. You are Flow. | reuse |
| `insights_stats_streak_daily_over_four_months` | ins | Over four months straight. This is genuinely rare. | reuse |
| `insights_stats_streak_daily_over_hundred` | ins | Over 100 days and still showing up. | reuse |
| `insights_stats_streak_daily_part_of_you` | ins | You've made Flow a part of who you are. | reuse |
| `insights_stats_streak_daily_second_nature` | ins | This is becoming second nature. | reuse |
| `insights_stats_streak_daily_second_nature_long` | ins | Using Flow is second nature at this point. | reuse |
| `insights_stats_streak_daily_seventy_five` | ins | 75 days. Three-quarters of the way to 100. | reuse |
| `insights_stats_streak_daily_showing_up` | ins | Showing up daily pays off. | reuse |
| `insights_stats_streak_daily_six_weeks` | ins | Six weeks and counting. Unstoppable. | reuse |
| `insights_stats_streak_daily_strong_consistency` | ins | Strong consistency builds great results. | reuse |
| `insights_stats_streak_daily_thirty_days` | ins | 30 days straight. Legendary. | reuse |
| `insights_stats_streak_daily_three_days` | ins | Three days strong. | reuse |
| `insights_stats_streak_daily_three_months` | ins | Three months of Flow, every day. Jaw-dropping. | reuse |
| `insights_stats_streak_daily_three_weeks` | ins | Three weeks in. You're Flowing everywhere now. | reuse |
| `insights_stats_streak_daily_tomorrow_big` | ins | Tomorrow's a big one… | reuse |
| `insights_stats_streak_daily_twelve_days` | ins | Twelve days of real progress. | reuse |
| `insights_stats_streak_daily_twenty_days` | ins | Twenty days. Seriously impressive. | reuse |
| `insights_stats_streak_daily_twenty_five` | ins | 25 days — elite consistency. | reuse |
| `insights_stats_streak_daily_two_days` | ins | Two days in a row. Keep it rolling. | reuse |
| `insights_stats_streak_daily_two_months` | ins | Two months straight. You're in a different league. | reuse |
| `insights_stats_streak_daily_two_weeks` | ins | Two weeks straight. Nice work! | reuse |
| `insights_stats_streak_weekly_consistency` | ins | Consistency is your superpower. | reuse |
| `insights_stats_streak_weekly_double_digits` | ins | Double digits, going strong. | reuse |
| `insights_stats_streak_weekly_fifteen` | ins | 15 is Flow's favorite number. | reuse |
| `insights_stats_streak_weekly_flow_legend` | ins | You are a Flow legend. | reuse |
| `insights_stats_streak_weekly_flow_master` | ins | You are a Flow master. | reuse |
| `insights_stats_streak_weekly_four_months` | ins | Four months? A true Flow god. | reuse |
| `insights_stats_streak_weekly_good_habit` | ins | We see a good habit taking shape! | reuse |
| `insights_stats_streak_weekly_great_start` | ins | You are off to a great start! | reuse |
| `insights_stats_streak_weekly_habits_forming` | ins | Habits forming, results showing. | reuse |
| `insights_stats_streak_weekly_living_legend` | ins | Becoming a living legend. | reuse |
| `insights_stats_streak_weekly_on_fire` | ins | You are truly on fire. | reuse |
| `insights_stats_streak_weekly_one_month` | ins | One month straight? Amazing. | reuse |
| `insights_stats_streak_weekly_tell_friends` | ins | Time to get your friends in on this. | reuse |
| `insights_stats_streak_weekly_three_months` | ins | Three months of solid productivity. | reuse |
| `insights_stats_streak_weekly_three_weeks` | ins | Three weeks in, getting stronger. | reuse |
| `insights_stats_streak_weekly_two_weeks` | ins | Two weeks down, many more ahead | reuse |
| `insights_stats_streak_weekly_unstoppable` | ins | You are unstoppable. | reuse |
| `insights_stats_streak_weekly_welcome` | ins | Welcome! | reuse |
| `insights_stats_title_average_speed` | ins | Average Speed | reuse |
| `insights_stats_title_daily_streak` | ins | Daily Streak | reuse |
| `insights_stats_title_most_used_app` | ins | Most Used App | reuse |
| `insights_stats_title_total_apps_flowed` | ins | Total Apps Flowed | reuse |
| `insights_stats_title_total_apps_used` | ins | Total Apps Used | reuse |
| `insights_stats_title_weekly_streak` | ins | Weekly Streak | reuse |
| `insights_stats_wpm_tagline_faster_90` | ins | Faster than 90% of typers | reuse |
| `insights_stats_wpm_tagline_faster_95` | ins | Faster than 95% of typers | reuse |
| `insights_stats_wpm_tagline_faster_97` | ins | Faster than 97% of typers | reuse |
| `insights_stats_wpm_tagline_top_1` | ins | Top 1% of all Flow users | reuse |
| `insights_stats_wpm_tagline_top_2` | ins | Top 2% of all Flow users | reuse |
| `insights_stats_wpm_tagline_top_3` | ins | Top 3% of all Flow users | reuse |
| `insights_stats_wpm_tagline_top_5` | ins | Top 5% of all Flow users | reuse |
| `insights_stats_wpm_tagline_use_more` | ins | Use Flow more to see your WPM improve | reuse |
| `insights_stats_wpm_value_display` | ins | {{value}} words per minute {{emoji}} | reuse |
| `insights_tab_leaderboard` | ins | Leaderboard | drop |
| `insights_tab_your_usage` | ins | Your usage | reuse |
| `insights_tab_your_voice` | ins | Your voice | reuse |
| `insights_total_apps_used` | ins | Total Apps Used | reuse |
| `insights_total_words_compare_last_month` | ins | {{current}} words compared to {{previous}} words this time last month | reuse |
| `insights_total_words_comparison_book_chapter_plural` | ins | book chapters | reuse |
| `insights_total_words_comparison_book_chapter_singular` | ins | book chapter | reuse |
| `insights_total_words_comparison_college_essay_plural` | ins | college essays | reuse |
| `insights_total_words_comparison_college_essay_singular` | ins | college essay | reuse |
| `insights_total_words_comparison_complete_book_plural` | ins | complete books | reuse |
| `insights_total_words_comparison_complete_book_singular` | ins | complete book | reuse |
| `insights_total_words_comparison_cover_letter_plural` | ins | cover letters | reuse |
| `insights_total_words_comparison_cover_letter_singular` | ins | cover letter | reuse |
| `insights_total_words_comparison_dr_seuss_book_plural` | ins | Dr. Seuss books | reuse |
| `insights_total_words_comparison_dr_seuss_book_singular` | ins | Dr. Seuss book | reuse |
| `insights_total_words_comparison_email_newsletter_plural` | ins | email newsletters | reuse |
| `insights_total_words_comparison_email_newsletter_singular` | ins | email newsletter | reuse |
| `insights_total_words_comparison_folk_tale_plural` | ins | folk tales | reuse |
| `insights_total_words_comparison_folk_tale_singular` | ins | folk tale | reuse |
| `insights_total_words_comparison_instruction_manual_plural` | ins | instruction manuals | reuse |
| `insights_total_words_comparison_instruction_manual_singular` | ins | instruction manual | reuse |
| `insights_total_words_comparison_meme_caption_plural` | ins | meme captions | reuse |
| `insights_total_words_comparison_meme_caption_singular` | ins | meme caption | reuse |
| `insights_total_words_comparison_news_article_plural` | ins | news articles | reuse |
| `insights_total_words_comparison_news_article_singular` | ins | news article | reuse |
| `insights_total_words_comparison_podcast_season_plural` | ins | podcast seasons | reuse |
| `insights_total_words_comparison_podcast_season_singular` | ins | podcast season | reuse |
| `insights_total_words_comparison_postcard_plural` | ins | postcards | reuse |
| `insights_total_words_comparison_postcard_singular` | ins | postcard | reuse |
| `insights_total_words_comparison_short_film_script_plural` | ins | short film scripts | reuse |
| `insights_total_words_comparison_short_film_script_singular` | ins | short film script | reuse |
| `insights_total_words_comparison_thank_you_note_plural` | ins | thank-you notes | reuse |
| `insights_total_words_comparison_thank_you_note_singular` | ins | thank-you note | reuse |
| `insights_total_words_comparison_tweet_plural` | ins | tweets | reuse |
| `insights_total_words_comparison_tweet_singular` | ins | tweet | reuse |
| `insights_total_words_comparison_wedding_vow_plural` | ins | wedding vows | reuse |
| `insights_total_words_comparison_wedding_vow_singular` | ins | wedding vow | reuse |
| `insights_total_words_dictated` | ins | Total Words Dictated | reuse |
| `insights_total_words_fun_fact_empty` | ins | You've written nothing yet—start dictating! | reuse |
| `insights_total_words_fun_fact_template` | ins | You've written {{count}} {{object}}! | reuse |
| `insights_total_words_percent_this_month` | ins | {{percent}}% this month | reuse |
| `insights_total_words_words_count_one` | ins | {{display}} word | reuse |
| `insights_total_words_words_count_other` | ins | {{display}} words | reuse |
| `insights_try_again` | ins | Try again | reuse |
| `insights_usage_category_ai` | ins | AI prompts | reuse |
| `insights_usage_category_document` | ins | documents | reuse |
| `insights_usage_category_email` | ins | emails | reuse |
| `insights_usage_category_other` | ins | other tasks | reuse |
| `insights_usage_category_personal_messaging` | ins | personal messages | reuse |
| `insights_usage_category_work` | ins | work messages | reuse |
| `insights_usage_load_error` | ins | Something went wrong loading your insights. | reuse |
| `insights_value_dash` | ins | — | reuse |
| `insights_words_per_minute_with_count_one` | ins | {{display}} word per minute | reuse |
| `insights_words_per_minute_with_count_other` | ins | {{display}} words per minute | reuse |
| `insights_wpm_words_per_minute` | ins | Words per minute | reuse |
| `insights_wpm_words_per_minute_tooltip` | ins | Compared to global typing speeds | reuse |
| `hub_dictation_stats_label_day_streak` | hub | day streak | reuse |
| `hub_dictation_stats_label_total_words` | hub | total words | reuse |
| `hub_dictation_stats_label_week_streak` | hub | week streak | reuse |
| `hub_dictation_stats_label_wpm` | hub | wpm | reuse |
| `hub_top_apps_empty_state` | hub | Start using Flow in any app to see your top apps here | reuse |
| `hub_top_apps_loading` | hub | Loading... | reuse |
| `hub_top_apps_title` | hub | `Get back into your <flow>Flow</flow>` | reuse |

### Dropped domains (summarised, not listed key by key)

Every key below belongs to a feature the rebuild does not have. Counts are exact; examples are verbatim. A summarised domain that the rebuild later adds back needs new wording anyway (local-only, no account). Rows marked "optional" are features a later version could add locally.

| Feature | Count | Key prefixes (as matched) | Rebuild | Examples |
|---|---|---|---|---|
| Transactional email templates | 2 | `degraded_network_work_*` | drop | Hi team,\n\nWispr Flow, my dictation app, says our network settings limit its performance. Could you review t… / IT request: Wispr Flow on our network |
| Meeting imports from Granola and Otter (optional: Granola import reads the locally installed Granola app [U]; Otter is server-side) | 143 | `settings_data_granola_*`, `hub_granola_import_*`, `hub_import_modal_*`, `hub_otter_import_*`, `hub_granola_csv_*`, `hub_import_source_*`, `hub_import_awaiting_*`, `settings_data_otter_*` | drop | Import your Granola CSV export to finish. / Finish import |
| Meeting-note sharing: share dialog, link visibility, default note visibility | 91 | `share_note_recipients_*`, `share_note_visibility_*`, `hub_share_scope_*`, `hub_shared_notes_*`, `share_note_error_*`, `settings_data_default_*`, `hub_shared_note_*`, `share_note_role_*` … | drop | Anyone with the link / The default sharing permission when you copy a link to a Notetaker meeting note. Transcripts are only visib… |
| Sign-in, account profile, SSO/IP allow-list, account deletion | 67 | `settings_account_confirm_*`, `hub_account_referral_*`, `ip_allowlist_blocked_*`, `settings_account_profile_*`, `failed_sign_in_*`, `settings_account_first_*`, `settings_account_last_*`, `settings_account_name_*` … | drop | Back to account / This will delete all your data, memory, and dictionary, locally and on our servers. |
| Plans, billing, trials, Flow Pro, word limits, student plans | 578 | `hub_sidebar_cta_*`, `settings_plans_feature_*`, `hub_student_referral_*`, `hub_trial_end_*`, `hub_typing_location_*`, `trial_opt_in_*`, `settings_plans_notetaker_*`, `settings_plans_trial_*` … | drop | {{count}} days / Add billing info within {{dayLabel}} to keep access to your team and {{planLabel}} features. |
| Referrals and gifts | 128 | `hub_referral_invite_*`, `hub_referral_modal_*`, `hub_referral_past_*`, `hub_referral_apply_*`, `referral_step_reward_*`, `hub_sidebar_referral_*`, `referral_step_signup_*`, `referral_badge_limited_*` … | drop | referral icon / Unlimited access for 1 month |
| Teams, organisations, admin policies, leaderboards, shared team dictionary/snippets | 429 | `settings_team_create_*`, `settings_team_member_*`, `solo_team_invite_*`, `settings_invite_user_*`, `settings_team_orphan_*`, `orphan_join_team_*`, `settings_contact_admin_*`, `hub_modal_domain_*` … | drop | Contact {{teamName}} team admins / Contact team admins |
| HIPAA, cloud sync / cloud storage, server-side data export, internal data sharing | 133 | `settings_data_export_*`, `hub_cloud_sync_*`, `hub_notes_cloud_*`, `settings_hipaa_baa_*`, `cloud_sync_gate_*`, `settings_data_hipaa_*`, `settings_data_cloud_*`, `settings_data_privacy_*` … | drop | Stores your dictation data, including transcripts, audio, and dictation history on Wispr servers, to enable… / Dictation Cloud Storage is locked off because HIPAA BAA is signed. |
| Cloud connectors (Gmail, Slack, Notion, GitHub, Linear, LinkedIn), MCP server, mobile app, email preferences | 232 | `settings_experimental_email_*`, `settings_testing_feature_*`, `settings_connectors_disconnect_*`, `settings_testing_item_*`, `hub_history_internal_*`, `settings_connectors_button_*`, `settings_connectors_description_*`, `settings_connectors_info_*` … | drop | Connector actions / Connected, but unavailable because your organization turned off this connector. |
| Support/feedback forms and sales contact (server-backed) | 44 | `help_button_placeholder_*`, `hub_contact_toast_*`, `help_button_toast_*`, `help_button_dialog_*`, `hub_contact_option_*`, `hub_contact_placeholder_*`, `hub_contact_report_*`, `hub_contact_request_*` … | drop | Your feedback helps us perfect the Flow experience. / Send a message to the Flow team |
| Marketing: testimonials, social proof, mic-buying quiz, voice-profile persona, insights sharing, status-page incidents, degraded-network IT emails | 390 | `mic_quiz_v2_*`, `insights_voice_profile_*`, `mic_quiz_v1_*`, `about_yourself_testimonial_*`, `social_proof_testimonial_*`, `insights_share_title_*`, `hub_banner_microphone_*`, `incident_slow_dictation_*` … | drop | Find the right mic for you → / Dismiss network alert |
| Hardware integrations (Jabra headsets, Logitech MX Master setup), Focus Mode, Windows-only | 25 | `settings_experimental_blocked_*`, `settings_hotkey_dialog_*`, `windows_mic_privacy_*`, `settings_experimental_add_*`, `settings_experimental_focus_*`, `settings_experimental_jabra_*`, `settings_experimental_added_*`, `settings_experimental_failed_*` … | drop | URL already in blocked list / Failed to load running apps |


---

## Part B. Hard-coded strings (not in i18n)

### Info.plist usage descriptions [R-plist]

| Key | English (main app `com.electron.wispr-flow`) | Rebuild |
|---|---|---|
| `NSMicrophoneUsageDescription` | Allow Wispr Flow microphone access to transcribe your speech. | reuse |
| `NSAudioCaptureUsageDescription` | Wispr Flow needs to access your computer's audio to take notes during meetings. | reuse (Notetaker system-audio capture) |
| `NSCameraUsageDescription` | This app needs access to the camera | drop |
| `NSBluetoothAlwaysUsageDescription` | This app needs access to Bluetooth | drop |
| `NSBluetoothPeripheralUsageDescription` | This app needs access to Bluetooth | drop |
| `CFBundleURLSchemes` | `wispr-flow` (URL scheme, not shown) | rewrite (own scheme) |

The Swift helper (`com.electron.wispr-flow.accessibility-mac-app`) adds `NSBluetoothAlwaysUsageDescription` = "Allow Wispr Flow to connect to your BLE mic ring for hands-free dictation." (drop: BLE ring hardware) and repeats the audio-capture string.

### System dialogs (main process) [B-main]

| Dialog | Title | Message / detail | Buttons | Rebuild |
|---|---|---|---|---|
| macOS too old (launch) | Unsupported MacOS Version | Wispr Flow requires MacOS 12.0 or later. Please upgrade your operating system to continue. | OK | rewrite (own minimum macOS) |
| Intel build on Apple silicon (launch) | Incorrect App Version | You are running the Intel version of Wispr Flow on an Apple Silicon Mac. Please download the Apple Silicon version from wisprflow.ai for better performance. | OK | rewrite (universal build makes it moot) |
| Not in /Applications (launch) | Move Flow to Applications folder | Flow needs to be in the Applications folder to run. | OK | reuse |
| Update while dictating or recording | Restart to update? | message: `` A ${n} is in progress `` · detail: `` Restarting to update will quit Wispr Flow and end the current ${n}. Any audio that hasn't been saved yet may be lost. `` (`n` = "dictation" or "meeting recording") | Cancel · Restart anyway | reuse |
| Update ready, idle-restart ceiling | `menus_update_ceiling_title` | `menus_update_ceiling_message` / `menus_update_ceiling_detail` | `menus_update_ceiling_later` · `menus_update_ceiling_restart` | reuse |
| Uncaught exception | A JavaScript error occurred in the main process / `` A JavaScript error occurred in the ${r} process `` | stack trace | — | drop (Electron-specific) |
| Windows only | Unsupported Windows Architecture | Wispr Flow requires x64 architecture. Please use a compatible Windows device to continue. | OK | drop |

### Window titles (main process `BrowserWindow`) [B-main]

Not shown in a title bar; they appear in Mission Control, the Window menu and accessibility tools.

| Window (renderer) | Title | Rebuild |
|---|---|---|
| hub | Flow Hub | reuse |
| status (floating flow bar) | Flow Status Indicator | reuse |
| contextMenu (bar menu and pop-overs) | Flow Context Menu | reuse |
| scratchpad | Scratchpad | reuse |
| accessibility_drop (drag-to-allow panel) | Accessibility | reuse |
| meeting_recorder (meeting window and notepad) | Meeting Recorder | reuse |
| meeting_ax_inspector | Meeting AX Inspector | drop (internal) |

### Menus without i18n keys [B-main]

| Where | English | Rebuild |
|---|---|---|
| Tray icon tooltip | Wispr Flow | reuse (brand) |
| Application menu, first item title | Wispr Flow | reuse (brand) |
| App menu items using system roles (macOS-localised) | Hide Others · Show All · Minimize · Close · Quit | reuse |
| Dock menu | `menus_start_notetaker` · `menus_open_notetaker` (when Notetaker is available) · `menus_open_wispr_flow` | reuse |
| Windows taskbar jump list | Quit Wispr — "Quit Wispr Flow application" | drop |

### In-app announcement cards (notification inbox and bar cards) [B-main]

A static table in the main process gives each local announcement a type (Announcement, Achievement, Referral), a badge and a call-to-action. The cards below carry hard-coded English. Most other milestone and streak cards (word counts 314 … 1.5M, streaks of 2–52 weeks, trial and team cards) carry only a CTA and badge here. Their title and body come from the server [U].

| Card key | Title | Body | CTA | Badge | Rebuild |
|---|---|---|---|---|---|
| `OnboardingComplete` | Hello from Flow! You're in. | We're here to turn your voice into beautifully formatted, ready-to-send text in real time. Have you seen our workflows? | Workflows | Welcome | reuse |
| `YayFirstOutsideDesktop` | You just did your first Flow dictation! | As you use Flow over the next few weeks, it'll soon become second-nature and before you know it, you'll be using it everywhere. Check out our workflows. | See use cases | Milestone | reuse |
| `DictionaryItems10` | You just added your 10th dictionary word! 📝 | Flow is learning your language. Each word you add makes dictation more accurate. | Open dictionary | Dictionary | reuse |
| `DictionaryItems50` | 50 custom words added to your dictionary! 🎯 | You're building a personalized vocabulary that makes Flow work exactly how you speak. | Open dictionary | Dictionary | reuse |
| `DictionaryItems100` | 100 dictionary words and counting! 🚀 | Your custom dictionary is now a powerhouse—Flow knows your jargon, shortcuts, and unique terms. | Open dictionary | Dictionary | reuse |
| `BillingUpgradeCompletePro` | Welcome to Flow Pro! Here's what's unlocked. | You're now part of a growing community that's rethinking how we work—where voice lets technology move with you. | Learn more | Pro | drop |
| `OnboardingDay3` / `OnboardingDay5` | (server) | (server) | Help Center / Workflows | Tip | rewrite |
| `YayWordCount*` (15 thresholds), `StreakWeeks*` (2, 4, 12, 26, 39, 52) | (server) | (server) | See stats | Milestone / Streak | rewrite (write local copy) |

Other CTA and badge literals in the same table (all drop): Upgrade now · Accept request · Accept Invite · View stats · Redeem now · See Referrals · Invite others · Request · Create a team · Invite them · Get a free month · Give unlimited words · Invite a teammate; badges Trial ending · Team billing · New Team Member · Referral · Team.

### Flow bar and pop-over literals [B-renderer]

| Where | English | Rebuild |
|---|---|---|
| Transform "done" pill label (status) | `Done. ` (trailing space, followed by `hub_polish_processing_see_changes`) | reuse |
| Settings-change confirmation card (Instruct Mode changed a setting) | Deny · Accept changes | reuse |
| Button spinner accessible label (all windows) | Loading | reuse |
| Bar notification when the Now Playing helper is missing (developer builds) | Now Playing unavailable — "Install nowplaying-cli: brew install nowplaying-cli" | drop |
| Trial-ending hero (status) | "Your Flow " + Pro badge + "trial ends tomorrow" | drop |
| Fetch-links palette, link kinds (scratchpad/contextMenu) | Google Doc · Google Drive file · Google Calendar event · Google Meet · Gmail thread · Notion page · Figma file · Linear issue · GitHub · Zoom meeting | reuse (labels for recognised URLs) |
| Scratchpad editor | Title · Failed to load image · Delete image · Toggle section · Cancel · Yes, delete it | reuse |
| Flow bar menu pop-overs (contextMenu) | Configure · Done | reuse |

### Keycap labels (shortcut keycaps in onboarding and the shortcuts dialog) [B-renderer]

macOS keycaps draw a symbol in one corner and a word in the opposite corner. Right-hand modifiers mirror the corners.

| Key id | Symbol | Word | Notes |
|---|---|---|---|
| `fn` | fn | (globe icon) + visually hidden "Fn Key Globe" | |
| `ctrl` / `ctrl_r` | ⌃ | control | |
| `opt` / `opt_r` | ⌥ | option | |
| `cmd` / `cmd_r` | ⌘ | command | |
| `shift` / `shift_r` | — | shift | |
| `alt` / `alt_r` | — | Alt / `Alt →` | |
| other | — | the key name, upper-cased when it is one character | |

Windows keycaps (Ctrl, Alt, Shift, Caps Lock, Windows logo, `→` for right-hand keys) are dropped.

### Onboarding mock-ups and examples [B-renderer]

| Where | English | Rebuild |
|---|---|---|
| Accessibility step: mock System Settings sidebar | Privacy & Security · Accessibility · Lock Screen · Touch ID & Password · Users & Groups · Internet Accounts · Game Center · Wallet & Apple Pay · Keyboard · Trackpad · Printers & Scanners | reuse (illustration text) |
| Accessibility step: mock authentication sheet | Privacy & Security — "Privacy & Security is trying to unlock system settings." — "Touch ID or enter your password to allow this." | reuse |
| Microphone step: mock system prompt | Wispr Flow needs access to your microphone to transcribe your speech. | reuse |
| Intro step | Flow turns your voice into clean, formatted text in every app on your computer. No integrations needed. · Start Setup · every app | reuse |
| About-you step | Which of these sound like you? | reuse |
| Language step, Hinglish tile | Hindi · Hinglish · Main kal office aaunga | reuse |
| Vibe-coding setup dialog | Cmd+Shift+P · Toggle Screen Reader Accessibility Mode | reuse |
| Appearance picker | Theme · Light · Dark · System | reuse |

### Dictionary and snippet import errors (main process) [B-main]

| English | Rebuild |
|---|---|
| No dictionary items found in file | reuse |
| No valid dictionary items found in file | reuse |
| No snippets found in file | reuse |
| No valid snippets found in file | reuse |
| `` Item at index ${t} is not an object `` | reuse |
| `` Item at index ${t} is missing required fields (name, text) `` | reuse |
| `` Item at index ${t} has invalid field types `` | reuse |
| `` Item at index ${t} has empty name `` | reuse |
| `` Item at index ${t} has empty snippet `` | reuse |
| `` Item at index ${t} name exceeds ${max} characters `` | reuse |
| `` Item at index ${t} snippet exceeds ${max} characters `` | reuse |

### Native helper and permission guide [B-native]

| Where | English | Rebuild |
|---|---|---|
| `FlowPermissionGuide.app` (macOS 26+ drag-to-allow overlay over System Settings) | "… to the list above to allow …", assembled as `Drag {app} to the list above to allow {permission}` with permission names "Accessibility" or "Screen Recording". The prefix is not a C-string; it is probably an inline Swift literal [U]. | reuse |
| Swift helper `MainMenu.nib` (never visible: `LSUIElement`) | Wispr Flow Helper · About Wispr Flow Helper · Preferences · Services · Hide Wispr Flow Helper · Hide Others · Show All · Quit Wispr Flow Helper · Main Menu | drop |

The helper's other C-strings are log and diagnostic messages, not UI.

### Use-case nudges (flow bar growth tips) [B-renderer]

`renderer/status/index.js` holds a hard-coded table of 38 use cases. Each has an `id`, a category ("Relationship / Identity-Based" for ids 1–12, "Job-specific" for 13–38), a `title`, a `notificationTitle`, a `notificationDescription` with `{action}` / `{hotkey}` slots, and an `appList` of bundle ids. The same titles are repeated as hard-coded literals in the main process. **Rebuild: drop** (growth marketing). Examples:

| id | title | notificationTitle | notificationDescription |
|---|---|---|---|
| 1 | Write better prompts in your AI IDE | Use Flow to write code and prompt faster | {action} {hotkey} and dictate in your IDE with correctly formatted variables + file names. |
| 4 | Clear your email inbox | Use Flow to clear your inbox | {action} {hotkey} and dictate perfectly formatted emails without typing. |
| 13 | Draft content and captions | Use Flow to write drafts and content | {action} {hotkey} and dictate drafts or ideas without typing. |

A parallel short-label list ("better prompts", "to-do lists", "email inbox", …) and two descriptions ("Record ideas, notes, or next steps instantly before they slip away with your voice." / "Think out loud and let Flow structure your ideas into clear, readable writing automatically.") belong to the same feature.

### Internal / testing panel (summarised) [B-renderer]

About 150 English literals in `renderer/hub/index.js` belong to the hidden internal settings page (`settings_sidebar_page_internal` / `testing`). Examples: Sandbox User Mode, Candidate ASR model routing, Internal data sharing, "Share transcripts for model training. Toggle with opt+P. Flow bar turns purple when active.", Instruct mode model, Show flow bar debug outlines, Refresh feature flags, Copy session token, Simulate past-due dunning, BLE Mic Ring, Sync WebSocket events. **Rebuild: drop.** The rebuild may add its own developer toggles; none are carried over.

Also hard-coded in `hub` and dropped:

- Testimonial author titles (e.g. "CEO of Superhuman", "CEO Product Hunt").
- The microphone-buying quiz answers (Wired Headphones, Bluetooth Earbuds, Headset, Clip-on Lav Mic, Podcast Mic, Gooseneck Mic, "Mostly private, quiet spaces", …).
- "Where did you hear about us?"
