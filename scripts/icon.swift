import AppKit

@main
struct IconGenerator {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let destination = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
                try png(size: size * scale).write(to: destination)
            }
        }
        if CommandLine.arguments.count > 2 {
            let resources = URL(fileURLWithPath: CommandLine.arguments[2])
            try png(size: 512).write(to: resources.appendingPathComponent("Speak.png"))
            try svg().write(to: resources.appendingPathComponent("SpeakMark.svg"), atomically: true, encoding: .utf8)
        }
    }

    private static func png(size: Int) throws -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        let side = CGFloat(size)
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        let tile = CGRect(x: side * 0.05, y: side * 0.05, width: side * 0.9, height: side * 0.9)
        let outline = CGPath(roundedRect: tile, cornerWidth: side * 0.215, cornerHeight: side * 0.215, transform: nil)
        context.saveGState()
        context.addPath(outline)
        context.clip()
        let colors = [
            CGColor(red: 1.00, green: 0.85, blue: 0.65, alpha: 1),
            CGColor(red: 0.96, green: 0.66, blue: 0.40, alpha: 1)
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: .zero, options: [])
        context.restoreGState()
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(red: 0.12, green: 0.15, blue: 0.16, alpha: 1))
        context.addPath(SpeakLogo.path(in: CGRect(x: side * 0.14, y: side * 0.14, width: side * 0.72, height: side * 0.72)))
        context.fillPath()
        return bitmap.representation(using: .png, properties: [:])!
    }

    private static func svg() -> String {
        var commands: [String] = []
        SpeakLogo.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).applyWithBlock { element in
            let value = element.pointee
            func point(_ index: Int) -> String { "\(value.points[index].x) \(value.points[index].y)" }
            switch value.type {
            case .moveToPoint: commands.append("M\(point(0))")
            case .addLineToPoint: commands.append("L\(point(0))")
            case .addQuadCurveToPoint: commands.append("Q\(point(0)) \(point(1))")
            case .addCurveToPoint: commands.append("C\(point(0)) \(point(1)) \(point(2))")
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" role=\"img\" aria-label=\"Speak microphone and text cursor\"><path fill=\"currentColor\" d=\"\(commands.joined(separator: " "))\"/></svg>\n"
    }
}
