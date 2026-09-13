# Changelog

Notable RuncatTouchBar changes are tracked here. GitHub Releases remain the canonical downloadable builds.

## Unreleased

### Added
- RunCat runner in the macOS Control Strip while preserving Apple's normal controls.
- Expanded Touch Bar system monitor with CPU, memory, storage, network, battery, and process information.
- Shared RunCat runner selection, custom runner state, metric visibility, and monitoring interval.
- Top CPU process list with normal quit and force-quit actions.
- Activity Monitor shortcut from the expanded Touch Bar.
- Scroll-aware process ranking and in-place row updates.
- GitHub Actions build/package workflow and tag-driven release workflow.

### Changed
- Battery information now comes from the same SystemInfoKit source used by RunCat instead of a separate `pmset` sampler.
- Public documentation reorganized around download, usage, security, and release information.

## Release history

The first public RuncatTouchBar release has not been tagged yet. When a `vX.Y.Z` tag is pushed, add a corresponding section above and move relevant items out of **Unreleased**.
