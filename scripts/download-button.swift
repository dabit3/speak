import AppKit

@main
struct DownloadButtonGenerator {
    static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        let scale: CGFloat = 3
        let height: CGFloat = 38
        let tile: CGFloat = 22
        let leading: CGFloat = 10, gap: CGFloat = 9, trailing: CGFloat = 16
        let ink = CGColor(red: 0.12, green: 0.15, blue: 0.16, alpha: 1)
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let title = NSMutableAttributedString(string: "Download ", attributes: [.font: font, .foregroundColor: NSColor(cgColor: ink)!])
        title.append(NSAttributedString(string: "for macOS", attributes: [.font: font, .foregroundColor: NSColor(white: 0.36, alpha: 1)]))
        let line = CTLineCreateWithAttributedString(title)
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let width = ceil(leading + tile + gap + textWidth + trailing)

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let pillRect = CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1)
        let pill = CGPath(roundedRect: pillRect, cornerWidth: pillRect.height / 2, cornerHeight: pillRect.height / 2, transform: nil)
        context.addPath(pill)
        context.setFillColor(.white)
        context.fillPath()
        context.addPath(pill)
        context.setStrokeColor(CGColor(gray: 0.84, alpha: 1))
        context.setLineWidth(1)
        context.strokePath()

        let tileRect = CGRect(x: leading, y: (height - tile) / 2, width: tile, height: tile)
        context.saveGState()
        context.addPath(CGPath(roundedRect: tileRect, cornerWidth: tile * 0.24, cornerHeight: tile * 0.24, transform: nil))
        context.clip()
        let colors = [
            CGColor(red: 1.00, green: 0.85, blue: 0.65, alpha: 1),
            CGColor(red: 0.96, green: 0.66, blue: 0.40, alpha: 1)
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: tileRect.minX, y: tileRect.maxY), end: CGPoint(x: tileRect.minX, y: tileRect.minY), options: [])
        context.restoreGState()

        context.saveGState()
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        let flippedTile = CGRect(x: tileRect.minX, y: height - tileRect.maxY, width: tile, height: tile)
        context.setFillColor(ink)
        context.addPath(SpeakLogo.path(in: flippedTile.insetBy(dx: tile * 0.1, dy: tile * 0.1)))
        context.fillPath()
        context.restoreGState()

        context.textPosition = CGPoint(x: leading + tile + gap, y: (height - font.capHeight) / 2)
        CTLineDraw(line, context)

        try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
        print("\(Int(width))x\(Int(height)) points at \(Int(scale))x")
    }
}
