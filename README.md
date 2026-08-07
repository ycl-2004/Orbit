<p align="center">
  <img src="Orbit/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="Orbit logo" width="120" height="120">
</p>

<h1 align="center">Orbit</h1>

<p align="center">
  <strong>A native macOS app switcher for people who want faster window switching.</strong>
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/Orbit/releases/latest"><img src="https://img.shields.io/github/v/release/ycl-2004/Orbit?label=release&color=111111" alt="Latest release"></a>
  <a href="https://github.com/ycl-2004/Orbit/releases"><img src="https://img.shields.io/github/downloads/ycl-2004/Orbit/total?label=downloads&color=111111" alt="Total downloads"></a>
  <a href="https://github.com/ycl-2004/Orbit/actions/workflows/ci.yml"><img src="https://github.com/ycl-2004/Orbit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-111111?logo=apple&logoColor=white" alt="macOS 14.0 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white" alt="Built with SwiftUI and AppKit">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-free%20for%20personal%20use-111111" alt="Free for personal use"></a>
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/Orbit/releases/latest/download/Orbit-macOS.zip"><strong>⬇ Download for macOS</strong></a>
  ·
  <a href="https://github.com/ycl-2004/Orbit/releases">Releases</a>
  ·
  <a href="#features">Features</a>
  ·
  <a href="#roadmap">Roadmap</a>
  ·
  <a href="CONTRIBUTING.md">Contributing</a>
  ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="photos/AppIntro.png" alt="Orbit App Intro and Welcome artwork" width="509">
</p>

<p align="center">
  <sub>App Intro / Welcome — hold Option, choose an app, and release to switch.</sub>
</p>

Hold a modifier key and every running app appears in a ring around your cursor.
Flick toward the one you want and release. No list to scan, no Command-Tab
cycling, no window hunting. Orbit is a menu bar app built in SwiftUI and AppKit,
with no third-party dependencies and no network access — everything stays
on-device.

## Quick start

