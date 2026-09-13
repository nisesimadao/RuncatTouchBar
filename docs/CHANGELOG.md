# Changelog

Notable RuncatTouchBar changes are tracked here. GitHub Releases remain the canonical downloadable builds.

## Unreleased

_No user-facing changes yet._

## v0.1.0 — 2026-09-13

### Added
- RunCat runner in the macOS Control Strip while preserving Apple's normal brightness, volume, and other controls.
- Tap-to-expand Touch Bar system monitor with CPU, memory, storage, network, battery, and process information.
- Shared RunCat runner selection, custom runner state, metric visibility, and monitoring interval.
- Top CPU process list with application icons, CPU usage, normal quit, and force-quit actions.
- Activity Monitor shortcut from the expanded Touch Bar.
- Horizontal process scrolling with scroll-aware ranking updates and in-place row reuse.
- GitHub Actions build/package workflow and tag-driven release workflow.
- English and Japanese public documentation with physical Touch Bar screenshots.

### Changed
- Battery information uses the same SystemInfoKit source as RunCat instead of a separate `pmset` sampler.
- Process names prefer the localized macOS application name when available.
- Process name and CPU percentage are rendered separately so long names can truncate without hiding CPU usage.
- Public documentation reorganized around download, usage, security, privacy, and release information.

### Validated
- arm64 Release build and ZIP packaging succeed in GitHub Actions.
- Physical Touch Bar Control Strip integration works on a real Touch Bar Mac while preserving Apple's controls.
- CPU-driven runner animation, repeated open/close, shared metric visibility, refresh interval changes, horizontal scrolling/ranking refresh, normal Quit, Force Quit, Activity Monitor shortcut, modal minimize/return, and sleep/wake recovery were tested successfully on hardware.
- Long process names truncate without hiding CPU percentages, and the force-quit control remains visually distinct in red.

## Release history

`v0.1.0` is the first planned public RuncatTouchBar release.
