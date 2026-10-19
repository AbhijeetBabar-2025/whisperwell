# Whisperwell

A minimal push-to-talk dictation app for macOS, modeled on how Wispr Flow works.
Hold a key, speak, let go: your speech is transcribed on your Mac, cleaned up by an AI model, and pasted wherever your cursor is.

By default speech-to-text runs on-device with [WhisperKit](https://github.com/argmaxinc/WhisperKit): free, offline, no API key. Cleanup can use Claude or a local model (LM Studio, Ollama, llama.cpp).

```
Hold hotkey ─▶ read focused text field (Accessibility) ─▶ record mic (16 kHz mono)
Release     ─▶ Whisper (on-device or API) ─▶ cleanup (Claude or local model) ─▶ clipboard + ⌘V ─▶ restore clipboard
```

The text goes wherever the cursor is when it's ready, in any app. If a text field ignores ⌘V (some web forms block pasting), Whisperwell types the text instead. If nothing that takes text is focused, or neither works, your text stays on the clipboard so you can paste it yourself. ⌘V follows your keyboard layout (Dvorak, AZERTY, and so on), and Electron apps such as VS Code and Slack are asked to expose their text fields so cleanup can see them.

To try insertion without dictating: `open -n build/Whisperwell.app --args --insert-test "some text" --into "TextEdit"`. It waits 3 seconds, inserts into the focused field if TextEdit is frontmost, and prints what happened (add `--stdout <file>` before `--args` to capture it).

## Setup

1. **Build** (needs Xcode or the Command Line Tools, macOS 13+):
   ```bash
   ./scripts/build-app.sh
   open build/Whisperwell.app
   ```
   On first launch Whisperwell downloads the Whisper model (about 600 MB) to `~/Library/Application Support/Whisperwell/Models`. The menu shows "… loading" until it's ready; later launches load it from disk.
2. **Grant permissions.** A setup window lists what's missing, with a button for each. It opens at launch until everything is allowed; the menu shows "⚠ Needs …" until then. You can also allow them yourself in System Settings › Privacy & Security:
   - **Microphone**: to record.
   - **Input Monitoring**: to see the hotkey.
   - **Accessibility**: to read the focused text field and press ⌘V.
   - **Local Network**: only if your model server is on another machine.

   Relaunch after granting. To keep these permissions across rebuilds, set up [development signing](#development-signing) once.
3. **Choose a cleanup model** in the menu bar mic › **Settings…** (⌘,): a Claude API key, a local model (see [Local AI](#local-ai)), or no cleanup at all. Saving restarts Whisperwell to apply the change.

## Config

Settings… covers everything below. API keys are saved in your login Keychain (items named "Whisperwell"). Everything else is saved to `~/.config/whisperwell/config.json` (readable only by you), which you can also edit directly from the menu's *Open Config File*. A key typed into that file works, and is moved to the Keychain the next time Whisperwell starts.

| Field | Default | Notes |
|---|---|---|
| `hotkey` | `rightOption` | `rightOption`, `rightCommand`, or `fn`. For `fn`, set System Settings › Keyboard › "Press 🌐 key to" to *Do Nothing*. |
| `playSounds` | `true` | A soft sound when the mic starts listening (your cue to talk) and when it stops. |
| `showIndicator` | `true` | A floating pill at the bottom of the screen: live waveform while listening, then "Transcribing…". |
| `livePreview` | `true` | Show your words in the indicator as you speak (on-device speech only). The cleaned-up text is pasted when you let go. Either way, on-device speech transcribes long dictations in pieces at your pauses while you talk, so letting go only has to transcribe the last few seconds. |
| `skipCleanupMaxWords` | `4` | Paste transcripts this short as-is, skipping cleanup, so quick replies appear almost instantly. Cleanup still runs if they contain fillers or corrections ("um", "actually"). `0` always cleans up. |
| `asrProvider` | `whisperkit` | `whisperkit` (on-device) or `api` (a transcription API). |
| `whisperModel` | `large-v3-v20240930_626MB` | WhisperKit only. Any name from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml), e.g. `small.en` (smaller, faster) or `large-v3-v20240930_turbo` (larger, fastest on Mac). |
| `whisperModelRepo` | none | WhisperKit only. A Hugging Face repo with your own Core ML Whisper models, such as a fine-tuned one. |
| `whisperModelFolder` | none | WhisperKit only. A model folder on disk; skips downloading. |
| `asrBaseURL` | `https://api.openai.com/v1` | API only. Any OpenAI-compatible transcription endpoint. Groq: `https://api.groq.com/openai/v1`. A server on `localhost`/`127.0.0.1` needs no `asrAPIKey`. |
| `asrModel` | `gpt-4o-mini-transcribe` | API only. Groq: `whisper-large-v3-turbo`. |
| `asrAPIKey` | none | API only. Or export `OPENAI_API_KEY` / `WHISPERWELL_ASR_API_KEY`. |
| `language` | auto | ISO code like `en`. |
| `cleanupEnabled` | `true` | `false` pastes the raw transcript. |
| `cleanupProvider` | `anthropic` | `anthropic` (Claude) or `local` (a model you run; see below). |
| `anthropicAPIKey` | none | Claude only. Or export `ANTHROPIC_API_KEY`. |
| `cleanupModel` | `claude-haiku-5-5` | Claude only. Fast and cheap. `claude-opus-5-5` gives stronger rewrites, is slower, and adds a server-side fallback if a request is declined. |
| `cleanupEffort` | `low` | Claude only. `""` omits the field (needed for models without effort support). |
| `localLLMBaseURL` | `http://localhost:11434/v1` | Local only. Ollama's address. LM Studio: `http://127.0.0.1:1234/v1`. |
| `localLLMModel` | `llama3.2` | Local only. `""` uses whichever chat model the server has loaded. |
| `localLLMAPIKey` | none | Local only. Most local servers don't need one. |
| `dictionary` | `[]` | Spellings that guide both speech-to-text and cleanup. |

Environment variables override the API keys when you run the binary from a terminal.
If cleanup fails (no key, server not running, refusal), Whisperwell pastes the raw transcript instead.
The menu shows which speech and cleanup models are active and whether they're ready.

## Local AI

Everything can run without cloud services: WhisperKit for speech (the default) plus a local model for cleanup. Set `"cleanupProvider": "local"`, then:

- **LM Studio:** load a model, open the Developer tab, and start the server. Use `"localLLMBaseURL": "http://127.0.0.1:1234/v1"` and `"localLLMModel": ""` to use the loaded model.
- **Ollama:** `ollama pull llama3.2`, keep Ollama running, and keep the defaults.
- **llama.cpp:** `llama-server -m model.gguf --port 8080`, then `"localLLMBaseURL": "http://127.0.0.1:8080/v1"`.

Instruction-tuned models from 3B to 14B (such as Qwen 2.5 Instruct or Llama 3.2) work well. Reasoning models work too; their `<think>` output is removed before pasting.

**Model server on another machine** (for example LM Studio at `http://10.0.0.82:1234/v1`):
- In LM Studio's server settings, turn on *Serve on Local Network* so other machines can reach it.
- Allow Whisperwell under System Settings › Privacy & Security › **Local Network**, then relaunch it. Until you do, macOS reports the connection as "offline". The menu shows "⚠ not reachable"; hover over it for the reason.
- Reserve the server's IP address in your router so it doesn't change.

**Custom Whisper models.** Fine-tune Whisper, convert it to Core ML with [whisperkittools](https://github.com/argmaxinc/whisperkittools), and either upload it to Hugging Face (`whisperModelRepo` + `whisperModel`) or point `whisperModelFolder` at it.

## Development signing

macOS ties privacy permissions to an app's code signature. An ad-hoc signature changes on every build, so macOS treats each rebuild as a new app and the permissions stop working. Create a local signing certificate once, and `build-app.sh` uses it automatically:

1. Open **Keychain Access › Certificate Assistant › Create a Certificate**.
2. Name: `Whisperwell Development`. Identity Type: Self Signed Root. Certificate Type: **Code Signing**.
3. Make sure it's trusted for code signing. Keychain Access usually does this; a certificate made on the command line isn't, and macOS then still resets permissions on every rebuild:
   ```bash
   security find-certificate -c "Whisperwell Development" -p > "$TMPDIR/whisperwell-dev.pem"
   security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$TMPDIR/whisperwell-dev.pem"
   ```
4. Rebuild with `./scripts/build-app.sh`, then grant the permissions one last time. The Whisperwell menu shows a "⚠ Needs …" line while any permission is missing.

A certificate made before the rename, named `FlowLite Development`, still works: `build-app.sh` falls back to it.

To use a different certificate, set `DEV_IDENTITY="Name"` when running the script. Without one, the script falls back to ad-hoc signing and prints a warning.

## Testing

- Unit tests: `swift test`.
- Full pipeline on an audio file, no microphone needed:
  ```bash
  say -o /tmp/test.aiff "um so lets meet at five, actually six pm tomorrow"
  ./build/Whisperwell.app/Contents/MacOS/Whisperwell --transcribe /tmp/test.aiff
  ```
  It prints the active models, the time taken, and the final text, using your real config.
  Add `--before "Text already in the field."` to simulate text above the cursor (checks that cleanup doesn't repeat it), `--race-preview` to run a live-preview pass at the same moment as the final transcription (checks they don't interfere), or `--simulate-live` to replay the file as if it were spoken and compare transcribing it in pieces with transcribing it all at once (text and time after release).
- Indicator design: `Whisperwell --render-indicator /tmp/indicator` writes a PNG of each state.
- Settings and setup windows: `Whisperwell --render-ui /tmp/ui` writes a PNG of each Settings tab and the setup window.
- Against a running local model server: `WHISPERWELL_LOCAL_LLM_URL=http://127.0.0.1:1234/v1 WHISPERWELL_LOCAL_LLM_MODEL="" swift test --filter LocalServerIntegrationTests`.

## Behavior

- Dictation starts once the hotkey has been held for 0.3 s: that's when the sound plays and the indicator appears. The mic starts the moment you press, so the first words aren't clipped. Shorter taps, and Option shortcuts typed within 0.3 s, are dropped silently.
- Pressing another key while holding the hotkey cancels (so Option+e still types é).
- It won't paste into password fields.
- The pasted text is marked so clipboard managers skip it, and your previous clipboard comes back 0.6 s later.
- While you hold the hotkey, the indicator shows the words heard so far. Whisperwell transcribes on-device about once a second, and at each pause it keeps the finished part, so letting go only transcribes the last few seconds. The log records the passes, how much was already transcribed at release, and the loudness levels used to find pauses.
- Cleanup never repeats text that's already in the field; if a model echoes it anyway, Whisperwell strips it before pasting.
- If Whisperwell can't paste (for example without Accessibility permission), the text is left on your clipboard so it isn't lost.
- The mic starts before anything else when you press the hotkey; wait for the soft "tink" before you talk. The log records how long the mic took to start.

Logs: `/usr/bin/log stream --predicate 'subsystem == "local.whisperwell"'`. Use the full path: in zsh, plain `log` is a built-in math command. Add `--info` to `/usr/bin/log show` to include success messages. Transcript text is never logged, only lengths.

## Layout

- `Sources/WhisperwellCore`: config, audio format, speech-to-text API client, Claude and local-model clients, cleanup prompt, pipeline. No UI, no third-party code. Unit tested.
- `Sources/Whisperwell`: menu bar app, hotkey event tap, microphone, Accessibility context, paste, on-device WhisperKit transcriber, floating indicator and sounds, `--transcribe` and `--render-indicator` dev modes.
- `Tests/WhisperwellCoreTests`: `swift test`.

## Publishing

Two ways to ship:

- **Direct download (recommended first):** `scripts/package-developer-id.sh` signs with Developer ID, notarizes, and builds `build/Whisperwell.dmg`. No sandbox, so every feature works as-is. This is how Wispr Flow ships.
- **Mac App Store:** `scripts/package-appstore.sh` builds a sandboxed, signed `.pkg` for upload. The sandbox may block the hotkey, reading text fields, or pasting into other apps, so test a sandboxed build before submitting.

Both need an Apple Developer Program membership. Supporting files:

| Path | What |
|---|---|
| `AppStore/metadata.md` | Listing text, keywords, review notes, privacy answers. Check limits with `scripts/check-metadata.py`. |
| `docs/privacy.md`, `docs/support.md` | Privacy policy and support page. Host them (for example on GitHub Pages) and put the URLs in App Store Connect. |
| `Branding/` | App icon and screenshots, generated from code. See `Branding/README.md`. |
| `Support/PrivacyInfo.xcprivacy` | Apple privacy manifest, bundled into the app. |
| `Support/AppStore.entitlements`, `Support/DeveloperID.entitlements` | Entitlements for each route. |

## Third-party software

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax, MIT License. Pinned to 1.1.1 in `Package.swift`.
- Whisper model weights by OpenAI, MIT License, downloaded at runtime from Hugging Face.

## Next steps

- Move to Swift 6 language mode (the package uses Swift 5 mode today).
- Intel Macs: the app compiles for x86_64, but WhisperKit 1.1.1 crashes there while decoding (tested under Rosetta). An Intel build would need on-device speech turned off, leaving only the cloud speech option.
