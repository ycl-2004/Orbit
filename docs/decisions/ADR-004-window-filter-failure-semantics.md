# ADR-004: Distinguish an empty window set from window-list failure

## Status

Accepted

## Context

`CGWindowListCopyWindowInfo` can return an empty array when no windows match the
requested options, but returns `NULL` when the window server is unavailable or
the process is outside a GUI security session. Treating both results as an
empty `Set` made the `hideWindowlessApps` filter indistinguishable from a
failed query. The app then fell back to the unfiltered running-app list,
reintroducing windowless cards exactly when the filter had no real windows to
show.

The window preview also drops windows without titles. When Screen Recording
permission makes titles readable, the ring should apply the same title rule;
without that permission, requiring a title would incorrectly hide real windows
whose titles are returned as unavailable.

## Decision

- `WindowVisibilityChecker.processesWithWindows()` returns an optional PID set.
- An empty set is authoritative: no listed app owns a qualifying window, so
  `hideWindowlessApps` returns an empty app list.
- `nil` means the window query failed, so the app list is preserved as a safe
  degraded result.
- `isRealWindow` requires a non-empty title only when
  `CGPreflightScreenCaptureAccess()` reports that titles can be read.

## Consequences

- A ring with no qualifying windows remains empty instead of showing dead-end
  app cards; its center control still handles cancel and file drops.
- Window-server failures do not make the app list disappear.
- Apps with untitled placeholder surfaces are excluded when titles are readable,
  while users without Screen Recording permission do not lose real windows.

## Sources

- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29)
- [Window List Option Constants](https://developer.apple.com/documentation/coregraphics/window-list-option-constants)
- [CGPreflightScreenCaptureAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29)
