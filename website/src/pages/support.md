---
title: Support
description: Help with installing and using Whisperwell, the push-to-talk dictation app for macOS.
---

# Whisperwell Support

Need help? [Open an issue on GitHub](https://github.com/AbhijeetBabar-2025/whisperwell/issues). Please include your macOS version and what the Whisperwell menu shows.

## Getting started

1. Open Whisperwell. A microphone icon appears in the menu bar.
2. On first launch it downloads the speech model (about 600 MB). The menu shows "Speech: … ✓ ready" when it's done.
3. The setup window lists the permissions Whisperwell needs (**Microphone**, **Input Monitoring**, **Accessibility**), with a button that opens the right page in System Settings for each. Then click **Restart Whisperwell**.
4. Click into any text field in any app, hold **Right Option (⌥)** until you hear the start sound (about a third of a second), speak, and let go.

## Common questions

**Nothing happens when I hold the key.**
Check that Whisperwell is allowed under Input Monitoring, then quit and reopen it. Your hotkey is shown in the Whisperwell menu.

**The text doesn't appear.**
Whisperwell needs Accessibility permission to paste, and it won't paste into password fields. Click into a text field before you let go of the key: if nothing that takes text is selected, Whisperwell leaves your text on the clipboard and tells you, so you can press ⌘V yourself.

**A website won't let me paste.**
Some forms block pasting. Whisperwell notices and types the text in instead. If that doesn't work either, the text is on your clipboard.

**A quick tap of Option doesn't start dictation.**
That's intended. Dictation starts once you've held the key for about a third of a second, so quick taps and Option shortcuts never pop up the indicator.

**Typing Option + a letter cancels dictation.**
That's intended, so Option shortcuts and accented characters (such as Option+E) keep working. Hold the hotkey on its own while you speak.

**"Not reachable" next to Cleanup.**
Whisperwell can't reach your cleanup model. Make sure the model server is running. If it's on another computer, allow Whisperwell under **Privacy & Security › Local Network** and relaunch. Hover over the menu line to see the exact reason. Dictation still works and pastes the raw transcript.

**How do I change settings?**
Choose **Settings…** (⌘,) from the Whisperwell menu. Saving restarts Whisperwell to apply your changes.

**Does it work offline?**
Yes, once the speech model is downloaded, unless you've chosen a cloud service for speech or cleanup.

**How do I remove Whisperwell completely?**
Quit it, move it to the Trash, and delete these folders:
- `~/Library/Application Support/Whisperwell` (the speech model)
- `~/.config/whisperwell` (settings)

For the App Store version, settings and the model live in `~/Library/Containers/` under Whisperwell's bundle ID instead.

## Privacy

See the [privacy policy](/privacy).
