# Orbit Privacy Policy

Last updated: 2026-08-08 — applies to Orbit 1.5.0 and later.

## The short version

Orbit collects nothing, stores nothing about you, and sends nothing anywhere.
There is no account, no analytics, no crash reporting, and no network code in
the app at all.

Orbit needs powerful macOS permissions to do its job — it watches for a modifier
key and, optionally, reads window thumbnails. This document explains exactly
what it does with that access, because "trust me" is not good enough for
permissions of that kind.

## What Orbit stores on your Mac

Your settings, and nothing else. They live in Orbit's own `UserDefaults` domain:
trigger modifier, long-press threshold, card size, ring order and placement,
preview size, whether window previews are on, keyboard shortcut toggles, your
language choice, and whether you have seen the welcome window.

That list is the whole of it. In particular, Orbit does **not** persist which
apps you use or when. The recently-used ordering in the ring is rebuilt in
memory each time Orbit runs and is gone when it quits — nothing about your app
usage is ever written to disk.

## What Orbit reads while running, and never keeps

To draw the ring, Orbit asks macOS for the currently running applications and
their names and icons. If window previews are enabled, it also reads window
titles and live window thumbnails. All of it is used to render the ring in the
moment and discarded when the ring closes. Thumbnails are never written to disk,
never encoded to a file, and never leave the process.

When you drag a file onto the center target, Orbit reads the file's path only to
hand it to macOS — see [System services](#system-services) below.

## Permissions Orbit asks for

**Accessibility** (required). macOS only notifies an app about key presses
outside its own windows if that app is trusted for Accessibility. Without it,
Orbit cannot notice you holding the trigger key while another app is in front,
which is the entire interaction. Orbit uses this access to observe the trigger
modifier and to activate the app you select. It does not log keystrokes, and it
does not read the contents of other apps' windows.

**Screen Recording** (optional). Requested only if you turn on **Show window
previews**. On macOS, both live window thumbnails and *window titles* count as
screen content, so this permission is what makes per-window selection possible.
Turn the setting off and Orbit never requests or uses it. macOS requires an
Orbit restart after you grant it.

**Automation** (conditional fallback). Ordinary switching uses Accessibility.
If direct window focus and the target app's Window menu both fail, Orbit can ask
that app through Apple Events to bring the selected window forward. macOS asks
for this per target app only when that fallback is reached. Declining it leaves
ordinary app switching available; Orbit does not require Automation during setup.

All permissions are managed by macOS, not by Orbit. You can revoke them at
any time in **System Settings → Privacy & Security**, and Orbit will degrade to
its reduced behavior rather than work around the revocation.

## System services

Two features hand your data to macOS itself rather than processing it in Orbit:

- **AirDrop.** Dropping a file on the center target passes it to the standard
  macOS share service. The transfer is macOS's, goes directly to the device you
  pick, and never passes through Orbit or any server.
- **Trash.** Holding a file over the center target past the delay moves it to the
  Trash using the standard file manager API. Orbit never deletes anything
  permanently.

Apple's privacy terms govern what those services do. Orbit adds nothing to them.

## No network, no third parties

Orbit contains no networking code. There is no telemetry, no update check, no
remote configuration, and no third-party SDK, analytics library, or crash
reporter of any kind — the app has no third-party dependencies at all.

You do not have to take our word for it. The source is public: search this
repository for `URLSession`, `NWConnection`, or any analytics vendor's name and
you will find nothing.

## App Sandbox

Orbit is **not** sandboxed, and you should know that. Quitting another
application from the center target is not possible from inside the macOS App
Sandbox, so the entitlement is deliberately disabled. The build does run with
Hardened Runtime enabled.

This is a real trade-off, stated plainly: not being sandboxed means macOS is not
enforcing a boundary around what Orbit could reach. What limits Orbit is the
code itself, which is why the source is public and why this document is specific
rather than reassuring.

## Your rights

Because Orbit never collects or transmits personal data, there is no data to
access, correct, export, or delete, and no one to request it from. Removing
every trace of Orbit means deleting the app and, if you want the settings gone
too, its preferences file in `~/Library/Preferences`.

## Changes

Material changes to this policy will be noted in `CHANGELOG.md` alongside the
release that makes them. If Orbit ever gains a feature that transmits data — it
has none today — that will be opt-in, announced in the release notes, and
described here before it ships.

## Contact

Questions about this policy: open an issue at
https://github.com/ycl-2004/Orbit/issues or contact the maintainer through the
GitHub profile associated with this repository.
