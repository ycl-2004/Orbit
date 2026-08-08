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

Orbit also records the frontmost window ID on every summon. If the current app
has another actionable window, its app card represents that sibling-window
destination and becomes card zero; the preview carousel hides the current window
and puts the most recently viewed sibling first. If no sibling can be resolved,
the previous eligible app remains card zero. Window history is in-memory and
bounded per app; stale window IDs simply stop matching later snapshots.

Card zero always occupies 12 o'clock. Remaining cards continue from that anchor
in the same direction whether Window Preview is enabled or disabled; Recent keeps
MRU order, while By name sorts only the cards after the anchor. From a neutral
ring, either vertical arrow enters at card zero before subsequent presses traverse
the sequence.

Opening behavior is an explicit setting. **Start at Cancel** is the default and
leaves the ring unselected, so release is a no-op. **Quick switch** preselects
card zero, so release switches immediately. A synchronous sibling-window target
is captured before thumbnail work begins, allowing quick release to switch even
when preview capture has not completed or previews are disabled.

Reference behavior:

- Apple defines Command-Tab as switching to the next most recently used app:
  <https://support.apple.com/en-us/102650>
- Microsoft documents Alt-Tab as moving forward on each press and switching on
  release: <https://support.microsoft.com/en-US/Windows/Hardware/Input-Devices/windows-keyboard-tips-and-tricks>
- VS Code exposes the previous editor in its MRU list as the Ctrl-Tab target:
  <https://code.visualstudio.com/docs/editing/userinterface>
- JetBrains switchers keep the popup open while Tab and arrow keys move through
  recent targets: <https://www.jetbrains.com/help/idea/using-code-editor.html>

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

### Keep the current app's other-window card at the end

Rejected because the card is a real switch destination, not a utility action.
When the current app has another window, that sibling is more recent than leaving
the app and belongs at the first keyboard position. Orbit's cleanup card remains
at the end because it is a utility action.

### Always preselect or never preselect

Rejected in favor of an explicit opening-behavior setting. Cancel is the safer
default, while users who want Command-Tab-style release behavior can choose Quick
switch without changing the shared 12-o'clock ordering rule.

### Always use `NSScreen.main` for capture scale

Rejected because Orbit can be summoned on a display with a different density;
the resulting thumbnail would be either soft or needlessly oversized.

## Consequences

- Users can choose a recognizable language without requiring system-wide
  language changes, with a visible restart step after selection.
- The ring remains recent-use aware while supporting stable alphabetical card
  placement for users who prefer muscle memory.
- The highest-value muscle-memory target is stable in both arrangement modes:
  a recent sibling window takes 12 o'clock when available, otherwise the previous
  app does, and neutral keyboard entry always starts there.
- Mixed-resolution and multi-display preview layouts use the intended target
  display scale, within a bounded capture budget.
- The app maintains a small amount of activation history and preference state;
  both remain local to Orbit and are not sent over the network.
