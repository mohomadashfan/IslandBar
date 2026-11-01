import AppKit
import CoreImage

/// Derives an accent colour from album artwork for the ambient glow and progress bar.
enum ArtworkPalette {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Average colour of the image, lifted so dark covers still produce a visible glow.
    static func accent(for image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let color = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        guard let hsb = color.usingColorSpace(.sRGB) else { return color }
        return NSColor(
            hue: hsb.hueComponent,
            saturation: min(1, hsb.saturationComponent * 1.3),
            brightness: max(0.6, hsb.brightnessComponent),
            alpha: 1
        )
    }
}
