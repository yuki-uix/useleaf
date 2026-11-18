// Reproducible vector artwork for Useleaf. No external fonts or image assets.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make_icon.swift <output.iconset>\n", stderr)
    exit(2)
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
             (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
             (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

// A leaf that opens into a conversation. Coordinates match Support/Brand/Useleaf.svg.
func leaf() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 292, y: 374))
    path.curve(to: NSPoint(x: 362, y: 685), controlPoint1: NSPoint(x: 239, y: 480), controlPoint2: NSPoint(x: 270, y: 613))
    path.curve(to: NSPoint(x: 787, y: 789), controlPoint1: NSPoint(x: 470, y: 770), controlPoint2: NSPoint(x: 632, y: 742))
    path.curve(to: NSPoint(x: 682, y: 363), controlPoint1: NSPoint(x: 811, y: 609), controlPoint2: NSPoint(x: 791, y: 453))
    path.curve(to: NSPoint(x: 424, y: 306), controlPoint1: NSPoint(x: 615, y: 307), controlPoint2: NSPoint(x: 511, y: 287))
    path.line(to: NSPoint(x: 270, y: 224))
    path.line(to: NSPoint(x: 292, y: 374))
    path.close()
    return path
}

func quote(at x: CGFloat, y: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x + 24, y: y + 103))
    path.line(to: NSPoint(x: x + 62, y: y + 103))
    path.curve(to: NSPoint(x: x + 86, y: y + 79), controlPoint1: NSPoint(x: x + 76, y: y + 103), controlPoint2: NSPoint(x: x + 86, y: y + 93))
    path.line(to: NSPoint(x: x + 86, y: y + 37))
    path.curve(to: NSPoint(x: x + 15, y: y - 50), controlPoint1: NSPoint(x: x + 84, y: y - 5), controlPoint2: NSPoint(x: x + 60, y: y - 37))
    path.line(to: NSPoint(x: x + 5, y: y - 24))
    path.curve(to: NSPoint(x: x + 42, y: y + 14), controlPoint1: NSPoint(x: x + 29, y: y - 13), controlPoint2: NSPoint(x: x + 39, y: y + 1))
    path.line(to: NSPoint(x: x + 24, y: y + 14))
    path.curve(to: NSPoint(x: x, y: y + 38), controlPoint1: NSPoint(x: x + 10, y: y + 14), controlPoint2: NSPoint(x: x, y: y + 24))
    path.line(to: NSPoint(x: x, y: y + 79))
    path.curve(to: NSPoint(x: x + 24, y: y + 103), controlPoint1: NSPoint(x: x, y: y + 93), controlPoint2: NSPoint(x: x + 10, y: y + 103))
    path.close()
    return path
}

for (size, name) in sizes {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.setShouldAntialias(true)

    let tile = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 216, yRadius: 216)
    NSGradient(starting: color(18, 63, 59), ending: color(47, 125, 109))!.draw(in: tile, angle: 55)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(247, 244, 232).setFill()
    leaf().fill()
    NSGraphicsContext.restoreGraphicsState()

    color(30, 91, 79).setFill()
    quote(at: 384, y: 476).fill()
    quote(at: 518, y: 476).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try png.write(to: destination.appendingPathComponent("icon_\(name).png"))
}
