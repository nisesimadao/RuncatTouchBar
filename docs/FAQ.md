# FAQ

## What is RuncatTouchBar?

RuncatTouchBar is an experimental macOS utility derived from RunCat Neo. It places the selected RunCat runner in the Touch Bar Control Strip. Tapping the runner opens a compact system and process monitor.

## Does it replace the normal Control Strip?

No. RuncatTouchBar adds one system-tray item and keeps Apple's normal brightness, volume, and other controls available.

## Why does it require a Touch Bar Mac?

The main feature uses `NSTouchBar` and private Control Strip APIs. Macs without a physical Touch Bar cannot display the integration.

## Why is macOS 26 required?

The current codebase and Swift package target macOS 26, matching the RunCat Neo base used by this repository.

## Why does macOS say the app cannot be opened?

Public builds are ad-hoc signed. They are not Developer ID signed or notarized, so Gatekeeper may block the first launch.

First, right-click the app and choose **Open**. If needed, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/RuncatTouchBar.app
```

## Why is App Sandbox disabled?

The process monitor needs to inspect user processes and request normal or forced termination. The RuncatTouchBar target therefore runs without App Sandbox. See [Security](./SECURITY.md) for the trade-offs.

## Does RuncatTouchBar use private APIs?

Yes. Apple does not provide a public API for third-party Control Strip system-tray items, so the required private symbols are resolved dynamically at runtime. If they are unavailable, the Touch Bar integration does not start.

## Does it upload my process list or system metrics?

The Touch Bar monitor processes its CPU, process, and system information locally and does not intentionally upload that monitor data. Because the project is derived from RunCat Neo, review the source and [Privacy](./PRIVACY.md) documentation if you need to audit inherited behavior as well.

## Why does the process order sometimes wait before changing?

The process list avoids aggressive reordering while you are swiping. Once scrolling becomes idle, the CPU ranking can update without moving rows under your finger as often.

## Can I use an Intel Touch Bar Mac?

The source may be adaptable, but the current public workflow produces an **arm64-only** app. Intel Macs are not currently advertised as supported downloadable builds.

## Where can I see screenshots?

The main [README](../README.md) includes the Control Strip, expanded monitor, and shared-settings screenshots. [DEMO_ASSETS.md](./DEMO_ASSETS.md) documents the screenshot set used for releases and documentation.
