# ADR-005: Language selection, recent-app ordering, and display-aware previews

## Status

Accepted

## Date

2026-08-07

## Context

The latest settings work adds three user-visible behaviors that affect how the
ring is built and rendered:

- Orbit ships multiple interface languages, but a language change must update
  every view and menu consistently.
- A fixed alphabetical list makes the ring predictable but can omit the app a
  user just left; a purely recent list makes spatial muscle memory less stable.
- A preview summoned on a secondary display can be captured at the wrong density
  if the implementation assumes `NSScreen.main` is the target display.

These behaviors need explicit contracts so the settings UI, ring construction,
and preview pipeline do not drift apart.

## Decision

### Interface language

Orbit uses the standard `AppleLanguages` application preference domain. The
Settings language picker offers Follow System plus the 11 bundled locales, and
normalizes regional tags such as `en-CA` and `zh-Hant-TW` to the closest bundled
locale. A language change requires an Orbit restart; the app offers that action
instead of trying to partially reload already-created SwiftUI and AppKit state.

### Ring membership and order

`AppActivationHistory` records frontmost application changes from the initial
window ordering and subsequent workspace activation notifications. The history
is used to choose the visible app set, capped by the existing maximum. The
`RingOrder` preference then arranges that chosen set either by recent use or by
localized app name. Alphabetical order changes placement, not membership.

Recent-app preselection is opt-in and defaults to off. When enabled, the most
recent eligible app starts selected so summon-and-release resembles Command-Tab;
when disabled, releasing without an explicit selection remains a safe cancel.

### Display-aware preview capture

Preview capture receives the scale of the display where Orbit was summoned and
uses it together with the user-controlled 70%–150% preview scale. It does not
read `NSScreen.main` as a proxy for the target display. Capture width remains
bounded by the configured maximum to keep short-lived ring interactions from
requesting unbounded image memory.

## Alternatives considered

### Reload only the visible language strings

Rejected because menus, settings labels, and AppKit-created surfaces can be
created through different lifecycles. A restart is explicit and produces one
consistent locale state.

### Use alphabetical order to choose the ring's app set

Rejected because the ordering preference should not make a recently used app
disappear merely because its name sorts outside the visible limit.

### Always use `NSScreen.main` for capture scale

Rejected because Orbit can be summoned on a display with a different density;
the resulting thumbnail would be either soft or needlessly oversized.

## Consequences

- Users can choose a recognizable language without requiring system-wide
  language changes, with a visible restart step after selection.
- The ring remains recent-use aware while supporting stable alphabetical card
  placement for users who prefer muscle memory.
- Mixed-resolution and multi-display preview layouts use the intended target
  display scale, within a bounded capture budget.
- The app maintains a small amount of activation history and preference state;
  both remain local to Orbit and are not sent over the network.
