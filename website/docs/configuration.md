---
title: Configuration
description: Every Whisperwell setting, its default, and what it does.
---

# Configuration

**Settings…** (⌘,) in the menu covers everything below. API keys are saved in your login Keychain (items named "Whisperwell"). Everything else is saved to `~/.config/whisperwell/config.json`, readable only by you, which you can also open from the menu's **Open Config File**. A key typed into that file works, and is moved to the Keychain the next time Whisperwell starts.

## Dictation

| Field | Default | Notes |
|---|---|---|
| `hotkey` | `rightOption` | `rightOption`, `rightCommand`, or `fn`. For `fn`, set System Settings › Keyboard › "Press 🌐 key to" to *Do Nothing*. |
| `playSounds` | `true` | A soft sound when the mic starts listening (your cue to talk) and when it stops. |
| `showIndicator` | `true` | A floating pill at the bottom of the screen: a live waveform while listening, then "Transcribing…". |
| `livePreview` | `true` | Show your words in the indicator as you speak (on-device speech only). |
| `skipCleanupMaxWords` | `4` | Insert transcripts this short as-is, unless they contain fillers or corrections. `0` always cleans up. |
| `dictionary` | `[]` | Spellings that guide both speech-to-text and cleanup. |
| `language` | auto | An ISO code such as `en`. |

## Speech-to-text

| Field | Default | Notes |
|---|---|---|
| `asrProvider` | `whisperkit` | `whisperkit` (on-device) or `api` (a transcription API). |
| `whisperModel` | `large-v3-v20240930_626MB` | WhisperKit only. Any name from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml), such as `small.en` (smaller, faster). |
| `whisperModelRepo` | none | WhisperKit only. A Hugging Face repo with your own Core ML Whisper models. |
| `whisperModelFolder` | none | WhisperKit only. A model folder on disk; skips downloading. |
| `asrBaseURL` | `https://api.openai.com/v1` | API only. Any OpenAI-compatible endpoint. Groq: `https://api.groq.com/openai/v1`. |
| `asrModel` | `gpt-4o-mini-transcribe` | API only. Groq: `whisper-large-v3-turbo`. |
| `asrAPIKey` | none | API only. Or export `OPENAI_API_KEY` / `WHISPERWELL_ASR_API_KEY`. A server on `localhost` needs none. |

## Cleanup

| Field | Default | Notes |
|---|---|---|
| `cleanupEnabled` | `true` | `false` inserts the raw transcript. |
| `cleanupProvider` | `anthropic` | `anthropic` (Claude) or `local` (a model you run). |
| `anthropicAPIKey` | none | Claude only. Or export `ANTHROPIC_API_KEY`. |
| `cleanupModel` | `claude-haiku-5-5` | Claude only. Fast and inexpensive. `claude-opus-5-5` rewrites more carefully but is slower. |
| `cleanupEffort` | `low` | Claude only. `""` leaves it out, for models without effort support. |
| `localLLMBaseURL` | `http://localhost:11434/v1` | Local only. Ollama's address. LM Studio: `http://127.0.0.1:1234/v1`. |
| `localLLMModel` | `llama3.2` | Local only. `""` uses whichever chat model the server has loaded. |
| `localLLMAPIKey` | none | Local only. Most local servers don't need one. |

Environment variables override the API keys when you run the binary from a terminal. The menu shows which speech and cleanup models are active and whether they're ready.
