import AppKit

// Renders the app icons from the flat glyph artwork:
// - macOS: white rounded plate on Apple's 1024-grid template (824pt plate,
//   ~185pt corners), soft drop shadow under the plate, glyph at 70%.
// - iOS: full-bleed white square, glyph at 74%, soft shadow under the glyph.

let arguments = CommandLine.arguments
guard arguments.count == 3, let source = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("usage: render-icons <glyph.png> <outdir>")
}
let outDir = URL(fileURLWithPath: arguments[2])

func canvas(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    return rep
}

func draw(on rep: NSBitmapImageRep, _ body: (CGContext) -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    body(context.cgContext)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

func drawGlyph(sized glyphSize: CGFloat, in total: CGFloat, context: CGContext) {
    let origin = (total - glyphSize) / 2
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -glyphSize * 0.012),
        blur: glyphSize * 0.03,
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )
    source.draw(
        in: NSRect(x: origin, y: origin, width: glyphSize, height: glyphSize),
        from: .zero, operation: .sourceOver, fraction: 1
    )
    context.restoreGState()
}

func write(_ rep: NSBitmapImageRep, to name: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name)")
}

// macOS
let mac = canvas(1024)
draw(on: mac) { context in
    let plate = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
        xRadius: 185, yRadius: 185
    )
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 22,
        color: NSColor.black.withAlphaComponent(0.3).cgColor
    )
    NSColor.white.setFill()
    plate.fill()
    context.restoreGState()
    plate.setClip()
    drawGlyph(sized: 580, in: 1024, context: context)
}
write(mac, to: "mac_1024.png")

// iOS
let ios = canvas(1024)
draw(on: ios) { context in
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    drawGlyph(sized: 758, in: 1024, context: context)
}
write(ios, to: "ios_1024.png")
