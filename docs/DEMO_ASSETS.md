# Screenshot checklist

The README now uses real screenshots captured on a Touch Bar Mac.

## Current assets

- `docs/assets/touchbar-overview.webp` — normal Control Strip with RunCat beside Apple's controls
- `docs/assets/expanded-monitor.webp` — expanded CPU / RAM / Battery / process monitor
- `docs/assets/settings.webp` — RunCat Neo settings shared with RuncatTouchBar

## When replacing screenshots later

1. Keep the full Touch Bar visible and avoid cropping off Apple's Control Strip controls.
2. Use a reasonably neutral app/process set when capturing the expanded monitor.
3. Keep the settings window at a readable scale.
4. Prefer WebP for README images to keep repository size and page load small.
5. Update both `README.md` and `README_jp.md` if filenames change.

## Capture guidance

- Use a real Touch Bar Mac and the release-candidate build.
- Keep private notifications, usernames, file paths, and unrelated app content out of frame.
- For the process monitor screenshot, choose ordinary applications and avoid sensitive process names.
- Make the Control Strip context visible; the important point is that RuncatTouchBar coexists with Apple controls.
- Avoid generated/mock Touch Bar screenshots for the final README. Real hardware proof is more useful here.

## Suggested macOS command

Interactive screenshot:

```bash
screencapture -i ~/Desktop/runcat-touchbar.png
```

For a short recording, recording the MacBook with a phone/camera can communicate Touch Bar interaction better than a normal screen recording because the Touch Bar is separate hardware.
