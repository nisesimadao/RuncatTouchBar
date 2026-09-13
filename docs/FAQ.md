# FAQ

## What is RuncatTouchBar?

RuncatTouchBar is a RunCat Neo-derived macOS utility that places the active RunCat runner in the Touch Bar Control Strip. Tapping it opens a compact system/process monitor.

## Does it replace the normal Control Strip?

No. The project adds a system-tray item and keeps the normal brightness, volume, and other Apple controls available.

## Why does it require a Touch Bar Mac?

The main feature is implemented with `NSTouchBar` and private Control Strip APIs. Macs without a physical Touch Bar cannot display the integration.

## Why is macOS 26 required?

The current codebase and Swift package target macOS 26, matching the RunCat Neo base currently used by this repository.

## Why does macOS say the app cannot be opened?

Public builds are ad-hoc signed, not Developer ID signed or notarized. First try right-clicking the app and choosing **Open**. If necessary:

```bash
xattr -dr com.apple.quarantine /Applications/RuncatTouchBar.app
```

## Why is App Sandbox disabled?

The process monitor needs to inspect user processes and request normal/forced termination. The RuncatTouchBar target therefore runs unsandboxed. See [Security](./SECURITY.md).

## Does RuncatTouchBar use private APIs?

Yes. Apple does not provide a public API for third-party Control Strip system-tray items. The private symbols are resolved dynamically at runtime. If they are unavailable, the Touch Bar integration does not start.

## Does it upload my process list or system metrics?

The RuncatTouchBar Touch Bar monitor processes its CPU/process/system information locally and does not intentionally upload that monitor data. The repository is derived from RunCat Neo, so review the source and privacy documentation if you need to audit all inherited features.

## Why does the process order sometimes wait before changing?

The list intentionally avoids aggressive reordering while you are swiping. Once scrolling is idle, CPU ranking can catch up without moving rows under your finger as often.

## Can I use an Intel Touch Bar Mac?

The source may be adaptable, but the current public workflow produces an **arm64-only** app. Intel is not currently advertised as a supported downloadable build.

## Where are screenshots?

The README currently uses placeholders. See [DEMO_ASSETS.md](./DEMO_ASSETS.md) for the exact shots to capture on physical hardware.
