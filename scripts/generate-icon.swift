import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draw the menu bar's square.grid.2x2 motif as a standalone app icon.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot create icon context") }
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = CGPath(roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928),
            cornerWidth: 210, cornerHeight: 210, transform: nil)
        context.addPath(background)
        context.setFillColor(CGColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1))
        context.fillPath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(42)
        for x in [CGFloat(248), CGFloat(556)] {
            for y in [CGFloat(248), CGFloat(556)] {
                context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 220, height: 220),
                    cornerWidth: 42, cornerHeight: 42, transform: nil))
                context.strokePath()
            }
        }
        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fatalError("Cannot encode icon") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save icon") }
    }
}
