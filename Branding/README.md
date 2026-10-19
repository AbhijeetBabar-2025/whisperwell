# Branding

Source and output for the app icon and App Store screenshots. Everything is generated from code,
so edits are reviewable and repeatable.

## Icon

- Source: `scripts/make-icon.swift`, a waveform resolving into a text cursor on an indigo-to-violet squircle.
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
