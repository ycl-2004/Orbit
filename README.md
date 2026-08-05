<p align="center">
  <img src="Orbit/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="Orbit logo" width="144" height="144">
</p>

<h1 align="center">Orbit</h1>

<p align="center">
  <strong>A radial, gesture-first app switcher and file hub for macOS.</strong>
</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/Orbit/releases/latest/download/Orbit-macOS.zip"><strong>Download Orbit for macOS</strong></a>
</p>

Orbit is a native menu bar companion that puts your running apps around the
cursor, so you can switch, manage, and share without leaving your flow.
Everything stays on-device.

## About Orbit

Orbit is an independent native macOS project built around a radial,
gesture-first workflow. This repository provides:

- The complete SwiftUI/AppKit source, resources, tests, and shared Xcode project.
- Portable placeholder bundle identifiers under `app.orbit.local`.
- No developer Team ID, signing certificate, or machine-specific Xcode state.
- English-first documentation with a separate Simplified Chinese version.
- English is the default app localization; Simplified Chinese, Traditional Chinese, and other localized resources are included.

## Download

[Download the latest Orbit for macOS](https://github.com/ycl-2004/Orbit/releases/latest/download/Orbit-macOS.zip).
It requires macOS 26.0 or later. Unzip the archive, move `Orbit.app` to
`/Applications`, then open it.

The downloadable build is ad-hoc signed and is not Apple-notarized. If macOS
blocks the first launch, Control-click `Orbit.app`, choose **Open**, and confirm.
If that option is unavailable, run:

```bash
xattr -dr com.apple.quarantine /Applications/Orbit.app
open /Applications/Orbit.app
```

Orbit will request Accessibility permission for its global trigger and Screen
Recording permission only when window previews are enabled.

## Features

- Radial app switcher summoned by holding a modifier key (default: Option ⌥).
- Arrow-key navigation is enabled by default; optional letter and number shortcuts can be enabled in Settings.
- Optional window previews beside the ring. Enable **Show window previews** in Settings and grant Screen Recording permission; macOS requires an Orbit restart after granting it.
- Drag an app into the center target to quit it with a pixel-dissolve animation.
- Drag files into the center to AirDrop or, after holding, move them to the Trash.
- Configurable trigger and clear-selection keys, optional letter/number shortcuts, long-press threshold, ring placement, card size/material, and launch-at-login.

## Screenshots

| Orbit Ring | File Share | File Delete |
| --- | --- | --- |
| ![Orbit ring](photos/01-orbit-ring.png) | ![File share](photos/02-file-share.png) | ![File delete](photos/03-file-delete.png) |

| App Exit | Settings | Welcome |
| --- | --- | --- |
| ![App exit](photos/04-app-exit.png) | ![Settings](photos/05-settings.png) | ![Welcome](photos/06-welcome.png) |

These screenshots show the current Orbit flows on macOS. The source PNGs live in
`photos/` so the README stays aligned with the checked-in product captures.

| Window Preview | Window Selection |
| --- | --- |
| ![Window preview](photos/07-window-preview.png) | ![Window selection](photos/08-window-selection.png) |

## Build from source

Requirements:

- macOS 26.0 or later for the current reconstructed Xcode project.
- Xcode 26 or later.
- Accessibility permission for the global modifier-key trigger.
- Screen Recording permission if live window previews are enabled.

The repository's **Code → Download ZIP** action gives you the source tree, while
the link in the Download section gives you a ready-built `.app`. You can also
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

To run the unit tests:

```bash
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO test -only-testing:OrbitTests
```

The repository intentionally excludes generated build products, DerivedData,
Xcode user state, local environment files, secrets, logs, and local workflow
state. The source files, assets, tests, project file, workspace data, and
public documentation remain tracked.

## Usage

- Hold the trigger modifier to open Orbit near the cursor.
- Hover or click a card to select it; release the trigger or press Enter to confirm.
- Press Escape or click the center to cancel.
- Use the arrow keys (and Tab) to navigate apps by default. Settings can enable number keys `1`–`9` or first-letter matching as additional shortcuts.
- When previews are enabled and the selected app has multiple windows, use left/right to choose a window; release the trigger or press Enter to activate it.
- Press the clear-selection key (Shift by default) to remove the highlight; releasing the trigger then closes Orbit without switching.
- Drag an app card into the center and release to quit it.
- While the ring is open, drag a file onto the center target and release for AirDrop; keep it over the target for 0.9 seconds until it changes to Trash, then release to move it to the macOS Trash. The file interaction keeps Orbit open until it finishes.
- Click the menu bar icon for settings, permissions, and quit.

## Project layout

- `Orbit/` — app source, configuration, resources, and asset catalog.
- `OrbitTests/` — unit tests for interaction and selection behavior.
- `OrbitUITests/` — UI test targets.
- `Orbit.xcodeproj/` — shared Xcode project and workspace data.
- `photos/` — README screenshots and supporting artwork.
- `docs/decisions/` — product and engineering decision records.

## License

The compiled app is free for personal, non-commercial use. The source is
available for reference under the terms in [LICENSE](LICENSE).

## Links

- [Issues](https://github.com/ycl-2004/Orbit/issues)
- [Simplified Chinese README](README.zh-CN.md)
