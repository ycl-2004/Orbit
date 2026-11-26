# Orbit release checklist

This checklist is the release gate for the downloadable macOS archive. It
separates checks that can run in CI from the macOS privacy checks that require a
real clean user session.

## Automated checks

Run the metadata and test-count checks:

```bash
bash scripts/ci_validate.sh
```

Build the release archive, then verify its architecture and signature:

```bash
bash scripts/package_release.sh 1.7.0
bash scripts/verify_release.sh dist/Orbit-macOS.zip
```

`verify_release.sh` must report both `arm64` and `x86_64`. If either
architecture is missing, the archive must not be published. The current
release filename is `Orbit-macOS.zip` because it is Universal 2; an
architecture-specific filename is not appropriate for this artifact.

GitHub Actions runs the metadata check, a Debug Universal 2 build, and the
`OrbitTests` unit tests for every push and pull request. A version tag must match the
Xcode `MARKETING_VERSION`, for example `v1.7.0`.

Tags matching `v*` use `.github/workflows/release.yml`. With the repository
secrets `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`,
`MACOS_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, and
`APPLE_APP_PASSWORD`, it signs with Developer ID, notarizes with `notarytool`,
staples the app, verifies Universal 2, and uploads the ZIP plus SHA-256 file.
Without those secrets it still publishes a verified Universal 2 ad-hoc ZIP;
users must use the documented **Privacy & Security → Open Anyway** flow until
notarization is configured.

## Clean-machine installation regression

Perform this once for each release candidate on a macOS machine or clean user
account that has never launched this Orbit build:

1. Download the exact release ZIP from the candidate release and run
   `bash scripts/verify_release.sh /path/to/Orbit-macOS.zip`.
2. Unzip it, move only `Orbit.app` to `/Applications`, and remove any old Orbit
   copy from that machine before launching.
3. Open the app, then allow it under **System Settings → Privacy & Security →
   Open Anyway**. Confirm the app appears only once in LaunchServices and the
   menu bar, and that no Dock icon appears at launch.
4. On first launch macOS asks for Accessibility. Grant it, then — without
   relaunching — hold Option while another app is frontmost. The ring must
   appear and switch apps.
5. With Chrome open in several windows, pick one of its windows in the
   preview carousel and release. On the first Apple Events fallback macOS asks
   for Automation; allow it and confirm the chosen window comes forward. A
   switch with no prompt and no window change means the release lacks the
   Apple Events entitlement.
6. Enable window previews, grant Screen Recording, restart Orbit, and confirm a
   selected app's preview is readable. Revoke Screen Recording and confirm the
   app remains usable with the documented permission-required state.
7. Revoke Accessibility and confirm the menu reports it missing and the trigger
   stops. Grant it again and confirm the trigger works without a relaunch.
8. Delete the app, reinstall the same ZIP, and repeat the Accessibility flow.
   Confirm there is no stale duplicate Orbit entry in System Settings.

The Accessibility and Screen Recording steps are intentionally manual: macOS
TCC privacy databases are user- and machine-specific and cannot be safely
granted or reset by a repository CI job. The release artifact, bundle, code
signature, architecture, and metadata are automated; the privacy regression
steps above are the required human sign-off.
