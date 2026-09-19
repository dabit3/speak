<p align="center">
  <img src="Resources/Speak.png" alt="Speak icon with a microphone and text cursor on warm apricot" width="112" height="112">
</p>

<h1 align="center">Speak</h1>

<p align="center">Your voice, right where you type.</p>

<p align="center">
  <a href="https://devin.ai">
    <img src="Resources/BuiltByDevin.png" alt="Built by Devin" width="164" height="38">
  </a>
</p>

Speak is a small macOS menu bar app that turns speech into text with OpenAI GPT-Live-Transcribe. Hold <kbd>fn</kbd> to dictate. Release it to paste your words into the active app.

## For users

You need an Apple Silicon Mac running macOS 14 or later, internet access, and an OpenAI API key. You do not need Xcode.

1. Open the Speak `.dmg` installer.
2. Drag Speak into Applications. Open Speak.
3. In Preferences, add your OpenAI API key.
4. Allow Microphone and Accessibility access.

OpenAI API usage is billed separately from ChatGPT subscriptions. The installer is locally signed, not notarized by Apple.

### Shortcuts

| Shortcut | Action |
| :--- | :--- |
| Hold <kbd>fn</kbd> | Record your voice. Release to paste. |
| <kbd>fn</kbd> + <kbd>space</kbd> | Start or stop hands-free dictation. |
| <kbd>esc</kbd> | Cancel without pasting. |

You can choose Control + Option or add vocabulary hints in Preferences. Turn off “Show live text above pill” to hide the transcript while recording.

Smart correction is on by default and uses GPT-4.1 nano to fix likely misheard words. It allows up to 350 ms of extra wait, then falls back to the original text. Choose “Copy original dictation” from the menu bar to recover the unedited transcript. Turn off “Smart correction” in Preferences for unedited output.

### Privacy

Speak stores your API key in macOS Keychain. Audio streams directly to OpenAI during dictation. Smart correction also sends transcript text, vocabulary, and the active app name to OpenAI, with extra text API charges. Speak keeps only the last original and corrected transcripts in memory, with no recordings or history saved to disk.

OpenAI’s API data policies still apply.

## For developers

Building from source requires Xcode with Swift 6 or later.

```sh
bash scripts/build.sh
open build/artifacts.noindex/Speak.app
```

Run tests with `swift test`. After building the app, create an installer with `bash scripts/package-dmg.sh`. The script writes the DMG to `build/`.
