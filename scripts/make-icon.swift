// Draws IslandBar's app icon and writes Support/AppIcon.icns.
//
// Usage: swift scripts/make-icon.swift            (run from the repository root)
//
// The artwork is generated from code so it is original, reviewable and reproducible: a night-sky
// squircle with a black "island" capsule at the top, showing a tiny live activity (artwork
// tile and level meter), glowing softly onto the surface below.

import AppKit

let canvas: CGFloat = 1024

func makeIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824 pt body centred on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(bodyPath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()

    // Night-sky gradient.
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.36, alpha: 1).cgColor,
        NSColor(srgbRed: 0.05, green: 0.06, blue: 0.14, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Aurora glows.
    func glow(_ center: CGPoint, _ radius: CGFloat, _ color: NSColor) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    glow(CGPoint(x: 330, y: 260), 420, NSColor(srgbRed: 0.18, green: 0.85, blue: 0.75, alpha: 0.45))
    glow(CGPoint(x: 760, y: 330), 380, NSColor(srgbRed: 0.55, green: 0.35, blue: 1.0, alpha: 0.45))
    glow(CGPoint(x: 512, y: 640), 300, NSColor(srgbRed: 0.40, green: 0.60, blue: 1.0, alpha: 0.30))

    // Subtle top sheen.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor.white.withAlphaComponent(0.14).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])

    // The island: a black capsule hanging from the top edge, with a soft light beneath it.
    let island = CGRect(x: 232, y: 640, width: 560, height: 150)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 60, color: NSColor(srgbRed: 0.45, green: 0.75, blue: 1, alpha: 0.55).cgColor)
    context.addPath(CGPath(roundedRect: island, cornerWidth: 75, cornerHeight: 75, transform: nil))
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Rim light on the capsule.
    context.addPath(CGPath(roundedRect: island.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 73, cornerHeight: 73, transform: nil))
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    context.setLineWidth(3)
    context.strokePath()

    // Live activity: a tiny artwork tile on the left...
    let tile = CGRect(x: island.minX + 42, y: island.midY - 42, width: 84, height: 84)
    context.saveGState()
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 22, cornerHeight: 22, transform: nil))
    context.clip()
    let art = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 1.0, green: 0.62, blue: 0.25, alpha: 1).cgColor,
        NSColor(srgbRed: 0.93, green: 0.25, blue: 0.55, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(art, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    context.restoreGState()

    // ...and a level meter on the right.
    let heights: [CGFloat] = [34, 66, 48, 80, 40]
    let barWidth: CGFloat = 16
    var x = island.maxX - 42 - CGFloat(heights.count) * barWidth - CGFloat(heights.count - 1) * 12
    for height in heights {
        let bar = CGRect(x: x, y: island.midY - height / 2, width: barWidth, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.setFillColor(NSColor(srgbRed: 0.30, green: 0.92, blue: 0.75, alpha: 1).cgColor)
        context.fillPath()
        x += barWidth + 12
    }

    // Reflection of the island on the "surface".
    glow(CGPoint(x: 512, y: 470), 210, NSColor.white.withAlphaComponent(0.10))

    context.restoreGState()

    // Hairline edge.
    context.addPath(CGPath(roundedRect: body.insetBy(dx: 1, dy: 1), cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    context.setLineWidth(2)
    context.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func resized(_ rep: NSBitmapImageRep, to size: Int) -> Data {
    let target = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return target.representation(using: .png, properties: [:])!
}

let master = makeIcon()
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try resized(master, to: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try resized(master, to: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try resized(master, to: 1024).write(to: URL(fileURLWithPath: "Support/AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Support/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("Wrote Support/AppIcon.icns and Support/AppIcon-1024.png")