1. **[Download `Orbit-macOS.zip`](https://github.com/ycl-2004/Orbit/releases/latest/download/Orbit-macOS.zip)** and unzip it. Requires macOS 14.0 or later; the release is a Universal 2 build for Apple Silicon and Intel Macs.
2. Move `Orbit.app` to `/Applications`. On first launch, Control-click it and choose **Open** — the build is ad-hoc signed, not Apple-notarized, so a regular double-click is blocked.
3. Grant **Accessibility** permission when asked, then hold **Option (⌥)** anywhere to summon the ring.

If the Control-click **Open** option is unavailable, clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Orbit.app
open /Applications/Orbit.app
```

Screen Recording permission is requested only if you turn on window previews.

The current Xcode project reports version `1.4.0 (build 3)`. See the
[1.4.0 release notes](CHANGELOG.md) for the changes since `v1.3.0`.

## Why Orbit

- **Spatial, not sequential.** Apps sit at fixed angles around the cursor, so you build muscle memory for direction instead of counting Command-Tab presses.
- **Switch to a window, not just an app.** With previews on, arrow left/right picks the exact window of the selected app before you release.
- **Recent when it matters, stable when you want it.** Orbit chooses the visible app set from recent activation history, then lets you arrange those cards by Recently used or By name.
- **The center is a drop target.** Drag an app card in to quit it; the optional Orbit card safely cleans up ordinary apps with no open windows, while Orbit and Finder stay protected. Drag a file in to AirDrop it, or hold to send it to the Trash.
- **Nothing leaves your Mac.** No accounts, no telemetry, no network calls. Native SwiftUI/AppKit with zero third-party packages.

## Features

**Switching**

- Radial app switcher summoned by holding a modifier key (default: Option ⌥).
- Arrow-key navigation enabled by default; optional letter and number shortcuts can be turned on in Settings.
- Optional window previews beside the ring. Enable **Show window previews** in Settings and grant Screen Recording permission; macOS requires an Orbit restart after granting it.
- **Preselect the last app** is optional and off by default. When enabled, summon-and-release behaves like Command-Tab; when disabled, releasing without a selection remains a safe no-op.
- A pending summon is canceled if another key, mouse button, or scroll gesture arrives before the hold completes, preventing accidental ring openings.

**Center target actions**

- Drag an app into the center to quit it, with a pixel-dissolve animation.
- Orbit can appear as an optional special card; drag it to the center to request a normal quit for eligible windowless apps. Orbit and Finder are never candidates.
- Drag files into the center to AirDrop them, or keep holding to move them to the Trash.

**Configuration**

- Interface language, recent/alphabetical card order, optional recent-app preselection, preview size (70%–150%), trigger and clear-selection keys, optional letter/number shortcuts, long-press threshold, ring placement, card size and material, and launch-at-login.
- The language picker includes English, Simplified Chinese, Traditional Chinese, Japanese, Korean, German, French, Russian, Danish, Norwegian Bokmål, and Esperanto. Orbit asks to restart after a language change so the whole interface reloads consistently.
- Preview capture uses the display where Orbit was summoned, which keeps mixed-resolution and multi-display setups sharp and predictable.

## Usage

- Hold the trigger modifier to open Orbit near the cursor.
- Hover or click a card to select it; release the trigger or press Enter to confirm.
- Press Escape to cancel. Clicking the center does whatever it currently says it does: Cancel when nothing is selected, Confirm when an app is selected.
- Use the arrow keys (and Tab) to navigate apps by default. Settings can enable number keys `1`–`9` or first-letter matching as additional shortcuts.
- When previews are enabled and the selected app has multiple windows, use left/right to choose a window; release the trigger or press Enter to activate it.
- Press the clear-selection key (Shift by default) to remove the highlight; releasing the trigger then closes Orbit without switching.
- Drag an app card into the center and release to quit it.
- While the ring is open, drag a file onto the center target and release for AirDrop; keep it over the target for 0.9 seconds until it changes to Trash, then release to move it to the macOS Trash. The file interaction keeps Orbit open until it finishes.
- Click the menu bar icon for settings, permissions, and quit.

## Screenshots

<details open>
<summary>Ring, file actions, window previews, and settings (8 screenshots)</summary>

| Orbit Ring | File Share | File Delete |
| --- | --- | --- |
| ![Orbit ring](photos/01-orbit-ring.png?v=da051c6) | ![File share](photos/02-file-share.png?v=da051c6) | ![File delete](photos/03-file-delete.png?v=da051c6) |

| App Exit | Settings | Welcome |
| --- | --- | --- |
| ![App exit](photos/04-app-exit.png?v=da051c6) | ![Settings](photos/05-settings.png?v=da051c6) | ![Welcome](photos/06-welcome.png?v=da051c6) |

| Window Preview | Window Selection |
| --- | --- |
| ![Window preview](photos/07-window-preview.png?v=da051c6) | ![Window selection](photos/08-window-selection.png?v=da051c6) |

These screenshots show the current Orbit flows on macOS. They are cropped to the
product canvas with the macOS menu bar and desktop chrome removed, then normalized
to 1556×900 for consistent documentation. The source PNGs live in `photos/` so the
README stays aligned with the checked-in product captures.

</details>

## Roadmap

Directional, not a commitment — order and scope will change based on what people
actually run into. Open an [issue](https://github.com/ycl-2004/Orbit/issues) to
argue for something.

- [ ] Apple-notarized signed builds, so the first launch needs no workaround
- [ ] Homebrew Cask distribution
- [ ] Pinned favorites that are independent of recent-use membership
- [ ] More ring layout and appearance options
- [ ] Translation review and additional locale coverage
- [ ] Full keyboard and accessibility coverage across every flow

## Contributing

Issues and pull requests are welcome — bug reports with your macOS version and
Orbit version are the most useful thing you can send.

- Read **[CONTRIBUTING.md](CONTRIBUTING.md)** for the build, test, and PR conventions.
- New here? Start with a **[good first issue](https://github.com/ycl-2004/Orbit/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)**.
- Please open an issue before a large change. The source is not under a permissive open-source license — see [LICENSE](LICENSE).

## FAQ

<details>
<summary>macOS says Orbit "cannot be opened because the developer cannot be verified"</summary>

The release build is ad-hoc signed and not Apple-notarized, so Gatekeeper blocks
a plain double-click. Control-click `Orbit.app` and choose **Open**, or run
`xattr -dr com.apple.quarantine /Applications/Orbit.app`. Notarized builds are on
the [roadmap](#roadmap).

</details>

<details>
<summary>Why does Orbit need Accessibility and Screen Recording permission?</summary>

**Accessibility** is required for the global modifier-key trigger — without it,
macOS will not tell Orbit that you are holding the trigger key outside its own
windows. **Screen Recording** is requested only when you enable window previews,
because live window thumbnails are screen content. macOS requires an Orbit
restart after you grant it. Nothing captured is stored or transmitted.

</details>

<details>
<summary>How do I change Orbit's interface language?</summary>

Open the menu bar icon, choose **Settings → Language**, and select **Follow
System** or one of Orbit's bundled languages. Orbit shows a restart prompt after
the selection changes; restart it for every view and menu to use the new locale.

</details>

<details>
<summary>How do I uninstall Orbit?</summary>

Quit Orbit from the menu bar icon, then move `/Applications/Orbit.app` to the
Trash. To also remove its preferences:

```bash
defaults delete app.orbit.local
```

You can revoke the permissions under **System Settings → Privacy & Security →
Accessibility / Screen Recording**.

</details>

<details>
<summary>Does Orbit send anything over the network?</summary>

No. There are no accounts, no analytics, and no third-party packages. AirDrop
transfers are handed to macOS and never touch an Orbit-controlled server.

</details>

## Build from source

<details>
<summary>Requirements, build commands, and test commands</summary>

Requirements:

- macOS 14.0 or later for the current reconstructed Xcode project.
- Universal 2 release artifacts contain both `arm64` and `x86_64`; the downloadable release supports Apple Silicon and Intel Macs.
- Xcode 26 or later.
- Accessibility permission for the global modifier-key trigger.
- Screen Recording permission if live window previews are enabled.

The repository's **Code → Download ZIP** action gives you the source tree, while
the link in the Quick start section gives you a ready-built `.app`. You can also
build with Xcode (or the command below), then choose your own Team if you need a
normally signed app for local use or distribution. There are no third-party
package dependencies.

Open `Orbit.xcodeproj` in Xcode, choose **My Mac**, and press **Run**. The
shared project does not contain a developer Team ID. If Xcode asks for
signing, choose your own Team and replace the local bundle identifiers with
identifiers unique to your account.

To verify a build without using a signing identity:

```bash
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build
```

To run the full test suite, including unit and UI tests:

```bash
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode clean test \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

For a faster unit-test-only loop:

```bash
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:OrbitTests
```

The repository intentionally excludes generated build products, DerivedData,
Xcode user state, local environment files, secrets, logs, and local workflow
state. The source files, assets, tests, project file, workspace data, and
public documentation remain tracked.

Release verification, including Universal 2 checks and the clean-machine
installation/permission regression checklist, is documented in
[docs/release-checklist.md](docs/release-checklist.md). GitHub Actions runs the
metadata check, Debug build, and 36 `OrbitTests` tests on every push and pull request.

</details>

## Project layout

- `Orbit/` — app source, configuration, resources, and asset catalog.
- `Orbit/Config/AppLanguage.swift` and `Orbit/Settings/` — language and user preference behavior.
- `Orbit/Services/AppActivationHistory.swift` — recent activation history used to build the ring.
- `OrbitTests/` — unit tests for interaction and selection behavior.
- `OrbitUITests/` — UI test targets.
- `Orbit.xcodeproj/` — shared Xcode project and workspace data.
- `photos/` — README screenshots, the App Intro artwork, and supporting images.
- `scripts/` — install, release packaging, and demo GIF helpers.
- `docs/decisions/` — product and engineering decision records.

## About Orbit

Orbit is an independent native macOS project built around a radial,
gesture-first workflow. This repository provides:

- The complete SwiftUI/AppKit source, resources, tests, and shared Xcode project.
- Portable placeholder bundle identifiers under `app.orbit.local`.
- No developer Team ID, signing certificate, or machine-specific Xcode state.
- English-first documentation with a separate Simplified Chinese version.
- Current source build: `1.4.0 (build 3)`.
- English is the default app localization; the in-app picker ships English, Simplified Chinese, Traditional Chinese, Japanese, Korean, German, French, Russian, Danish, Norwegian Bokmål, and Esperanto.

## License

The compiled app is free for personal, non-commercial use. The source is
available for reference under the terms in [LICENSE](LICENSE).

## Links

- [Download the latest release](https://github.com/ycl-2004/Orbit/releases/latest)
- [Issues](https://github.com/ycl-2004/Orbit/issues)
- [Contributing guide](CONTRIBUTING.md)
- [Decision records](docs/decisions)
- [Simplified Chinese README](README.zh-CN.md)
