import AppKit
import Combine
import SwiftUI

struct PillView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let position = model.preferences.pillPosition
        Group {
            if position == .bottom {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    bubble(at: position)
                    controls(vertical: false)
                }
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                HStack(spacing: 12) {
                    if position == .right {
                        Spacer(minLength: 0)
                        bubble(at: position)
                    }
                    controls(vertical: true)
                    if position == .left {
                        bubble(at: position)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.phase)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func bubble(at position: PillPosition) -> some View {
        let vertical = position != .bottom
        if model.phase == .failure {
            note(model.message, size: 12, lines: vertical ? 6 : 4, at: position)
        } else if model.showsLiveTranscript {
            note(model.partial, size: 13, lines: vertical ? 7 : 3, at: position)
                .accessibilityLabel("Live transcript: \(model.partial)")
        } else if vertical && model.phase == .success {
            note(model.message, size: 12, lines: 2, at: position)
        }
    }

    private func note(_ text: String, size: CGFloat, lines: Int, at position: PillPosition) -> some View {
        let vertical = position != .bottom
        return Text(text)
            .font(.system(size: size)).foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(vertical ? .leading : .center).lineLimit(lines)
            .padding(.horizontal, 17).padding(.vertical, 11)
            .background(Color(white: 0.13).opacity(0.96), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(vertical ? 0.08 : 0)))
            .frame(maxWidth: vertical ? 300 : 370, alignment: position == .left ? .leading : position == .right ? .trailing : .center)
    }

    @ViewBuilder private func meter(vertical: Bool) -> some View {
        Circle().fill(Color(red: 1, green: 0.73, blue: 0.48)).frame(width: 5, height: 5)
        AudioBars(level: model.level, axis: vertical ? .vertical : .horizontal)
        Text(model.timeLabel).font(.system(size: 10, design: .default)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
    }

    private func controls(vertical: Bool) -> some View {
        let idle = model.phase == .idle
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 13))
        return stack {
            if model.phase.isBusy {
                Button { model.cancel() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: vertical ? 28 : 23, height: vertical ? 22 : 28).contentShape(Rectangle())
                }.help("Cancel dictation · Esc")
                if model.phase == .finishing {
                    Spinner(size: vertical ? 14 : 12).frame(height: vertical ? 104 : nil)
                    if !vertical { Text("Finishing").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)) }
                } else if vertical {
                    VStack(spacing: 10) { meter(vertical: true) }.frame(height: 104)
                } else {
                    meter(vertical: false)
                }
                Button { model.finish() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 10)).foregroundStyle(.white)
                        .frame(width: 25, height: 25).background(.white.opacity(0.13), in: Circle())
                }.disabled(model.phase == .finishing).help("Finish dictation")
            } else if model.phase == .success {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 0.72, green: 0.82, blue: 0.65))
                    .frame(height: vertical ? 22 : nil)
                if !vertical { Text(model.message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.9)) }
            } else if model.phase == .failure {
                Button { model.dismiss() } label: {
                    if vertical {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 28, height: 22).contentShape(Rectangle())
                    } else {
                        Label("Dismiss", systemImage: "xmark").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                    }
                }.help("Dismiss").accessibilityLabel("Dismiss")
            } else {
                Button { model.toggle() } label: {
                    (vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 9))) {
                        BrandMark(size: 16).foregroundStyle(.white.opacity(0.85))
                        Text(model.preferences.shortcutLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(vertical ? .vertical : .horizontal, 7).frame(width: vertical ? 30 : nil, height: vertical ? nil : 20).contentShape(Rectangle())
                }.help("Click to dictate, or hold \(model.preferences.shortcutLabel)")
            }
        }
        .frame(minWidth: vertical && !idle ? 30 : nil)
        .buttonStyle(.plain)
        .padding(.horizontal, vertical ? (idle ? 5 : 8) : (idle ? 10 : 13))
        .padding(.vertical, vertical ? (idle ? 8 : 12) : (idle ? 7 : 9))
        .background(Color(red: 0.11, green: 0.115, blue: 0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
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
        model.preferences.$pillPosition.sink { [weak self] _ in
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
        let position = model.preferences.pillPosition
        let size = Self.size(for: position, idle: phase == .idle, height: model.pillHeight)
        panel.setFrame(Self.frame(for: position, in: screen.visibleFrame, size: size), display: true)
        panel.orderFrontRegardless()
    }

    static func size(for position: PillPosition, idle: Bool, height: CGFloat) -> NSSize {
        switch position {
        case .bottom: return NSSize(width: idle ? 150 : 430, height: height)
        case .left, .right: return idle ? NSSize(width: 90, height: 120) : NSSize(width: 430, height: 260)
        }
    }

    static func frame(for position: PillPosition, in visible: NSRect, size: NSSize) -> NSRect {
        let middle = visible.midY - size.height / 2
        switch position {
        case .bottom: return NSRect(origin: NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 5), size: size)
        case .left: return NSRect(origin: NSPoint(x: visible.minX + 5, y: middle), size: size)
        case .right: return NSRect(origin: NSPoint(x: visible.maxX - size.width - 5, y: middle), size: size)
        }
    }
}
