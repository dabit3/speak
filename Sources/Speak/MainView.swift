import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 25).foregroundStyle(Color.ink)
                Text("speak").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-1)
                Spacer()
                HStack(spacing: 3) {
                    tab("Dictation", index: 0)
                    tab("Preferences", index: 1)
                }
                .padding(4)
                .background(.black.opacity(0.035), in: Capsule())
            }
            .padding(.horizontal, 36)
            .padding(.top, 39)
            .padding(.bottom, 22)
            if model.selectedTab == 0 {
                DashboardView(model: model)
            } else {
                PreferencesView(model: model, preferences: model.preferences)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 11))
                Text("No audio saved. No transcript history on disk.")
                Spacer()
                if model.selectedTab == 1 {
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(SubtleButton())
                        .help("Quit Speak")
                        .accessibilityIdentifier("quit-speak")
                } else {
                    Text("MADE FOR YOUR TRAIN OF THOUGHT").font(.system(size: 8, weight: .medium)).tracking(1.2)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.muted)
            .padding(.horizontal, 36)
            .padding(.vertical, 19)
            .background(Color.canvas)
            .overlay(alignment: .top) {
                if model.selectedTab == 1 {
                    Rectangle()
                        .fill(Color.line)
                        .frame(height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: 760, height: 640)
        .foregroundStyle(Color.ink)
        .background(Color.canvas)
        .tint(Color.accent)
        .preferredColorScheme(.light)
    }

    private func tab(_ title: String, index: Int) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { model.selectedTab = index } } label: {
            Text(title)
                .font(.system(size: 12, weight: model.selectedTab == index ? .medium : .regular))
                .foregroundStyle(model.selectedTab == index ? Color.ink : Color.muted)
                .padding(.horizontal, 15)
                .padding(.vertical, 7)
                .background(model.selectedTab == index ? .white : .clear, in: Capsule())
                .shadow(color: .black.opacity(model.selectedTab == index ? 0.04 : 0), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var practiceText = ""
    @FocusState private var practiceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Think it. Say it. Done.")
                .font(.system(size: 40, weight: .semibold, design: .default))
                .tracking(-1.4)
                .padding(.top, 28)
            Text("Your words, wherever you’re writing.")
                .font(.system(size: 14))
                .foregroundStyle(Color.muted)
                .padding(.top, 9)
            interactionCard.padding(.top, 28)
            if model.phase == .failure {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle")
                    Text(model.message).frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.6, green: 0.28, blue: 0.2))
                .padding(14)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 14)
            } else if !model.ready {
                HStack(spacing: 12) {
                    Image(systemName: "sparkle").font(.system(size: 18)).foregroundStyle(Color.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Make room for your voice.").font(.system(size: 13, weight: .medium))
                        Text("Add your API key and allow microphone & accessibility access.")
                            .font(.system(size: 11)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Button("Set up Speak") { model.selectedTab = 1 }.buttonStyle(PrimaryButton())
                }
                .padding(17)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.line))
                .padding(.top, 19)
            } else {
                transcriptCard.padding(.top, 19)
            }
        }
        .padding(.horizontal, 48)
    }

    private var interactionCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 28) {
                ZStack {
                    Circle().fill(Color(red: 0.98, green: 0.88, blue: 0.76)).frame(width: 108, height: 108)
                    Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1).frame(width: 94, height: 94)
                    if model.phase.isBusy {
                        AudioBars(level: model.level, active: model.phase.isRecording, color: .accent)
                    } else {
                        Keycap(label: model.preferences.shortcutLabel, large: true).rotationEffect(.degrees(-5))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.phase.isBusy ? model.phaseLabel : "Hold. Speak. Release.")
                        .font(.system(size: 21, weight: .medium)).tracking(-0.6)
                    Text(model.phase.isBusy ? "\(model.timeLabel)  ·  \(model.handsFree ? "Hands-free" : "Release to finish")" : "Hold \(model.preferences.shortcutLabel) in any text field.\nLet go, and your words appear.")
                        .font(.system(size: 13)).lineSpacing(5).foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 29)
            .padding(.vertical, 25)
            Rectangle().fill(Color.line).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "hands.sparkles").font(.system(size: 12)).foregroundStyle(Color.muted)
                Text("Hands-free").font(.system(size: 11, weight: .medium))
                Keycap(label: model.preferences.shortcutLabel)
                Text("+").foregroundStyle(Color.muted)
                Keycap(label: "space")
                Spacer()
                Keycap(label: "esc")
                Text("to cancel").font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
        }
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.lastTranscript.isEmpty ? "A SPACE TO TRY IT" : "YOUR LAST DICTATION")
                    .font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(Color.muted)
                Spacer()
                if let latency = model.lastLatency {
                    Text("\(latency) ms to final text").font(.system(size: 10)).foregroundStyle(Color.muted)
                }
                if !model.lastTranscript.isEmpty {
                    Button { model.copyLast() } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).help("Copy last dictation")
                }
            }
            TextField("Click here, hold \(model.preferences.shortcutLabel), and say something…", text: $practiceText, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(2...3)
                .focused($practiceFocused)
                .onChange(of: model.lastTranscript) { _, text in
                    if !practiceFocused { practiceText = text }
                }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
    }
}
