# Orbit release notes

## 1.5.1 — 2026-08-08

### Fixed

- A fullscreen Chromium window on another Space now stays reached. `v1.5.0` activated the process one beat after the Window-menu press, which reasserted Chrome's old fullscreen window whenever the switch started inside Chrome itself. Orbit now activates the process only when the switch originated in a different app, and hides the page currently under Orbit instead of an untitled browser helper surface.
- A Chromium Window-menu action that times out is no longer treated as a definite failure. Accessibility actions can be accepted before the target app finishes replying; running the AppleScript fallback in that state reactivated the old fullscreen Space and undid the pending switch. The menu item now gets its own timeout, and an indeterminate-but-possibly-accepted action is preserved.
- Quick switch never reactivates the window already under Orbit. A frontmost app participates only when Orbit resolves a different sibling window synchronously; otherwise the target falls back to the previous application.
- Accessibility round trips can no longer stall system-wide keyboard input. `AXUIElementSetMessagingTimeout` is per object, so the existing 0.4-second guards only ever covered the first hop — the window, menu and menu-item objects Orbit then walks kept the framework default of several seconds each, on the main thread the event tap's callback also runs on. Orbit now installs one process-wide ceiling; the Window-menu press still asks for more, deliberately.
- The Window-menu search is bounded. It stops after the few menus at the right end of the bar, where the Window menu conventionally sits, and skips any menu too large to be one — an unrecognised Window menu used to mean probing History's hundreds of rows one synchronous round trip at a time.
- A late answer to the Automation dialog no longer switches apps. That dialog blocks the Apple Events fallback for as long as it stays on screen, and the fallback activation that followed could arrive minutes after the person had moved on. Fallback activation now only runs while the switch is still what they are doing.
- The current app's card no longer disappears without Screen Recording permission. Identifying the window you are looking at required a title, which reads as `nil` for every window when that permission is absent — taking the whole "switch to another window of the same app" path down with it. The title requirement now follows the permission, as it already did elsewhere.
- Settings re-reads the interface language when it reopens, so a language changed from System Settings in the meantime no longer shows a stale entry in the picker.
- Arrowing into a neutral ring skips Orbit's own card whenever a real switch target exists, matching what Quick switch already preselected. Confirming the Orbit card only dismisses the ring, so the two entry paths disagreeing meant releasing the trigger did different things depending on which one placed the highlight.

### Changed

- The Welcome page now appears on launch by default, with a clear opt-out both on the page itself and in Settings. This keeps Orbit's hold-to-switch interaction discoverable after the first run without forcing it on people who have already learned it.
- When Window Preview is enabled but Screen Recording access is unavailable, the menu bar icon and status menu now identify the missing access and provide a direct route to the relevant System Settings pane.
- The highest-value recent destination now has a stable 12-o'clock anchor. If the current app has another actionable window, that window-aware card comes first and its carousel defaults to the previously viewed sibling; otherwise the previous app remains first. Cards continue in one direction with or without Window Preview, and either vertical arrow enters a neutral ring at that same target.
- Opening behavior is now an explicit Settings choice: **Start at Cancel** is the safe default, while **Quick switch** preselects the 12-o'clock target and switches on release. General settings remains shorter and task-oriented; Window Preview controls live in Appearance, advanced explanations use native hover help, and persistent footer text appears only when alphabetical arrangement needs clarification.
- Automation is no longer presented as a required setup step. Orbit's Accessibility-based window paths handle normal switching; macOS requests Automation only if Orbit reaches its rare Apple Events fallback for an exact window switch. See `docs/decisions/ADR-007-contextual-automation-permission.md`.

### Removed

- The Settings › General Automation pre-authorization button, its per-app status list, the background permission scan behind them, and the matching strings in all 11 bundled languages. The Apple Events fallback and `NSAppleEventsUsageDescription` remain.
- Dead code: an accessibility-prompt helper no caller used, one post-switch diagnostic that only wrote to the log, and two localization keys unreferenced since the first commit.

### Validation

- The test targets contain 58 `OrbitTests` tests and 2 `OrbitUITests` methods; the unit target passes with 0 failures, and `scripts/ci_validate.sh` passes.
- A clean Debug build produces no Swift warnings, and `plutil -lint` passes for all 11 bundled localizations.
- The installed `/Applications/Orbit.app` was manually verified across fullscreen Chrome Spaces and into a normal Chrome window; each selected window became on-screen, including the formerly failing fullscreen target that reports a misleading successful `AXRaise` before the Window-menu fallback completes the Space switch.

## 1.5.0 — 2026-08-07

### Fixed

- Selecting a specific window in the preview carousel now lands on that window, including one buried under the app's other windows. Windows are re-identified by title *and* frame instead of an exact-title match — ScreenCaptureKit and Accessibility report different title formats for the same window, so the old equality test silently failed for browsers.
- The chosen window is now focused *before* the application is activated. macOS follows an application onto the Space its main window lives on, so naming the window first is what makes a switch to a fullscreen window's Space actually land there; the old order could only reorder windows on the Space it had already arrived at.
- Activating a chosen window no longer restores the app's own front-to-back window order on top of it, and a minimized target window is restored before being raised.
- A failed raise now reports failure instead of success, so the plain app-activation fallback runs instead of leaving the wrong window in front.

- A fullscreen Chromium window on another Space is now reachable. Chromium implements the scripted window reorder without making the window key, so a switch used to stop on whichever Space the app was last active on. Orbit now presses the matching entry in the app's own Window menu — which Chromium does expose to Accessibility, and which performs a real makeKeyAndOrderFront — then activates the app one beat later so macOS follows the key change to the right Space in a single hop. The Window menu is recognised by its contents (it is the only menu listing all of the app's window titles), never by its localized title.

