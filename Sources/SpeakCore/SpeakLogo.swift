import CoreGraphics

public enum SpeakLogo {
    public static func path(in rect: CGRect) -> CGPath {
        guard rect.width > 0, rect.height > 0 else { return CGMutablePath() }
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 18, y: 8, width: 28, height: 48), cornerWidth: 14, cornerHeight: 14)

        let microphone = CGMutablePath()
        microphone.move(to: CGPoint(x: 8, y: 44))
        microphone.addLine(to: CGPoint(x: 8, y: 52))
        microphone.addCurve(to: CGPoint(x: 32, y: 76), control1: CGPoint(x: 8, y: 65), control2: CGPoint(x: 19, y: 76))
        microphone.addCurve(to: CGPoint(x: 56, y: 52), control1: CGPoint(x: 45, y: 76), control2: CGPoint(x: 56, y: 65))
        microphone.addLine(to: CGPoint(x: 56, y: 44))
        microphone.move(to: CGPoint(x: 32, y: 76))
        microphone.addLine(to: CGPoint(x: 32, y: 89))
        microphone.move(to: CGPoint(x: 20, y: 89))
        microphone.addLine(to: CGPoint(x: 44, y: 89))
        path.addPath(microphone.copy(strokingWithWidth: 7, lineCap: .round, lineJoin: .round, miterLimit: 2))

        let cursor = CGMutablePath()
        cursor.move(to: CGPoint(x: 70, y: 18))
        cursor.addLine(to: CGPoint(x: 92, y: 18))
        cursor.move(to: CGPoint(x: 81, y: 18))
        cursor.addLine(to: CGPoint(x: 81, y: 89))
        cursor.move(to: CGPoint(x: 70, y: 89))
        cursor.addLine(to: CGPoint(x: 92, y: 89))
        path.addPath(cursor.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 2))
        let side = min(rect.width, rect.height)
        var transform = CGAffineTransform(
            a: side / 100, b: 0, c: 0, d: side / 100,
            tx: rect.midX - side / 2, ty: rect.midY - side / 2
        )
        return path.copy(using: &transform)!
    }
}
