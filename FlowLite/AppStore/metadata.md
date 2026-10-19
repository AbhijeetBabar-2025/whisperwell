# App Store listing

Everything to paste into App Store Connect. Character limits are checked by
`scripts/check-metadata.py`. Run it after editing.

## App information

| Field | Value |
|---|---|
| Name (≤30) | FlowLite: Voice to Text |
| Subtitle (≤30) | Dictate anywhere on your Mac |
| Bundle ID | set in `scripts/package-appstore.sh` (`BUNDLE_ID`) |
| SKU | flowlite-mac-001 |
| Primary category | Productivity |
| Secondary category | Utilities |
| Age rating | 4+ (no objectionable content) |
| Copyright | © 2026 Abhijeet Babar |
| Price | Decide in App Store Connect (Free suggested for launch) |
| Support URL | https://YOUR-SITE/support (host `docs/support.md`) |
| Marketing URL | https://YOUR-SITE (optional) |
| Privacy Policy URL | https://YOUR-SITE/privacy (host `docs/privacy.md`) |

> **Name check before submitting.** "Flow" is part of Wispr Flow's brand, and "Lite" can read as a
> cut-down version of another product. App Review rejects names that copy or imply another app
> (Guidelines 4.1 and 5.2). Consider an original name; only this file, `Info.plist`
> (`CFBundleName`, `CFBundleDisplayName`) and the menu text need to change. The icon and
> screenshots don't show the name.

## Promotional text (≤170, editable any time without review)

Hold a key, speak, and polished text appears wherever you type. Speech recognition runs privately on your Mac. No account, no subscription.

## Keywords (≤100, comma-separated, no spaces after commas)

dictation,speech to text,voice typing,transcribe,whisper,dictate,voice,writing,productivity,offline

## Description (≤4000)

Talk instead of type, in any app.

Hold one key, say what you want to write, and let go. FlowLite turns your speech into clean, punctuated text and types it wherever your cursor is: email, chat, documents, notes, or code.

TYPES WHAT YOU MEANT
• Removes filler words like "um" and "uh"
• Applies your corrections: say "at 5, actually 6" and it types "at 6"
• Adds punctuation and capitalization for you
• Matches the tone of the app you're writing in

PRIVATE BY DEFAULT
• Speech recognition runs on your Mac with Whisper and Core ML. In on-device mode your audio is never uploaded.
• Works offline after a one-time model download
• No account, no subscription, no tracking, no analytics
• Never types into password fields, and restores your clipboard after every paste

BRING YOUR OWN AI
Text cleanup can use a model on your own computer or local network (any OpenAI-compatible server), or a cloud model with your own API key. You can also turn cleanup off and paste exactly what you said.

MADE FOR YOUR WORKFLOW
• Lives in the menu bar; every option is in one Settings window
• Choose your hotkey: Right Option, Right Command, or Fn
• Add names and jargon to your dictionary so they're spelled right every time
• Choose a smaller Whisper model for speed, or load your own fine-tuned model

REQUIREMENTS
• A Mac with Apple silicon, macOS 13 or later
• About 600 MB of free space for the speech model
• Microphone, Input Monitoring, and Accessibility permissions (the app explains each one)

## What's new in this version (≤4000)

First release.

## App Privacy ("nutrition label") answers

- **Does this app collect data?** No. Answer "Data Not Collected".
  - The developer runs no servers, analytics, or crash reporting.
  - Audio and text stay on the Mac in the default on-device mode.
  - If the user chooses a cloud provider (OpenAI, Groq, Anthropic), audio or text goes directly from their Mac to that provider under the user's own account and API key, and is never sent to the developer. Say this in the privacy policy.
- **Tracking:** No.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`: the app uses only Apple's standard HTTPS.

## App Review notes (paste into "Notes" for the reviewer)

FlowLite is a menu bar dictation app. It has no account and no login.

How to test:
1. Launch FlowLite. A microphone icon appears in the menu bar. On first launch it downloads the on-device Whisper speech model (about 600 MB) from Hugging Face; the menu shows "Speech: … ✓ ready" when it's done (1–3 minutes on a fast connection).
2. A setup window lists the permissions FlowLite needs (Microphone, Input Monitoring, Accessibility), with a button that opens the right page in System Settings for each. Allow them, then click "Restart FlowLite".
3. Open TextEdit, click in a document, hold the Right Option key, say a sentence, and release. The text appears at the cursor.

Why each permission is needed:
- Microphone: records your voice only while the hotkey is held.
- Input Monitoring: detects the hotkey (Right Option) system-wide. The app only listens for that key; it doesn't record other keystrokes.
- Accessibility: reads the text around the cursor in the focused field, so punctuation and capitalization fit, and inserts the result with a paste (⌘V).

Text cleanup only runs when the user sets up a cleanup model; until then the app pastes the raw transcript. No third-party account is needed to review the app.

## Screenshots

`Branding/Screenshots/*.png`, 2880×1800 (16:10, accepted for Mac). Upload in order 01 → 04.
Re-render after editing the HTML: see `Branding/README.md`.

## App icon

`Branding/Icon/AppIcon-1024.png` for App Store Connect; `Support/AppIcon.icns` is bundled into the app.
