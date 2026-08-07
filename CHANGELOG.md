# Orbit release notes

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

- Debug build succeeds.
- OrbitTests: 27 tests passed.
