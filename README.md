<p align="center">
  <img src="Resources/Speak.png" alt="Speak icon with a microphone and text cursor on warm apricot" width="112" height="112">
</p>

<h1 align="center">Speak</h1>

<p align="center">Your voice, right where you type.</p>

Speak is a small macOS menu bar app that turns speech into text with OpenAI GPT-Live-Transcribe. Hold <kbd>fn</kbd> to dictate. Release it to paste your words into the active app.

## Get started

You need macOS 14 or later, Xcode with Swift 6 or later, and an OpenAI API key.

Build and open the app:

```sh
bash scripts/build.sh
open build/artifacts.noindex/Speak.app
```

In Preferences:

1. Add your OpenAI API key.
2. Allow microphone access.
3. Allow Accessibility access for shortcuts and automatic paste.

OpenAI API usage is billed separately from ChatGPT subscriptions.

## Shortcuts

| Shortcut | Action |
| :--- | :--- |
| Hold <kbd>fn</kbd> | Record your voice. Release to paste. |
| <kbd>fn</kbd> + <kbd>space</kbd> | Start or stop hands-free dictation. |
| <kbd>esc</kbd> | Cancel without pasting. |

You can also choose Control + Option in Preferences. Add names and technical terms to your vocabulary for recognition hints.

## Privacy

Speak stores your API key in macOS Keychain. Audio streams directly to OpenAI during dictation. Speak keeps the last transcript in memory but saves no audio or transcript history to disk.

OpenAI’s API data policies still apply.

## Build an installer

After building the app, create a DMG:

```sh
bash scripts/package-dmg.sh
```

Open the DMG in `build/`. Drag Speak into Applications. The installer is locally signed, not notarized by Apple.

Run the tests with `swift test`.
