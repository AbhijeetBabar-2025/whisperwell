---
title: Getting started
description: Build Whisperwell, grant its permissions, and dictate your first sentence.
---

# Getting started

Whisperwell is a push-to-talk dictation app for macOS. Hold a key, speak, and let go: your speech is transcribed on your Mac, tidied up, and typed wherever your cursor is.

## Build it

You need macOS 13 or later and Xcode or the Command Line Tools.

```bash
git clone https://github.com/AbhijeetBabar-2025/whisperwell.git
cd whisperwell
./scripts/build-app.sh
open build/Whisperwell.app
```

A microphone icon appears in the menu bar. On first launch Whisperwell downloads the Whisper speech model (about 600 MB) to `~/Library/Application Support/Whisperwell/Models`. The menu shows "… loading" until it's ready. Later launches load it from disk.

## Allow its permissions

A setup window lists what's missing, with a button that opens the right page in System Settings for each. It opens at launch until everything is allowed.

| Permission | Why |
|---|---|
| **Microphone** | To record while you hold the hotkey. |
| **Input Monitoring** | To notice the hotkey. |
| **Accessibility** | To read the field you're typing in and insert the text. |
| **Local Network** | Only if your cleanup model runs on another machine. |

Relaunch Whisperwell after granting them.

:::tip Keep permissions across rebuilds
macOS ties permissions to the app's code signature, and an ad-hoc signature changes with every build. Create a self-signed **Code Signing** certificate named `Whisperwell Development` in Keychain Access once, and `build-app.sh` signs with it automatically. The [README](https://github.com/AbhijeetBabar-2025/whisperwell#development-signing) has the steps.
:::

## Dictate

1. Click into any text field, in any app.
2. Hold **Right Option (⌥)** until you hear a soft "tink" (about a third of a second).
3. Speak, then let go.

The text appears where your cursor is. Quick taps of Option and Option shortcuts are ignored, so they keep working as usual.

## Choose a cleanup model

Cleanup removes filler words, applies corrections ("at five, actually six"), and adds punctuation. Open **Settings…** (⌘,) from the menu and pick one:

- **Claude**, with your Anthropic API key.
- **A local model** through LM Studio, Ollama, or llama.cpp. See [Local AI](./local-ai.md).
- **No cleanup**, to type exactly what Whisper heard.

Saving restarts Whisperwell to apply the change.
