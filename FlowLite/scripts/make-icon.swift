// Draws the app icon and builds Support/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the FlowLite folder)
//
// Design: a voice waveform that resolves into a text cursor, i.e. speech becoming text,
// on the standard macOS rounded-square body (824 pt inside a 1024 pt canvas).
import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let shape = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft drop shadow under the body, per macOS icon guidelines.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x1B1F3B))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep indigo to violet.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [color(0x2A2F7A), color(0x5B3FD1), color(0x8E5BF5)] as CFArray,
                                locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.minY),
                           end: CGPoint(x: body.maxX, y: body.maxY), options: [])
    // Glow behind the waveform for depth.
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 430, options: [])
    // Subtle top highlight.
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Waveform: rounded bars, tallest in the middle, fading in from the left.
    let centerY: CGFloat = 512
    let barWidth: CGFloat = 44
    let gap: CGFloat = 30
    let heights: [CGFloat] = [110, 220, 360, 270, 160]
    // Bars + caret span 452 pt; start so the whole group is centered on 512.
    var x: CGFloat = 286
    for (i, h) in heights.enumerated() {
        let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.55 + 0.1 * CGFloat(i)))
        ctx.fillPath()
        x += barWidth + gap
    }

    // Text cursor (I-beam) in mint: where the words land.
    let caretX = x + 24
    let caretTop: CGFloat = centerY + 205
    let caretBottom: CGFloat = centerY - 205
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0x5FF2C8, 0.8))
    ctx.setStrokeColor(color(0x6BF5CF))
    ctx.setLineCap(.round)
    ctx.setLineWidth(40)
    ctx.move(to: CGPoint(x: caretX, y: caretBottom + 20))
    ctx.addLine(to: CGPoint(x: caretX, y: caretTop - 20))
    ctx.strokePath()
    ctx.setLineWidth(30)
    for y in [caretTop, caretBottom] {
        ctx.move(to: CGPoint(x: caretX - 58, y: y))
        ctx.addLine(to: CGPoint(x: caretX + 58, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()
}

func renderPNG(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDir = root.appendingPathComponent("Branding/Icon")
let iconset = iconDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Sizes macOS expects in an .iconset.
for base in [16, 32, 128, 256, 512] {
    try renderPNG(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try renderPNG(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try renderPNG(size: 1024).write(to: iconDir.appendingPathComponent("AppIcon-1024.png"))
print("Wrote \(iconset.path) and AppIcon-1024.png")
