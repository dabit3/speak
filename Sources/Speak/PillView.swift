import AppKit
import Combine
import SwiftUI

struct PillView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if model.phase == .failure {
                Text(model.message)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center).lineLimit(4)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 370)
            } else if model.showsLiveTranscript {
                Text(model.partial)
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center).lineLimit(3)
                    .padding(.horizontal, 17).padding(.vertical, 11)
                    .background(Color(white: 0.13).opacity(0.96), in: RoundedRectangle(cornerRadius: 13))
                    .frame(maxWidth: 370)
                    .accessibilityLabel("Live transcript: \(model.partial)")
            }
            HStack(spacing: 13) {
                if model.phase.isBusy {
                    Button { model.cancel() } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                            .frame(width: 23, height: 28).contentShape(Rectangle())
                    }.help("Cancel dictation · Esc")
                    if model.phase == .finishing {
                        ProgressView().controlSize(.small).tint(.white).scaleEffect(0.7)
                        Text("Finishing").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                    } else {
                        Circle().fill(Color(red: 1, green: 0.73, blue: 0.48)).frame(width: 5, height: 5)
                        AudioBars(level: model.level)
                        Text(model.timeLabel).font(.system(size: 10, design: .default)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                    }
                    Button { model.finish() } label: {
                        Image(systemName: "stop.fill").font(.system(size: 10)).foregroundStyle(.white)
                            .frame(width: 25, height: 25).background(.white.opacity(0.13), in: Circle())
                    }.disabled(model.phase == .finishing).help("Finish dictation")
                } else if model.phase == .success {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 0.72, green: 0.82, blue: 0.65))
                    Text(model.message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.9))
                } else if model.phase == .failure {
                    Button { model.dismiss() } label: {
                        Label("Dismiss", systemImage: "xmark").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    Button { model.toggle() } label: {
                        HStack(spacing: 9) {
                            BrandMark(size: 16).foregroundStyle(.white.opacity(0.85))
                            Text(model.preferences.shortcutLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 7).frame(height: 20).contentShape(Rectangle())
                    }.help("Click to dictate, or hold \(model.preferences.shortcutLabel)")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, model.phase == .idle ? 10 : 13)
            .padding(.vertical, model.phase == .idle ? 7 : 9)
            .background(Color(red: 0.11, green: 0.115, blue: 0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.phase)
        .preferredColorScheme(.dark)
    }
}

final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PillController {
    private let panel: DictationPanel
    private let model: AppModel
    private var subscriptions = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        panel = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 190), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        model.$phase.sink { [weak self] phase in
            Task { @MainActor in self?.update(phase: phase) }
        }.store(in: &subscriptions)
        model.preferences.$showPill.sink { [weak self] _ in
            Task { @MainActor in self?.update(phase: model.phase) }
        }.store(in: &subscriptions)
        model.preferences.$showLiveTranscript.sink { [weak self] _ in
            Task { @MainActor in self?.update(phase: model.phase) }
        }.store(in: &subscriptions)
        model.$partial.map { !$0.isEmpty }.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.update(phase: model.phase) }
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update(phase: model.phase) }
        }
        update(phase: model.phase)
    }

    private func update(phase: AppModel.Phase) {
        guard model.preferences.showPill || phase != .idle else { panel.orderOut(nil); return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let height = model.pillHeight
        let width: CGFloat = phase == .idle ? 150 : 430
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 5, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
}
