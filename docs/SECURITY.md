# Security

RuncatTouchBar deliberately uses capabilities that deserve extra scrutiny.

## Private Touch Bar APIs

Apple does not expose a supported public API for third-party Control Strip system-tray items. RuncatTouchBar dynamically resolves private Touch Bar APIs at runtime.

Consequences:

- a future macOS update can change or remove those APIs;
- the Control Strip feature may stop working even when the app still launches;
- this architecture is not appropriate for Mac App Store distribution.

The integration is guarded so it does not start when the required symbols cannot be found.

## App Sandbox

The RuncatTouchBar app target disables App Sandbox because the process monitor needs to inspect and terminate other user processes.

That means the app is less isolated than a sandboxed Mac App Store utility. Only run builds you trust, and prefer artifacts published from this repository's GitHub Actions workflow.

## Process termination

The expanded Touch Bar can request normal termination and forced termination of displayed processes. Force quit can cause unsaved work to be lost. The UI distinguishes the force action visually, but users should still treat it as destructive.

## Signing / notarization

Public workflow builds are ad-hoc signed. They are not Developer ID signed or notarized. Verify the SHA-256 file published alongside a release if you need to confirm the downloaded ZIP matches the release asset.

## Reporting issues

For non-sensitive bugs, use GitHub Issues. If you discover a security issue that should not be public immediately, avoid posting exploit details in a public issue until a private reporting path is available.