- The app you are currently in is reachable again when it has more than one window. The ring used to drop the frontmost app's card entirely, so standing in one Chrome window put every other Chrome window out of reach. That card now appears whenever the app owns more than one window — its only purpose being to reach the others — and its preview hides the window you are looking at. An app with a single window still has no card, since selecting it would only return you where you already are.

### Added

- Apple Events fallback for apps whose windows Accessibility cannot see. Chromium-based apps (Chrome, Edge, Brave …) expose no windows to the Accessibility API at all, so Orbit now asks such an app directly, over Apple Events, to bring the chosen window forward. First use prompts for the Automation permission; declining it degrades gracefully to plain app activation — the behaviour Orbit always had.
- The bundle now declares `NSAppleEventsUsageDescription` for the Automation prompt.
- Settings › General gains a one-shot Automation pre-authorization button. The permission is per target app and macOS only asks on first contact, which used to interrupt the first switch into each Chromium-based app with a dialog; the button walks the running apps that will need the fallback (real windows, none visible to Accessibility) and fronts all of those prompts now. Localized in all 11 bundled languages.

### Validation

- The test targets now contain 46 `OrbitTests` tests and 2 `OrbitUITests` methods, including new unit coverage for cross-framework title matching (with real Chrome title pairs), frame-tolerance boundaries, AppleScript title escaping, Window-menu recognition, current-app card eligibility, current-window hiding, pre-authorization candidate selection, and `AEDeterminePermissionToAutomateTarget` status mapping.
- Both activation paths were verified against real window stacks via `CGWindowListCopyWindowInfo` z-order: the Accessibility path raised the bottom of three Finder windows, and the Apple Events path raised the bottom of five Chrome windows.

## 1.4.1 — 2026-08-07

### Changed

- The downloadable release is now a verified Universal 2 archive containing both `arm64` and `x86_64`, while the existing `v1.4.0` tag remains unchanged.
- The release pipeline now checks architecture, metadata, checksums, and test counts before publishing.
- The Xcode project version is now `1.4.1`, build `4`.

### Validation

- The source contains 36 `OrbitTests` tests and 2 `OrbitUITests` methods; the unit test target passed in CI.
- The published ZIP and SHA-256 file were generated from the latest `main` commit.

## 1.4.0 — 2026-08-07

### Added

- Settings now includes an interface-language picker with System plus 11 bundled locales: English, Simplified Chinese, Traditional Chinese, Japanese, Korean, German, French, Russian, Danish, Norwegian Bokmål, and Esperanto.
- The ring uses recent activation history to choose its visible app set, with a preference for Recently used or By name card order.
- An optional recent-app preselection preference makes summon-and-release behave like Command-Tab; it remains off by default for a safe no-op release.
- Preview size is configurable from 70% to 150%.
- The first-launch Welcome page now uses the Orbit app icon and a visual three-step walkthrough for holding Option, choosing an app, and releasing to switch.
- The README now presents the standalone App Intro artwork and a refreshed set of product screenshots.

### Changed

- Window previews capture from the display where Orbit was summoned, preserving the intended sharpness across mixed-resolution displays.
- A pending summon is canceled when another key, mouse button, or scroll gesture arrives before the hold completes.
- Preview capture now stops once the carousel is full instead of capturing every window an app has open. An app with twenty windows no longer pays twenty captures for six thumbnails inside the pause between the summon and the panel appearing.
- Both READMEs, ADR-001, and the source comments now describe the center hub as it behaves: it performs the action it displays — Cancel with nothing selected, Confirm with an app selected.
- The ring track, center hub, backdrop, card material, card size, placement, and preview layout now share a more balanced visual system.

### Fixed

- Escape or a hub click can no longer discard an accepted file drop. While a drop's URLs are still being read, a cancel is recorded and applied once the file operation settles, instead of releasing the view model that owns it.
- A failed move to the Trash, or an AirDrop macOS will not offer, is now reported on the hub instead of ending in silence. Every dropped file is attempted even when an earlier one fails.
- A failed language restart leaves the running Orbit alone. The old instance now terminates only after the new one has actually launched, and the settings window says so when it has not.
- A summon canceled before the hold completes no longer leaves Orbit in a stale interaction state.

### Validation

- The full clean test suite contains 36 `OrbitTests` tests and 2 `OrbitUITests` tests; the 36 unit tests passed with 0 failures.
- Release artifacts are Universal 2 (`arm64` + `x86_64`) and are checked before publishing.
- The release build is marketing version `1.4.0`, build `3`.

## 1.3.0 — 2026-08-06

### Added

- Orbit can appear as an optional special card in the app ring.
- Dragging the Orbit card to the center safely requests a normal quit for ordinary apps confirmed to have no open windows.
- The right-side preview now explains empty, unavailable, permission-required, loading, and Orbit states.
- The ring now has an optional circular backdrop with a separate appearance color control.
- Appearance settings now include a live preview for the ring backdrop and its material/card styling.

### Fixed

- Orbit cleanup no longer closes the ring while the trigger key is still held; releasing the trigger remains the intentional dismissal action.
- File deletion and AirDrop now follow the same trigger-key lifetime, including asynchronous file URL loading.
- Finder and Orbit are excluded from the windowless-app cleanup candidates.
- The AirDrop center state now uses Orbit’s ivory and burgundy palette instead of the previous blue treatment.
- Small app groups now use a tighter, more balanced fan while preserving the full preview width.
- The ring and preview now share a centered two-column layout with consistent spacing and screen margins.

### Validation

- Release build succeeds and the app signature verifies successfully.
- At release time, the test run was attempted but could not complete because CoreSimulatorService became unavailable in the build environment; subsequent validation is recorded in the `1.4.0` section above.
