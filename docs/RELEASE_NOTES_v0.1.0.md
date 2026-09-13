# RuncatTouchBar v0.1.0

The first public release of RuncatTouchBar — RunCat in the MacBook Pro Control Strip with a compact system monitor one tap away.

## Highlights

- Keep RunCat beside Apple's normal Control Strip controls instead of replacing the whole Touch Bar.
- Tap RunCat to open CPU, memory, storage, network, battery, and top-process information directly on the Touch Bar.
- Browse active processes horizontally and request normal quit or force quit without opening Activity Monitor.

## Touch Bar

- Selected RunCat runner and CPU-driven animation speed are shared with RunCat Neo.
- Memory / Storage / Network / Battery visibility follows the existing RunCat settings.
- Refresh interval follows RunCat's 3 / 5 / 10 second monitoring setting.
- Process rows show app icons, localized app names when available, and CPU usage.
- Long process names truncate independently, so CPU percentages remain visible.
- Includes a direct Activity Monitor shortcut for deeper inspection.

## Reliability / polish

- Process rows are reused in place instead of recreated on every sample.
- CPU ranking changes are delayed while the process list is actively being swiped.
- Battery data now comes from the same SystemInfoKit source as the main RunCat UI.
- Physical Touch Bar screenshots are included in the English and Japanese READMEs.

## Install

1. Download `RuncatTouchBar.zip` from this release.
2. Unzip it and move `RuncatTouchBar.app` to `/Applications`.
3. If Gatekeeper blocks the first launch, right-click the app and choose **Open**.

This build is ad-hoc signed, but is not Developer ID signed or notarized.

> RuncatTouchBar uses private macOS Touch Bar APIs and is experimental. A future macOS update may affect Control Strip integration.

## Tested

- GitHub Actions: macOS 26 arm64 Release build / packaging
- Physical Touch Bar: Control Strip runner, expanded monitor, system metrics, horizontal process list, app icons, CPU percentages, normal quit / force-quit UI, and Activity Monitor shortcut visually verified on hardware

Because this is the first public release, there is no previous release tag to compare against.
