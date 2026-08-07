# Orbit release notes

## Unreleased — source build 1.3.0 (2)

### Added

- Settings now includes an interface-language picker with System plus 11 bundled locales: English, Simplified Chinese, Traditional Chinese, Japanese, Korean, German, French, Russian, Danish, Norwegian Bokmål, and Esperanto.
- The ring uses recent activation history to choose its visible app set, with a preference for Recently used or By name card order.
- An optional recent-app preselection preference makes summon-and-release behave like Command-Tab; it remains off by default for a safe no-op release.
- Preview size is configurable from 70% to 150%.

### Changed

- Window previews capture from the display where Orbit was summoned, preserving the intended sharpness across mixed-resolution displays.
- A pending summon is canceled when another key, mouse button, or scroll gesture arrives before the hold completes.

### Validation

- The full clean test suite passed: 34 `OrbitTests` tests and 2 `OrbitUITests` tests, with 0 failures.
- The current project metadata remains marketing version `1.3.0`, build `2`; the next published release version has not been selected.

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
- At release time, the test run was attempted but could not complete because CoreSimulatorService became unavailable in the build environment; the current source validation is recorded in the Unreleased section above.
