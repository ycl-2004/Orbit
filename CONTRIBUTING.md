# Contributing to Orbit

Thanks for taking a look. Orbit is a small, single-purpose macOS app, and the
most valuable contributions are usually precise bug reports and focused fixes.

## Before you start

**Open an issue first for anything beyond a small fix.** The source is not under
a permissive open-source license — see [LICENSE](LICENSE) — so a large PR that
was never discussed may not be mergeable, and neither of us wants that. Bug
fixes, documentation, and localization corrections are always welcome.

Good bug reports include:

- Your Orbit version and macOS version, and whether you are on Apple Silicon or Intel.
- Whether Accessibility (and Screen Recording, if previews are on) is granted.
- Exact steps to reproduce, what you expected, and what happened instead.
- A screenshot or short recording if the problem is visual or timing-dependent.

Use the [issue templates](https://github.com/ycl-2004/Orbit/issues/new/choose) —
they ask for exactly this.

## Development setup

- macOS 14.0 or later (the deployment target of the current Xcode project).
- Xcode 26 or later.
- No third-party packages. Do not add a dependency without discussing it first.

Open `Orbit.xcodeproj`, choose **My Mac**, and press **Run**. The shared project
carries no developer Team ID. If Xcode asks for signing, pick your own Team and
replace `app.orbit.local` with a bundle identifier unique to your account —
but do not commit that change.

### Build and test

Both commands work without a signing identity:

```bash
# Build
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build

# Full test suite (unit + UI tests)
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode clean test \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# Unit-test-only loop
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:OrbitTests
```

To try your build the way a user would run it, use `scripts/install.sh`. It
installs to `/Applications` and removes the build product, because macOS grants
Accessibility and Screen Recording **per app path** — a copy left in `Build/`
registers as a second Orbit in System Settings and never inherits the
permissions you already granted.

## Manual verification

Automated tests cover selection and interaction logic, not the parts that depend
on system permissions. Before opening a PR, run through whatever your change
touches:

- **Trigger:** hold the trigger modifier over a non-Orbit app; the ring appears near the cursor. Release to switch, Escape to cancel.
- **Keyboard:** arrow keys and Tab move the selection; the clear-selection key removes the highlight; releasing then closes without switching.
- **Window previews:** enable **Show window previews**, grant Screen Recording, **restart Orbit** (macOS requires it), then check left/right window selection on a multi-window app.
- **Language:** select a bundled language or **Follow System** in Settings, confirm the restart prompt, then verify menus and settings reload in the selected locale.
- **Ring preferences:** check Recently used vs. By name ordering, and verify optional recent-app preselection behaves like Command-Tab while the default remains a safe no-op.
- **Preview size and displays:** change preview size from 70% to 150% and summon Orbit on each connected display when their scales differ.
- **Center target:** drag an app card in to quit it; drag a file in and release for AirDrop; hold a file over the target past the delay until it becomes Trash.
- **Settings:** the changed setting persists across an Orbit restart.

Say in the PR which of these you actually ran.

## Branches, commits, and PRs

- Branch off `main` with a short descriptive name, e.g. `fix-window-preview-restart`.
- Commit messages are lowercase and descriptive of the change, e.g. `feedback fix 1: hide-windowless-apps`. Keep them in English.
- One logical change per PR. Do not mix a refactor into a bug fix.
- Do not commit build products, `DerivedData`, Xcode user state, your Team ID, or your own bundle identifiers. Check `git status` against `.gitignore` before pushing.
- If your change alters user-visible strings, update every localization you can, and say which ones you could not.

## Decision records

Changes to interaction semantics, permission requirements, or how Orbit is
built and distributed need an ADR in `docs/decisions/`, named
`ADR-00N-short-slug.md` and following the existing format: `Status`, `Context`,
`Decision`, `Consequences`. See
[ADR-003](docs/decisions/ADR-003-hide-windowless-apps.md) for the level of
detail expected — state what was rejected and why, not just what was chosen.

Ordinary bug fixes and refactors do not need one.

## Code style

Match the file you are editing. In general: SwiftUI for views, AppKit where the
system API requires it, tunable constants in `OrbitConfig` rather than inline
literals, and comments that explain *why* a non-obvious constraint exists —
system quirks, permission behavior, timing — rather than restating the code.

## Documentation

`README.md` and `README.zh-CN.md` must stay in sync. If you change one, change
the other, or note in the PR that the translation is still pending.

The README hero animation is generated by `scripts/make_demo_gif.sh`. Run
`scripts/make_demo_gif.sh --from-screenshots` after updating `photos/`, or pass
a screen recording to build it from real footage.

## License of contributions

By submitting a pull request you agree that your contribution is licensed under
the terms in [LICENSE](LICENSE) and that the copyright holder may distribute it
as part of Orbit.
