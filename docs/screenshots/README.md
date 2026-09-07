# Phase 2 design QA screenshots

Regenerate with:

```bash
dist/Hypertime.app/Contents/MacOS/Hypertime --screenshots docs/screenshots
```

Every screen is rendered in four modes: `light`, `dark`, `light-contrast` and `dark-contrast`
(the last two are macOS Increase Contrast).

Two things to know when reading them:

- **Materials are rendered as their Reduce Transparency fallback.** `NSVisualEffectView` is
  composited by the window server and cannot be captured off screen, so these images double as
  the Reduce Transparency proof. Live glass has to be checked on screen.
- **The live amount is a fixture.** The renderer never ticks the clock, so `0:12:34` is set
  directly; `Discard` therefore reads as disabled (the real pending bucket is empty).
