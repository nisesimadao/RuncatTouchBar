# Demo Asset Checklist

Use this when replacing the README placeholders with real Touch Bar captures.

## Assets to capture

- `docs/assets/touchbar-overview.*` — RunCat visible inside the normal Control Strip with several Apple controls still present.
- `docs/assets/expanded-monitor.*` — expanded monitor showing CPU plus at least several enabled metrics and process rows.
- `docs/assets/settings.*` — RunCat settings showing the shared system-metric toggles / refresh interval.
- Optional short clip — tap RunCat → expanded monitor → horizontal process swipe → return to Control Strip.

The README currently references `.svg` placeholder files. When final images are ready, either replace those files or update both README files to the final PNG/WebP names.

## Capture guidance

- Use a real Touch Bar Mac and the release-candidate build.
- Keep private notifications, usernames, file paths, and unrelated app content out of frame.
- For the process monitor screenshot, choose ordinary applications and avoid sensitive process names.
- Make the Control Strip context visible; the important point is that RuncatTouchBar coexists with Apple controls.
- Keep the expanded monitor readable rather than trying to fit every optional metric into one shot.
- Capture one English and one Japanese pass during QA, even if only one language is used publicly.
- Avoid generated/mock Touch Bar screenshots for the final README. Real hardware proof is more useful here.

## Suggested macOS command

Interactive screenshot:

```bash
screencapture -i ~/Desktop/runcat-touchbar.png
```

For a short recording, recording the MacBook with a phone/camera may communicate Touch Bar interaction better than a normal screen recording because the Touch Bar is separate hardware.
