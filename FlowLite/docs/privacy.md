---
title: FlowLite Privacy Policy
---

# FlowLite Privacy Policy

_Last updated: October 19, 2026_

FlowLite is a dictation app for macOS. This policy explains what happens to your voice and text when you use it.

## The short version

- The developer of FlowLite collects **no data**. There are no accounts, servers, analytics, advertising, or tracking.
- By default, speech recognition runs **entirely on your Mac**, and your audio is not uploaded anywhere.
- If you choose to connect a cloud AI service, your audio or text goes **directly from your Mac to that service**, under your own account. It never passes through the developer.

## What FlowLite processes, and where

**Your voice.** FlowLite records the microphone only while you hold the dictation hotkey. The recording stays in memory, is turned into text, and is discarded. It is never saved to disk.

- *On-device mode (default):* the Whisper speech model runs on your Mac. Audio never leaves your computer.
- *API mode (optional):* if you set a speech-to-text service (such as OpenAI or Groq) in the settings, each recording is sent to that service to be transcribed.

**Text around your cursor.** To get punctuation and capitalization right, FlowLite reads the text field you're typing into and the name of the app. Only up to 500 characters on each side of the cursor are ever used or sent, and only when a cleanup model is set up. It never reads password fields.

**Text cleanup (optional).** If you set up a cleanup model, the transcript and the nearby text above are sent to the model you chose:

- *A model on your own computer or local network* (for example LM Studio or Ollama): the data stays on your devices.
- *A cloud model* (for example Anthropic's Claude): the data goes to that provider using your API key.

**Your clipboard.** FlowLite inserts text by pasting it. It saves your clipboard first and restores it about half a second later. Pasted text is marked so clipboard managers skip it.

**Your settings.** Settings, API keys, and your personal dictionary are stored in a file on your Mac that only your user account can read. They are never sent to the developer.

**The speech model.** On first use, FlowLite downloads the Whisper model from Hugging Face. That download is a normal web request; it doesn't include your audio or text.

## Third-party services you may choose

If you connect a cloud service, its own privacy policy applies to the data you send it:

- OpenAI: https://openai.com/policies/privacy-policy
- Groq: https://groq.com/privacy-policy
- Anthropic: https://www.anthropic.com/legal/privacy
- Hugging Face (model download): https://huggingface.co/privacy

## Logs

FlowLite writes short diagnostic messages to the macOS system log (for example "Inserted 42 characters"). It never logs what you said or typed. The logs stay on your Mac.

## Children

FlowLite does not knowingly collect information from anyone, including children.

## Changes

If this policy changes, the new version will be posted at this address with a new date.

## Contact

Questions about privacy: **support@YOUR-DOMAIN**
