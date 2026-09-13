# Privacy

RuncatTouchBar is designed as a local macOS utility.

## Touch Bar monitor data

The Touch Bar monitor reads local system information such as CPU, memory, storage, network throughput, battery status, and running user processes. That monitor data is used locally to render the Touch Bar UI.

RuncatTouchBar does not intentionally transmit the Touch Bar process list or system-monitor snapshots to the project author.

## Process control

When you tap a process action, RuncatTouchBar sends a local termination request to that process. No remote service is involved in that action.

## Settings

RuncatTouchBar reuses the settings/storage behavior inherited from RunCat Neo. Runner selection and monitoring preferences remain local application state unless an inherited upstream feature explicitly does otherwise.

## Network note

The repository is derived from RunCat Neo and contains upstream functionality beyond the Touch Bar monitor. This document describes the RuncatTouchBar-specific monitoring layer and should not be read as a blanket claim that every inherited code path can never access the network.

For a security-oriented overview, see [SECURITY.md](./SECURITY.md).
