import Cocoa

// MARK: Icon: a monitor with three rising bars (the scale stages). One drawing serves the menu bar
// (template, so macOS tints it for light/dark) and the app icon (white on a gradient squircle).

func drawGlyph(in r: NSRect, _ color: NSColor, barAlpha: [CGFloat] = [1, 1, 1]) {
    let u = r.width
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: r.minX + x * u, y: r.minY + y * u, width: w * u, height: h * u) }
    color.setStroke(); color.setFill()
    let screen = NSBezierPath(roundedRect: rect(0.08, 0.30, 0.84, 0.58), xRadius: 0.09 * u, yRadius: 0.09 * u)
    screen.lineWidth = 0.075 * u
    screen.stroke()
    NSBezierPath(rect: rect(0.45, 0.17, 0.10, 0.13)).fill()
    NSBezierPath(roundedRect: rect(0.28, 0.10, 0.44, 0.075), xRadius: 0.035 * u, yRadius: 0.035 * u).fill()
    for (i, h) in [0.12, 0.22, 0.32].enumerated() {
        color.withAlphaComponent(barAlpha[i]).setFill()
        NSBezierPath(roundedRect: rect(0.25 + CGFloat(i) * 0.18, 0.42, 0.13, h), xRadius: 0.03 * u, yRadius: 0.03 * u).fill()
    }
}

func menuBarIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { drawGlyph(in: $0, .black); return true }
    img.isTemplate = true
    img.accessibilityDescription = "ScaleBar"
    return img
}

func appIcon(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), inset = s * 100 / 1024 // macOS icon grid: 824pt squircle in a 1024 canvas
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.36, green: 0.33, blue: 0.95, alpha: 1), NSColor(red: 0.16, green: 0.72, blue: 0.86, alpha: 1)])?
        .draw(in: shape, angle: -60)
    drawGlyph(in: tile.insetBy(dx: tile.width * 0.2, dy: tile.width * 0.2), .white, barAlpha: [0.7, 0.85, 1])
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}
