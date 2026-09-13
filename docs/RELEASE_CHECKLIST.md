# Release Checklist

Use this before pushing a public `vX.Y.Z` tag.

## Build / version

- [ ] Update `docs/CHANGELOG.md`.
- [ ] Choose the intended `vX.Y.Z` tag.
- [ ] Confirm `main` Build & Package is green.
- [ ] Confirm the project still builds with macOS 26 / current stable Xcode.
- [ ] Push the tag only after physical Touch Bar verification.
- [ ] Confirm the Build & Release workflow publishes `RuncatTouchBar.zip` and `RuncatTouchBar.zip.sha256`.
- [ ] Download the actual release ZIP and verify its SHA-256 file.

## Physical Touch Bar QA

- [ ] Run the exact release candidate on a Touch Bar MacBook Pro.
- [ ] Confirm RunCat appears in Control Strip without removing Apple's controls.
- [ ] Confirm animation follows the selected RunCat runner and CPU-driven speed.
- [ ] Tap the runner repeatedly and confirm the modal does not duplicate or get stuck.
- [ ] Confirm CPU / RAM / Storage / Network / Battery visibility follows RunCat settings.
- [ ] Change the RunCat update interval and confirm Touch Bar refresh follows it.
- [ ] Swipe the process list and confirm it does not jump aggressively during the gesture.
- [ ] Confirm old process rankings eventually refresh after scrolling stops.
- [ ] Confirm normal Quit targets the intended process.
- [ ] Confirm Force Quit targets the intended process and the destructive icon is visually distinct.
- [ ] Confirm the Activity Monitor shortcut opens the correct macOS app.
- [ ] Close/minimize the expanded Touch Bar and confirm the Control Strip runner remains available.
- [ ] Sleep/wake once and confirm the tray item returns.

## Documentation

- [ ] Replace stale screenshot placeholders when final screenshots are available.
- [ ] Check English and Japanese README links.
- [ ] Confirm the Latest release badge resolves to the new release.
- [ ] Confirm installation/Gatekeeper text still matches current behavior.
- [ ] Confirm supported architecture/macOS requirements are accurate.

## Release notes

- [ ] Start from `RELEASE_NOTES_TEMPLATE.md` or generated GitHub notes.
- [ ] Mention that the build is ad-hoc signed and not notarized.
- [ ] Mention that the app uses private Touch Bar APIs and is experimental.
- [ ] Separate hardware-verified behavior from CI-only build verification.
