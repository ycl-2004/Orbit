# ADR-009: License Orbit under GPL-3.0

## Status

Accepted. Supersedes [ADR-006](ADR-006-source-available-distribution.md).

## Date

2026-11-26

## Context

ADR-006 kept Orbit public but source-available: free to use, not free to copy,
modify or redistribute. That kept product control, and it also kept Orbit out
of the places people find open-source Mac software. The largest open-source Mac
app list removes entries that lack an open-source license, awesome lists mark
source-available apps as freeware rather than open source, and no one can send
a fix they are not allowed to build. The repository had no forks.

The comparable Mac utilities that grew large communities — AltTab, Loop, Ice —
are all GPL-3.0.

## Decision

- Orbit's code is licensed under version 3 of the GNU General Public License
  (GPL-3.0-only). `LICENSE` holds the unmodified license text; the copyright
  notice lives in the README.
- Anyone may use, study, modify and redistribute Orbit. Whoever distributes it,
  modified or not, must provide the source under the same license, so a closed
  derivative of Orbit's code is not permitted.
- The license covers the code, not the Orbit name or logo. Modified builds that
  are distributed should carry their own name and icon.
- The inbound contributor grant from ADR-006 stays: contributors keep their
  copyright and grant the copyright holder a relicensable license. That keeps a
  separate commercial license possible later without tracking down every past
  contributor.

## Consequences

- Orbit can be listed and searched for as open source, and outside fixes can be
  built, tested and submitted.
- The organizational-deployment and personal-use distinctions of ADR-006 no
  longer apply; GPL-3.0 allows use anywhere.
- Releases published before this change were distributed under the
  source-available license; versions from this change on are GPL-3.0.
- Some contributors decline relicensing grants. If that keeps out work worth
  having, dropping the grant in favour of plain inbound-equals-outbound GPL is
  a later decision.
