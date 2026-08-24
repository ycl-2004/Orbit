# ADR-008: Make ring opening animation optional

## Status

Accepted

## Date

2026-08-24

## Context

Orbit's hold-to-summon interaction opens a fan of app cards from the centre.
The deployment animation gives the ring a sense of origin, but it also delays
the moment at which the complete set of targets is readable. People who use
Orbit as a fast switcher may prefer the final layout immediately.

## Decision

Add a `Show the ring instantly` toggle under Settings → Shortcuts, next to the
existing opening behavior choice. It is off by default so existing installs
keep the animated presentation.

When enabled, the summon captures the preference once and renders the scrim,
trail, cards, centre control, and preview container in their final opening
state without deployment animation. It does not change the hold threshold,
selection or carousel animations, collapse animation, target activation, or
asynchronous thumbnail loading.

## Alternatives considered

### Change the global animation speed

Rejected. A speed control still makes the user wait and would also affect
interaction and dismissal motion that this preference is not meant to change.

### Make instant opening the new default

Rejected. The existing animation communicates where the fan came from and is a
reasonable first-run presentation; users who value the shortest visual path can
opt in.

### Delay the trigger itself

Rejected. The current hold threshold is an independent shortcut setting. Mixing
it with presentation style would make the toggle unexpectedly change when the
ring opens.

## Consequences

- Users who want the fastest visual result can open the ring directly in its
  usable final layout.
- The preference is sampled per summon, so changing Settings cannot produce a
  half-animated ring already on screen.
- Window preview thumbnails may still appear a moment later because capture and
  permission checks remain asynchronous; the ring layout itself is immediate.
