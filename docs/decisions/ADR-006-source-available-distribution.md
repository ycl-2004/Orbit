# ADR-006: Source-available distribution and product identity

## Status

Accepted

## Date

2026-08-07

## Context

Orbit benefits from being discoverable as a public GitHub project: users can
inspect the project, report issues, follow releases, and star the repository.
At the same time, the product's interaction design, implementation, name, and
visual identity are part of an independent product rather than a community
library. A permissive open-source license would allow commercial reuse,
rebranded distributions, and derivative products without preserving product
control.

The repository is already public and contains the complete source tree. The
distribution decision therefore needs to clarify what the public repository is
for without pretending that source visibility prevents copying.

## Decision

Orbit remains a public, source-available repository.

- The repository stays public for product discovery, transparency, issue
  discussion, documentation, and source reference.
- Official compiled releases remain the primary download path.
- Personal use of the official compiled app is permitted, explicitly including
  use on an employer-provided machine. An app switcher is used during work; a
  bare "non-commercial" restriction would have put most real users in breach.
- Organizational deployment — installing or managing Orbit across an
  organization's machines, for-profit or not — requires a written license. This
  is the line that preserves a future commercial tier.
- Source copying, modification, redistribution, sublicensing, sale, rebranding,
  and distribution of derivative works of the source require written permission.
  The restriction is scoped to derivative works rather than to "competing
  products", because copyright does not reach an independently written
  competitor and an unenforceable clause endangers the ones around it.
- The Orbit name, logo, and Orbit's own screenshots and artwork remain part of
  the product identity and are not granted for competing distributions.
  Third-party icons appearing in Orbit and its screenshots are explicitly
  disclaimed — they are not the copyright holder's to license.
- Contributions are accepted through maintainer-reviewed issues and pull
  requests. Contributors grant a sublicensable, relicensable inbound license so
  that accepting a PR does not foreclose commercial licensing later.
- The license carries termination, severability, statutory-rights reservation,
  and consumer-law carve-outs, so that a clause struck down in one jurisdiction
  does not take the rest of the license with it.
- No choice-of-law clause is stated yet. It will be set together with the legal
  entity and jurisdiction at commercialization; a wrong forum is worse than
  no forum.

## Alternatives considered

### Permissive open source under MIT or Apache-2.0

Rejected for now because it would maximize reuse and contribution freedom at the
cost of control over commercial and rebranded distributions.

### Private source with a public download-only repository

Rejected for now because it would reduce source transparency and make the GitHub
repository less useful for technical trust, issue discussion, and contributor
feedback. This remains a future option if the implementation becomes a more
valuable proprietary asset.

## Consequences

- Orbit can grow through a public product page, releases, issues, and stars
  without granting a permissive commercial reuse license.
- The license must be read together with GitHub's public-repository terms:
  publishing on GitHub makes the repository viewable and forkable within the
  service, and it does not technically prevent copies outside the repository.
- The custom license should be reviewed by a lawyer before commercial licensing
  or enforcing it against a third party.
- "Orbit" is a common product name. A trademark clearance search in the software
  class is required before charging for Orbit or asserting the name against
  anyone — the risk of infringing a prior holder is larger than the value of the
  identity clause, and renaming only gets more expensive as users accumulate.
- The copyright notice uses a pseudonymous handle. DMCA notices and any
  litigation require identifying the rights holder, so the notice should carry a
  real name or entity before enforcement is attempted.
- If the repository later changes from public to private, existing forks and
  local copies will not disappear, and repository stars/watchers may be lost.
