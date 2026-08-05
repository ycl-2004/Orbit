# ADR-001: Ring interaction semantics and local signing

## Status

Accepted

## Date

2026-08-04

## Context

Orbit's radial interaction needs an explicit distinction between selection and
activation. A card can be selected without immediately activating its app, and
the center target needs to distinguish cancellation from an intentional quit.

The local project also contained a developer Team ID and personal bundle
identifiers, which prevented a clean signing workflow for other contributors.

## Decision

### Interaction states

Orbit uses three distinct states:

1. No app selected: the ring is open and the center is a safe Cancel target.
2. App selected: hover/click changes selection but does not activate the app;
   pressing Enter or releasing the trigger key confirms activation.
3. App dragged into the center: the center changes to a Quit target; only
   releasing an explicit card drag can terminate the app.

Escape and clicking the center cancel the ring. Releasing the trigger without
   a selected app also cancels, so a user cannot accidentally jump to an app
   merely by opening and closing the ring.

While the ring is open, the event tap is an active filter and consumes keyboard
navigation events after translating them into Orbit commands. This prevents
Tab, arrow, number, and letter keys from also reaching the application beneath
the overlay.

### Frontmost application filtering

Orbit captures the real frontmost application before showing its overlay, then
excludes that process only when it has a visible window. This avoids treating
Orbit's own overlay as the active application and avoids hiding background
menu-bar apps that have no visible window.

### Window preview permission and selection

Window previews are opt-in because ScreenCaptureKit requires the separate
Screen Recording permission. When the setting is enabled and permission is
available, Orbit shows up to six titled, normal-layer windows for the selected
app in a panel beside the ring. Left and right arrows move between those
windows; Enter or releasing the trigger activates the app and raises the
selected window when Accessibility can match its title. If permission is
missing, the ring remains usable without previews. macOS applies a newly
granted Screen Recording permission after Orbit is restarted.

### Local signing

The shared project does not specify a `DEVELOPMENT_TEAM`. The app and test
targets use local-only placeholder identifiers under `app.orbit.local`.
Developers who need automatic signing select their own Team in Xcode's Signing
& Capabilities pane and replace those identifiers with values unique to their
account. No personal certificate, Team ID, or signing secret is stored in the
repository.

## Alternatives considered

### Activate on card click

Rejected because it makes cancellation difficult and conflicts with the
gesture-first model. Click/hover selection is reversible; activation is an
explicit confirmation.

### Treat every center entry as Quit

Rejected because the center is under or near the pointer when the ring opens,
and ordinary pointer movement could become destructive. Quit requires an
explicit drag gesture and a visible center-state change.

### Store a developer Team ID in the shared project

Rejected because a personal signing identity is machine-specific and should not
be committed to a portable project.

## Consequences

- The ring is safer and easier to explain, at the cost of one confirmation
  step before switching.
- App termination remains available but is visually and gesturally explicit.
- A user must choose their own Team in Xcode before a normally signed build can
  be run; Accessibility authorization is still required for the global event
  tap.
- Window previews add a privacy-sensitive permission and a restart step, but
  they remain optional so the core app switcher does not depend on Screen
  Recording access.
