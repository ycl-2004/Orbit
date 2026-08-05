# ADR-002: Make card shortcut styles optional

## Status

Accepted

## Context

Orbit supports several ways to select a card. Letter and number shortcuts are
useful for power users, but showing or handling every shortcut by default makes
the ring visually busy and adds accidental key paths for users who prefer
directional navigation.

## Decision

Arrow-key navigation remains available by default. Letter matching and number
keys `1`–`9` are independent opt-in settings under Settings → Trigger. Card
hints only show the shortcut styles that are enabled, and disabled shortcut
commands are ignored by both the event tap and the ring model.

## Consequences

- New users get a simpler arrow-first interaction.
- Power users can enable letters, numbers, or both without changing the core
  navigation model.
- The usage section and card hints stay in sync with the selected settings.
- Number shortcuts remain limited to the first nine visible cards.
