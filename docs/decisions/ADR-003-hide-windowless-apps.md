# ADR-003: Keep apps with no windows off the ring

## Status

Superseded by [ADR-004](ADR-004-window-filter-failure-semantics.md)

This ADR records the original window-filter decision. The empty-result fallback
described below was later superseded because an empty window list is a valid,
authoritative result rather than a query failure.

## Context

The ring was built from `NSWorkspace.runningApplications` filtered only by
`activationPolicy == .regular`. That is the same test the Dock uses for its
running indicator, and it counts a process as present even when it has no
window open at all — Finder in its idle state, or any app whose last window was
closed without quitting.

Those cards were dead ends. Selecting one showed `preview.none` ("No windows to
preview") in the preview panel, and switching to it activated a process that put
nothing on screen. The card looked identical to a real one right up until the
moment it did nothing.

## Decision

An app must own at least one real window to appear on the ring, controlled by
`hideWindowlessApps` in Settings → Appearance and **on by default**.

"Real window" is decided by `WindowVisibilityChecker.isRealWindow`: normal
window layer, non-transparent, and at least `OrbitConfig.minimumRealWindowSize`
(200×120). Both the ring's app list and `WindowPreviewService`'s window list
measure against that one constant, so a card never promises a thumbnail the
preview then refuses to show.

Two deliberate choices inside that:

- **Off-screen windows count.** The query drops `.optionOnScreenOnly`, unlike
  the pre-existing `hasVisibleWindow`. A minimized window, a window on another
  Space and a fullscreen app are all off-screen, and all three are things a
  person still wants to switch back to. Only "no windows anywhere" hides an app.
- **The size threshold is not cosmetic.** Finder keeps four untitled 1512×33
  menu-bar strips and a 64×64 surface on layer 0 at all times. Without a size
  floor those alone would make Finder look permanently windowed, and the whole
  filter would never fire for the app that motivated it.

If the filter would empty the ring entirely, the unfiltered list is shown
instead. A ring with a few useless cards is still a ring; a ring with nothing on
it reads as a bug.

## Consequences

- The window list is copied once per summon rather than once per app —
  `processesWithWindows()` returns the whole pid set in a single pass.
- Users who want the Dock's roster back can turn the setting off.
- One residual mismatch remains: the preview additionally requires a non-empty
  window title, which the ring cannot check because `kCGWindowName` needs the
  Screen Recording permission and the ring works without it. An app whose only
  window is untitled can still reach the ring and show an empty preview.
