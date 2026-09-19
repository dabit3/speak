# Speak

Speak is a native macOS 14+ app for dictation. It uses SwiftUI, AppKit, AVAudioEngine, and OpenAI GPT-Live-Transcribe. The Swift package has no external dependencies.

Use sans-serif fonts throughout the interface. Never introduce serif typography. Use the system default or rounded design, with monospaced digits only where needed for stable timers. Keep the dashboard free of the removed introductory tagline and status dot. Keep the Preferences Quit button in the fixed footer, outside the scrolling content. Use normal app termination so microphone, shortcuts, and clipboard cleanup still run.

Run these commands from the project root:

- Run `swift test` for the automated tests.
- Run `bash scripts/build.sh` to create `build/artifacts.noindex/Speak.app`.
- Run `open build/artifacts.noindex/Speak.app` to launch the app.
- Run `bash scripts/package-dmg.sh` to package the existing signed app as a DMG.

The packaging script does not rebuild or sign the app again. It creates `build/Speak-<version>-<architecture>.dmg` and a SHA-256 checksum file. It refuses to overwrite an existing installer. The DMG contains Speak and an Applications shortcut. The script verifies the image, mounts it read-only, validates the bundled signature, and compares the executable with the source. Temporary packaging files stay under the hidden `.build/` directory. App bundles stay under `build/artifacts.noindex/` so Spotlight does not index development copies. The DMG also disables Spotlight indexing.

Keep only the latest verified installer and its checksum when cleanup is approved. After packaging a new version, ask for confirmation to delete specific older Speak DMGs and checksums. Eject only the older Speak images approved for cleanup. Leave source files, the installed app, the current app bundle, credentials, and unrelated disk images untouched.

The build script signs the app locally by default. Set `CODE_SIGN_IDENTITY` to use an installed signing identity. Release distribution also requires notarization through Apple.

`Sources/SpeakCore/SpeakLogo.swift` defines the shared microphone-and-text-cursor mark. The interface, menu bar, icon generator, and SVG export use that path. The build script compiles `scripts/icon.swift` with the shared logo file and generates the app icon, `Resources/Speak.png`, and `Resources/SpeakMark.svg`. Keep the waveform bars only for the live audio meter, not for branding.

`Sources/SpeakCore` contains shortcut logic, API messages, and the transcription connection. `Sources/Speak` contains the native interface, microphone capture, Keychain access, and text insertion. Tests use a mock connection and do not call OpenAI.

To render native previews, create `build/previews` and run `.build/debug/Speak --render-previews "$PWD/build/previews"` after a debug build. The preview process does not request microphone or Accessibility access. AppKit renders the controls because SwiftUI ImageRenderer cannot render all native controls.

Use `gpt-live-transcribe`, not the conversational `gpt-live-1` model or the older Whisper models. Stream mono 24 kHz PCM16 audio over a WebSocket, a persistent network connection. Disable automatic turn detection and commit audio after the user releases the shortcut. Match final transcripts to the committed item before pasting.

Keep API keys in macOS Keychain. Never put keys in source files, logs, or command arguments. Do not save audio or transcript history to disk. Keep only the last original and corrected transcripts in memory for copy and paste recovery.

Smart correction defaults to enabled. `SmartCorrection` debounces partial text, caps speculative requests, and reuses results only for identical source text. It waits at most 350 ms for final correction before falling back to the original. `OpenAITranscriptCorrector` uses `gpt-4.1-nano-2025-04-14`, predicted output, and `store: false` through Chat Completions. Transcript text, vocabulary, language, and the active app name are sent to OpenAI. No surrounding text or clipboard context is collected. Use `CorrectionPolicy` to reject unsafe edits. Its checks are conservative heuristics, not a guarantee that an edit preserves meaning. Mock tests do not measure live model quality or response times.

`showLiveTranscript` defaults to true and is independent of `showPill` and `smartCorrectionEnabled`. Hidden live text must not stop audio capture, correction, or automatic paste. The compact pill must retain its recording controls and error messages.

The app needs microphone and Accessibility permissions for live dictation. Users enter their own API key in Preferences. A ChatGPT subscription does not include OpenAI API usage.

Paste automatically when dictation finishes. Capture the destination app when the user releases the shortcut. Do not require Accessibility element identity or metadata to send paste. Some text inputs do not expose that metadata. If the user changes apps while awaiting the final transcript, copy the text instead of pasting into another app. Block known password fields. Preserve the clipboard after automatic paste unless another process changes it. Never press Return or submit a form automatically.

Before claiming live accuracy or latency, test with a real microphone and an authorized API key. Automated tests do not establish live accuracy, actual latency, or compatibility with every target app. After rebuilding an app with a local signature, macOS can require new permission approval.

If Accessibility stays enabled in System Settings but Speak denies access, inspect macOS logs for a code requirement mismatch. A local rebuild can cause this mismatch. Get user approval before resetting permissions. Quit Speak, run `tccutil reset Accessibility local.speak.dictation`, and reopen the unchanged app. Ask the user to click Allow in Preferences and enable Speak again in System Settings. Do not rebuild between the reset and user approval. Do not reset other apps or other permission services.

Speak uses `local.speak.dictation` for its bundle identifier and Keychain service. A differently named predecessor does not share Speak preferences, permissions, or its Keychain entry. Ask the user to enter their API key and grant microphone and Accessibility permissions in Speak. Do not delete or read credentials from an older app during migration.
