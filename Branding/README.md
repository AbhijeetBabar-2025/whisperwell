# Branding

Source and output for the app icon and App Store screenshots. Everything is generated from code,
so edits are reviewable and repeatable.

## Logo

- `Logo/mark-light.svg` (violet, for light backgrounds), `Logo/mark-dark.svg` (white, for dark backgrounds), and `Logo/mark-tile.svg` (the mark on the brand gradient, used as the website favicon and hero icon).
- Design: one continuous sound wave shaped like a lowercase "w" (the voice, and the brand initial) beside a mint text cursor (where the words land). It is drawn on a 100-unit grid; `scripts/make-icon.swift` draws the same path for the app icon, so change both together.
- Keep clear space of at least half the mark's width around it, and don't recolor the cursor: mint is the "text lands here" accent. On light backgrounds the cursor uses a deeper mint (`#2BC9A0`) for contrast.
- The website uses copies in `website/static/img/` (`logo.svg`, `logo-dark.svg`, `favicon.svg`).

## Icon

- Source: `scripts/make-icon.swift`, the logo mark on an indigo-to-violet squircle.
- Output: `Icon/AppIcon-1024.png` (upload to App Store Connect) and `Support/AppIcon.icns` (bundled in the app).

```bash
swift scripts/make-icon.swift
iconutil -c icns Branding/Icon/AppIcon.iconset -o Support/AppIcon.icns
```

## Screenshots

- Source: `Screenshots/src/*.html` + `style.css` (laid out at 1440×900, rendered at 2x).
- Output: `Screenshots/0N-*.png`, 2880×1800, the size App Store Connect accepts for Mac.
- Every example sentence on the slides was produced by the real app (`Whisperwell --transcribe`). Re-check them if you change the cleanup prompt or model.

```bash
swiftc -O scripts/render-html.swift -o /tmp/render-html
for f in Branding/Screenshots/src/0*.html; do
  /tmp/render-html "$PWD/$f" "$PWD/Branding/Screenshots/$(basename "$f" .html).png" 2880 1800
done
```

## Palette

| Name | Hex | Use |
|---|---|---|
| Indigo | `#2A2F7A` | Backgrounds |
| Violet | `#5B3FD1` | Primary brand color |
| Lilac | `#8E5BF5` | Gradient highlight |
| Mint | `#6BF5CF` | Accent: the cursor, "ready" states |
