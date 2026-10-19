---
title: FlowLite Support
---

# FlowLite Support

Need help? Email **support@YOUR-DOMAIN**. Please include your macOS version and what the FlowLite menu shows.

## Getting started

1. Open FlowLite. A microphone icon appears in the menu bar.
2. On first launch it downloads the speech model (about 600 MB). The menu shows "Speech: … ✓ ready" when it's done.
3. The setup window lists the permissions FlowLite needs (**Microphone**, **Input Monitoring**, **Accessibility**), with a button that opens the right page in System Settings for each. Then click **Restart FlowLite**.
4. Click into any text field, hold **Right Option (⌥)**, speak, and let go.

## Common questions

**Nothing happens when I hold the key.**
Check that FlowLite is allowed under Input Monitoring, then quit and reopen it. Your hotkey is shown in the FlowLite menu.

**The text doesn't appear.**
FlowLite needs Accessibility permission to paste. It also won't paste into password fields.

**Typing Option + a letter cancels dictation.**
That's intended, so Option shortcuts and accented characters (such as Option+E) keep working. Hold the hotkey on its own while you speak.

**"Not reachable" next to Cleanup.**
FlowLite can't reach your cleanup model. Make sure the model server is running. If it's on another computer, allow FlowLite under **Privacy & Security › Local Network** and relaunch. Hover over the menu line to see the exact reason. Dictation still works and pastes the raw transcript.

**How do I change settings?**
Choose **Settings…** (⌘,) from the FlowLite menu. Saving restarts FlowLite to apply your changes.

**Does it work offline?**
Yes, once the speech model is downloaded, unless you've chosen a cloud service for speech or cleanup.

**How do I remove FlowLite completely?**
Quit it, move it to the Trash, and delete these folders:
- `~/Library/Application Support/FlowLite` (the speech model)
- `~/.config/flowlite` (settings)

For the App Store version, settings and the model live in `~/Library/Containers/` under FlowLite's bundle ID instead.

## Privacy

See the [privacy policy](privacy.md).
