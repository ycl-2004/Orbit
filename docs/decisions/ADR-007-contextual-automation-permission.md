# ADR-007: Request Automation only in the fallback context

## Status

Accepted

## Date

2026-08-08

## Context

Orbit has three progressively less general ways to focus a selected window:

1. Raise the exact Accessibility window.
2. Press the matching item in the target application's Window menu through Accessibility.
3. Ask the application to reorder the matching window through Apple Events.

The first two paths use the Accessibility permission Orbit already requires for
its global trigger. The third path is a best-effort fallback and requires a
separate, per-target-app Automation decision from macOS.

General Settings previously scanned running apps that might need the fallback
and exposed Allowed, Declined, Not requested, or Unavailable for each one. This
made an optional recovery path look like required setup. In practice, users
could decline every listed app and still switch successfully because the Window
menu path completed the operation first.

Apple's privacy guidance recommends requesting permission only when a feature
clearly needs it and, ideally, when the person uses the feature that requires it:

- <https://developer.apple.com/design/human-interface-guidelines/privacy>
- <https://developer.apple.com/videos/play/wwdc2019/701/>

## Decision

Remove Automation pre-authorization, background permission inspection, and the
app-by-app Automation status list from Orbit Settings.

Keep the Apple Events implementation as the final exact-window fallback. macOS
can present its standard consent dialog only if execution actually reaches that
path. A denial remains non-fatal: Orbit falls back to ordinary app activation.

Keep `NSAppleEventsUsageDescription` in the application bundle because Apple
requires a purpose string for apps that send Apple Events:

- <https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription>

## Alternatives considered

### Hide only “Not requested” rows

Rejected. Allowed and Declined were also misleading when the primary
Accessibility path already worked, and the remaining panel still presented an
optional fallback as a setup task.

### Show Automation only after a denial

Rejected for now. A stored denial does not prove that a current switch needs
Apple Events. macOS already provides the authoritative global control in System
Settings, while Orbit degrades safely.

### Remove Apple Events entirely

Rejected. Accessibility coverage differs by application and window state. The
fallback can still recover an exact window when both direct AX focus and Window
menu selection are unavailable.

## Consequences

- General Settings shows only permissions with an immediate, understandable
  effect on the current Orbit experience.
- The Window menu path recognises a menu by matching its entries against the
  window titles the app really owns, and reading another app's window titles
  requires Screen Recording. Without that permission the Window menu cannot be
  identified, so exact-window switches fall through to Apple Events sooner and
  the Automation dialog appears more often than the reasoning above implies.
  Screen Recording is itself optional in Orbit, so this is the expected shape of
  the trade rather than a defect: the fallback still degrades to plain app
  activation, which is what a person without either optional permission gets.
- Users no longer see or manage speculative per-app Automation states in Orbit.
- A system Automation prompt can still appear during a rare fallback attempt,
  at the moment its purpose is most relevant.
- Declining Automation never blocks Orbit's ordinary app-switch behavior.
