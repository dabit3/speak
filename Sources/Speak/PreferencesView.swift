import SwiftUI
import SpeakCore

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var apiKey = ""
    @State private var keyMessage = ""
    @State private var keyError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Just the essentials.").font(.system(size: 29, weight: .semibold, design: .default)).tracking(-0.8)
                    Text("A few small things. Then get back to your thoughts.").font(.system(size: 12)).foregroundStyle(Color.muted)
                }
                section("CONNECTION") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("OpenAI API key").font(.system(size: 13, weight: .medium))
                            Text("Stored in your Mac’s Keychain. Never in project files.").font(.system(size: 11)).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        if preferences.hasAPIKey {
                            Label("Saved", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Color.accent)
                        }
                    }
                    HStack(spacing: 9) {
                        SecureField(preferences.hasAPIKey ? "Enter a new key to replace it" : "Paste your API key", text: $apiKey)
                            .textFieldStyle(.plain).font(.system(size: 12, design: .default))
                            .padding(11).background(Color.canvas, in: RoundedRectangle(cornerRadius: 8))
                            .onSubmit(saveKey)
                        Button("Save key", action: saveKey).buttonStyle(PrimaryButton()).disabled(apiKey.isEmpty)
                    }
                    if !keyMessage.isEmpty {
                        Text(keyMessage).font(.system(size: 11)).foregroundStyle(keyError ? Color.red : Color.accent)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.accent).frame(width: 4, height: 4)
                        Text("GPT-Live-Transcribe").fontWeight(.medium)
                        Text("·  Direct to OpenAI · Separate API billing")
                    }
                    .font(.system(size: 10)).foregroundStyle(Color.muted)
                }
                section("PERMISSIONS") {
                    permissionRow("Microphone", detail: "Only listens while you’re dictating.", symbol: "mic", granted: model.microphoneGranted, action: model.requestMicrophone)
                    Divider().overlay(Color.line)
                    permissionRow("Accessibility", detail: "For your global shortcut and pasting into other apps.", symbol: "keyboard", granted: model.accessibilityGranted, action: model.requestAccessibility)
                    if model.accessibilityGranted && !model.shortcutAvailable {
                        Text("Keyboard monitoring is unavailable. Restart Speak after granting access; if needed, allow Input Monitoring in System Settings.")
                            .font(.system(size: 11)).foregroundStyle(Color.red)
                        Button("Open Input Monitoring") { model.openPrivacy("ListenEvent") }.buttonStyle(SubtleButton())
                    }
                }
                section("DICTATION") {
                    toggleRow("Smart correction", detail: "Fix likely misheard words from the context of your dictation.", isOn: $preferences.smartCorrectionEnabled)
                    Text("Uses GPT-4.1 nano and adds text API charges. Waits up to 350 ms for correction, then pastes the original. Copy the original from the menu bar at any time.")
                        .font(.system(size: 10)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    settingRow("Shortcut", detail: "Double-tap for hands-free, or add Space.") {
                        Picker("Shortcut", selection: $preferences.shortcut) {
                            Text("fn").tag("fn")
                            Text("⌃ Control + ⌥ Option").tag("controlOption")
                        }.labelsHidden().frame(width: 190)
                    }
                    Text("If Fn opens the emoji picker, set the Fn / Globe key action to “Do Nothing” in macOS Keyboard settings. Control + Option works on external keyboards.")
                        .font(.system(size: 10)).foregroundStyle(Color.muted)
                    Divider()
                    settingRow("Language", detail: "A language hint can improve recognition.") {
                        Picker("Language", selection: $preferences.language) {
                            Text("Auto-detect").tag("")
                            Text("English").tag("en")
                            Text("Spanish").tag("es")
                            Text("French").tag("fr")
                            Text("German").tag("de")
                            Text("Portuguese").tag("pt")
                            Text("Italian").tag("it")
                            Text("Japanese").tag("ja")
                            Text("Korean").tag("ko")
                            Text("Chinese").tag("zh")
                            Text("Hindi").tag("hi")
                            Text("Arabic").tag("ar")
                        }.labelsHidden().frame(width: 190)
                    }
                    Divider()
                    settingRow("Transcription speed", detail: "Faster partial text, or more context for accuracy.") {
                        Picker("Live text delay", selection: $preferences.delay) {
                            ForEach(TranscriptionDelay.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 190)
                    }
                }
                section("APPEARANCE") {
                    toggleRow("Show live text above pill", detail: "Turn off to keep only the recording controls and audio level.", isOn: $preferences.showLiveTranscript)
                    Divider()
                    toggleRow("Show the floating pill", detail: "Keep the pill visible when you are not recording.", isOn: $preferences.showPill)
                }
                section("YOUR VOCABULARY") {
                    Text("Names, products, and words you use. Separated by commas.").font(.system(size: 11)).foregroundStyle(Color.muted)
                    TextField("e.g. Nader, PostgreSQL, Speak", text: $preferences.vocabulary, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(2...3)
                        .padding(11).background(Color.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .onChange(of: preferences.vocabulary) { _, value in
                            if value.count > 4000 { preferences.vocabulary = String(value.prefix(4000)) }
                        }
                }
                Text("Audio goes directly to OpenAI. Smart correction also sends transcript text, vocabulary, and the active app name to OpenAI. Only the last original and corrected transcripts stay in memory. No recordings or transcript history are saved to disk. OpenAI’s API data policies and separate API billing apply.")
                    .font(.system(size: 10)).lineSpacing(4).foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 44)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.visible, axes: .vertical)
        .disabled(model.phase.isBusy)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(Color.muted)
            VStack(alignment: .leading, spacing: 13, content: content)
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.line))
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(.switch).controlSize(.small)
    }

    private func permissionRow(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 24).foregroundStyle(Color.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Color.muted)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accent).font(.system(size: 16)).accessibilityLabel("Allowed")
            } else {
                Button("Allow", action: action).buttonStyle(SubtleButton())
            }
        }
    }

    private func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Color.muted)
            }
            Spacer()
            content().font(.system(size: 12))
        }
    }

    private func saveKey() {
        do {
            try preferences.saveKey(apiKey)
            apiKey = ""
            keyError = false
            keyMessage = "Saved securely. Your next dictation will use this key."
        } catch {
            keyError = true
            keyMessage = error.localizedDescription
        }
    }
}
