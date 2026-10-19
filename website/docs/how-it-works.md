---
title: How it works
description: What happens between pressing the hotkey and the text appearing.
---

# How it works

```
Hold hotkey  ▶ read the focused text field ▶ record the microphone (16 kHz mono)
Release      ▶ Whisper (on-device or API) ▶ cleanup (Claude or local model) ▶ insert
```

## While you hold the key

- The microphone starts the moment you press, so your first words aren't clipped. Dictation counts once you've held the key for 0.3 seconds: that's when the sound plays and the floating indicator appears.
- Pressing another key while holding the hotkey cancels, so Option+E still types é.
- With on-device speech, Whisperwell transcribes about once a second while you talk and keeps each finished part at your pauses. Letting go only has to transcribe the last few seconds. With live preview on, the indicator shows your words as you speak.

## Cleanup

Whisperwell sends the transcript, plus up to 500 characters on each side of your cursor, to the cleanup model you chose. The nearby text helps with capitalization and punctuation. Cleanup never repeats text that's already in the field. If a model echoes it anyway, Whisperwell strips it.

Short replies (four words or fewer, with no fillers or corrections) skip cleanup so they appear almost instantly. If cleanup fails, Whisperwell inserts the raw transcript instead.

## Inserting the text

The text goes wherever your cursor is when it's ready, in any app:

1. Whisperwell checks what has focus. It never inserts into password fields.
2. It puts the text on the clipboard and presses ⌘V, using whichever key types "v" in your keyboard layout (so Dvorak and AZERTY work too).
3. In a text field that reports its contents, it checks the text arrived. If the field ignored ⌘V (some web forms block pasting), Whisperwell types the text in instead.
4. Your previous clipboard comes back about 0.6 seconds later. The pasted text is marked so clipboard managers skip it.

If nothing that takes text is focused, or the field rejects both pasting and typing, the text stays on your clipboard and the indicator tells you to press ⌘V. A dictation is never silently lost.

Electron apps such as VS Code, Slack, and Discord hide their text fields from macOS until asked. Whisperwell asks the first time you dictate into one, so cleanup can see the surrounding text.

## Logs

```bash
/usr/bin/log stream --predicate 'subsystem == "local.whisperwell"'
```

Use the full path: in zsh, plain `log` is a built-in math command. What you said is never logged, only lengths and timings.
