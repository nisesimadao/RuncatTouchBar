# Release Checklist

Use this before pushing a public `vX.Y.Z` tag.

## Build / version

- [x] Update `docs/CHANGELOG.md`.
- [x] Choose the intended `vX.Y.Z` tag: `v0.1.0`.
- [x] Confirm `main` Build & Package is green for the current Touch Bar code.
- [x] Confirm the project builds with macOS 26 / current stable Xcode in CI.
- [ ] Push the tag only after the remaining physical Touch Bar verification below.
- [ ] Confirm the Build & Release workflow publishes `RuncatTouchBar.zip` and `RuncatTouchBar.zip.sha256`.
- [ ] Download the actual release ZIP and verify its SHA-256 file.

## Physical Touch Bar QA

- [x] Run the release-candidate code on a Touch Bar MacBook Pro.
- [x] Confirm RunCat appears in Control Strip without removing Apple's controls.
- [x] Confirm the expanded monitor renders CPU / RAM / Storage / Battery and process information on hardware.
- [x] Confirm long process names truncate without hiding CPU percentages.
- [x] Confirm the force-quit icon is visually distinct in red.
- [ ] Confirm animation follows the selected RunCat runner and CPU-driven speed.
- [ ] Tap the runner repeatedly and confirm the modal does not duplicate or get stuck.
- [ ] Confirm CPU / RAM / Storage / Network / Battery visibility follows RunCat settings.
- [ ] Change the RunCat update interval and confirm Touch Bar refresh follows it.
- [ ] Swipe the process list and confirm it does not jump aggressively during the gesture.
- [ ] Confirm old process rankings eventually refresh after scrolling stops.
- [ ] Confirm normal Quit targets the intended process.
- [ ] Confirm Force Quit targets the intended process.
- [ ] Confirm the Activity Monitor shortcut opens the correct macOS app.
- [ ] Close/minimize the expanded Touch Bar and confirm the Control Strip runner remains available.
- [ ] Sleep/wake once and confirm the tray item returns.

## Documentation

- [x] Replace screenshot placeholders with physical Touch Bar captures.
- [x] Update the expanded-monitor capture after CPU-percentage layout polish.
- [x] Check English and Japanese README screenshot references.
- [ ] Confirm the Latest release badge resolves to the new release after publication.
- [x] Confirm installation/Gatekeeper text still matches the current ad-hoc-signed distribution plan.
- [x] Confirm supported architecture/macOS requirements are documented.

## Release notes

- [x] Prepare `RELEASE_NOTES_v0.1.0.md`.
- [x] Mention that the build is ad-hoc signed and not notarized.
- [x] Mention that the app uses private Touch Bar APIs and is experimental.
- [x] Separate hardware-verified behavior from CI-only build verification.
