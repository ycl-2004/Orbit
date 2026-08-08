# Orbit release notes

## 1.5.0 — 2026-08-07

### Fixed

- Preselecting the previous app now skips the frontmost app even when that app keeps a special ring card for its other windows. This restores summon-and-release switching from fullscreen browser Spaces instead of selecting the fullscreen app again.
- Fullscreen Chrome now hides the page currently under Orbit instead of accidentally hiding an untitled browser helper surface. Same-Chrome off-Space targets always use the Window-menu action even when `AXRaise` misleadingly reports success, and Orbit does not reactivate Chrome afterward; either shortcut could leave or restore the old fullscreen Space instead of reaching the selected window.
- A Chromium Window-menu action that times out is no longer treated as a definite failure. Accessibility actions can be accepted before the target app finishes replying; immediately running the AppleScript fallback in that state reactivated the old fullscreen Space and undid the pending switch. Orbit now gives the actual menu item its own timeout and preserves an indeterminate-but-possibly-accepted action.
- Selecting a specific window in the preview carousel now lands on that window, including one buried under the app's other windows. Windows are re-identified by title *and* frame instead of an exact-title match — ScreenCaptureKit and Accessibility report different title formats for the same window, so the old equality test silently failed for browsers.
- The chosen window is now focused *before* the application is activated. macOS follows an application onto the Space its main window lives on, so naming the window first is what makes a switch to a fullscreen window's Space actually land there; the old order could only reorder windows on the Space it had already arrived at.
- Activating a chosen window no longer restores the app's own front-to-back window order on top of it, and a minimized target window is restored before being raised.
- A failed raise now reports failure instead of success, so the plain app-activation fallback runs instead of leaving the wrong window in front.

- A fullscreen Chromium window on another Space is now reachable. Chromium implements the scripted window reorder without making the window key, so a switch used to stop on whichever Space the app was last active on. Orbit now presses the matching entry in the app's own Window menu — which Chromium does expose to Accessibility, and which performs a real makeKeyAndOrderFront. Orbit activates the process afterward only when the switch originated in a different app; same-Chrome switches must not reassert the old fullscreen window. The Window menu is recognised by its contents (it is the only menu listing all of the app's window titles), never by its localized title.

- The app you are currently in is reachable again when it has more than one window. The ring used to drop the frontmost app's card entirely, so standing in one Chrome window put every other Chrome window out of reach. That card now appears whenever the app owns more than one window — its only purpose being to reach the others — and its preview hides the window you are looking at. An app with a single window still has no card, since selecting it would only return you where you already are.

### Added

- Apple Events fallback for apps whose windows Accessibility cannot see. Chromium-based apps (Chrome, Edge, Brave …) expose no windows to the Accessibility API at all, so Orbit now asks such an app directly, over Apple Events, to bring the chosen window forward. First use prompts for the Automation permission; declining it degrades gracefully to plain app activation — the behaviour Orbit always had.
- The bundle now declares `NSAppleEventsUsageDescription` for the Automation prompt.
- Settings › General gains a one-shot Automation pre-authorization button. The permission is per target app and macOS only asks on first contact, which used to interrupt the first switch into each Chromium-based app with a dialog; the button walks the running apps that will need the fallback (real windows, none visible to Accessibility) and fronts all of those prompts now. Localized in all 11 bundled languages.

### Validation

- The test targets now contain 51 `OrbitTests` tests and 2 `OrbitUITests` methods, including new unit coverage for cross-framework title matching (with real Chrome title pairs), frame-tolerance boundaries, AppleScript title escaping, Window-menu recognition, cross-Space direct-focus and activation policy, current-app card eligibility, current-window hiding, pre-authorization candidate selection, and `AEDeterminePermissionToAutomateTarget` status mapping.
- Both activation paths were verified against real window stacks via `CGWindowListCopyWindowInfo` z-order: the Accessibility path raised the bottom of three Finder windows, and the Apple Events path raised the bottom of five Chrome windows.
- The installed `/Applications/Orbit.app` was manually verified across fullscreen Chrome Spaces and into a normal Chrome window. Public switch diagnostics confirmed each selected window became on-screen, including the formerly failing fullscreen target that reports a misleading successful `AXRaise` before the Window-menu fallback completes the Space switch.

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
