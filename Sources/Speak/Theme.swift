import SwiftUI
import SpeakCore

extension Color {
    static let canvas = Color(red: 0.973, green: 0.969, blue: 0.958)
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.18)
    static let muted = Color(red: 0.45, green: 0.45, blue: 0.46)
    static let accent = Color(red: 0.66, green: 0.30, blue: 0.16)
    static let line = Color.black.opacity(0.075)
}

struct BrandMark: View {
    var size: CGFloat = 26
    var body: some View {
        DictationMark()
            .fill()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(SpeakLogo.path(in: bounds.insetBy(dx: 1, dy: 1)))
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Speak dictation"
        return image
    }
}

private struct DictationMark: Shape {
    func path(in rect: CGRect) -> Path { Path(SpeakLogo.path(in: rect)) }
}

struct Keycap: View {
    let label: String
    var large = false
    var body: some View {
        Text(label)
            .font(.system(size: large ? 23 : 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.ink.opacity(0.8))
            .padding(.horizontal, large ? 18 : 7)
            .frame(minWidth: large ? 66 : 25, minHeight: large ? 61 : 23)
            .background(
                RoundedRectangle(cornerRadius: large ? 15 : 5).fill(.white)
                    .shadow(color: .black.opacity(large ? 0.08 : 0.03), radius: large ? 0 : 1, y: large ? 4 : 1)
            )
            .overlay(RoundedRectangle(cornerRadius: large ? 15 : 5).strokeBorder(Color.black.opacity(0.1)))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Color.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SubtleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(configuration.isPressed ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct Spinner: View {
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            Circle()
                .trim(from: 0.1, to: 0.78)
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Finishing")
    }
}

struct AudioBars: View {
    let level: Float
    var active = true
    var color: Color = .white
    var axis: Axis = .horizontal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let horizontal = axis == .horizontal
        TimelineView(.animation(minimumInterval: 0.065, paused: !active || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            (horizontal ? AnyLayout(HStackLayout(spacing: 3)) : AnyLayout(VStackLayout(spacing: 3))) {
                ForEach(0..<(horizontal ? 15 : 11), id: \.self) { index in
                    let wave = (sin(time * 9 + Double(index) * 0.8) + 1) / 2
                    let amplitude = active ? Double(level) : 0
                    let length = 3 + amplitude * (7 + wave * 19)
                    Capsule()
                        .fill(color.opacity(active ? 0.95 : 0.4))
                        .frame(width: horizontal ? 3 : length, height: horizontal ? length : 3)
                }
            }
            .frame(width: horizontal ? 87 : 30, height: horizontal ? 30 : 63)
        }
        .accessibilityLabel(active ? "Microphone audio level" : "Microphone off")
    }
}
