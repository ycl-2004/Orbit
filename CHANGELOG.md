# Orbit release notes

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

- The full clean test suite passed: 37 `OrbitTests` tests and 2 `OrbitUITests` tests, with 0 failures.
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
