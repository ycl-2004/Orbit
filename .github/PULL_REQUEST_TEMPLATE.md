<!-- Please open an issue before a large change. See CONTRIBUTING.md. -->

## Summary

<!-- What changes, and why. One logical change per PR. -->

Closes #

## Verification

- [ ] `xcodebuild ... build` passes
- [ ] `xcodebuild ... test -only-testing:OrbitTests` passes
- [ ] Installed via `scripts/install.sh` and tried it as a user would

Manual checks run (delete what does not apply):

- [ ] Trigger — ring appears near the cursor, release switches, Escape cancels
- [ ] Keyboard — arrows/Tab navigate, clear-selection key removes the highlight
- [ ] Window previews — enabled, Screen Recording granted, Orbit restarted, left/right picks a window
- [ ] Center target — app quit, file AirDrop, hold-to-Trash
- [ ] Settings persist across an Orbit restart

## Notes

- [ ] This changes interaction semantics, permissions, or distribution, so it includes an ADR in `docs/decisions/`
- [ ] User-visible strings changed, and localizations are updated (say which ones are still pending)
- [ ] `README.md` and `README.zh-CN.md` are in sync
- [ ] No build products, `DerivedData`, Team ID, or personal bundle identifiers are committed

<!-- Screenshots or a short recording for anything visual. -->
