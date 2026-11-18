// The app and icon renderer use the same original CoreGraphics artwork.
// Compile with Sources/WordShelf/Views/UseleafArtwork.swift (see build_app.sh).
import AppKit
import Foundation

@main
struct UseleafIconRenderer {
    static func main() throws {
        guard (2...3).contains(CommandLine.arguments.count) else {
            fputs("Usage: make-useleaf-icon <output.iconset> [brand-output-directory]\n", stderr)
            exit(2)
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sizes = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                     (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]
        for (size, name) in sizes {
            try png(size: size).write(to: destination.appendingPathComponent("icon_\(name).png"))
        }
        if CommandLine.arguments.count == 3 {
            let brand = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)
            try png(size: 1024).write(to: brand.appendingPathComponent("Useleaf-1024.png"))
            try UseleafArtwork.svg().write(to: brand.appendingPathComponent("Useleaf.svg"), atomically: true, encoding: .utf8)
        }
    }

    private static func png(size: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        UseleafArtwork.draw(in: context, size: CGSize(width: size, height: size))
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        return data
    }
}
