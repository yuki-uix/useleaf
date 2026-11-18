import CoreGraphics
import Foundation

enum UseleafMascotPose: Equatable, Sendable {
    case idle
    case saved
    case recall
    case rest
}

/// Original Useleaf artwork. Geometry uses a 1024-square, top-left coordinate
/// system, shared by the application, raster icon renderer and SVG export.
enum UseleafArtwork {
    private enum Pigment: String {
        case porcelain = "#F3F6FA"
        case ink = "#193044"
        case mint = "#4ED7B5"
        case coral = "#FF5D62"
        case white = "#FFFFFF"

        var color: CGColor {
            let value = UInt32(rawValue.dropFirst(), radix: 16)!
            return CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }

    private struct Layer {
        let path: CGPath
        let pigment: Pigment
    }

    /// Call directly from SwiftUI Canvas.withCGContext. Bitmap contexts whose
    /// origin is bottom-left should be flipped by the caller before drawing.
    static func draw(in context: CGContext, size: CGSize,
                     pose: UseleafMascotPose = .idle, includesTile: Bool = true) {
        guard size.width > 0, size.height > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let scale = min(size.width, size.height) / 1024
        context.translateBy(x: (size.width - 1024 * scale) / 2,
                            y: (size.height - 1024 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        // Preserve the silhouette at 16px, where two tiny quotes merge into a
        // dark speck. Larger icons and in-app poses retain the quotation wing.
        for layer in layers(pose: pose, includesTile: includesTile,
                            includesQuotes: min(size.width, size.height) >= 32 || !includesTile) {
            context.addPath(layer.path)
            context.setFillColor(layer.pigment.color)
            context.fillPath()
        }
    }

    static func svg(pose: UseleafMascotPose = .idle, includesTile: Bool = true) -> String {
        let paths = layers(pose: pose, includesTile: includesTile, includesQuotes: true).map { layer in
            "  <path fill=\"\(layer.pigment.rawValue)\" d=\"\(svgPath(layer.path))\"/>"
        }.joined(separator: "\n")
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="Useleaf woodpecker with a leaf-shaped quotation wing">
        \(paths)
        </svg>

        """
    }

    private static func layers(pose: UseleafMascotPose, includesTile: Bool,
                               includesQuotes: Bool) -> [Layer] {
        var result: [Layer] = []
        if includesTile {
            result.append(Layer(path: CGPath(roundedRect: CGRect(x: 32, y: 32, width: 960, height: 960),
                                            cornerWidth: 216, cornerHeight: 216, transform: nil),
                                pigment: .porcelain))
        }

        let body = CGMutablePath()
        body.move(to: CGPoint(x: 228, y: 890))
        body.addCurve(to: CGPoint(x: 280, y: 538), control1: CGPoint(x: 218, y: 721), control2: CGPoint(x: 238, y: 621))
        body.addCurve(to: CGPoint(x: 369, y: 422), control1: CGPoint(x: 303, y: 491), control2: CGPoint(x: 337, y: 452))
        body.addCurve(to: CGPoint(x: 409, y: 330), control1: CGPoint(x: 397, y: 395), control2: CGPoint(x: 401, y: 365))
        body.addCurve(to: CGPoint(x: 501, y: 223), control1: CGPoint(x: 413, y: 283), control2: CGPoint(x: 451, y: 237))
        body.addCurve(to: CGPoint(x: 616, y: 244), control1: CGPoint(x: 541, y: 214), control2: CGPoint(x: 581, y: 224))
        body.addLine(to: CGPoint(x: 866, y: 164))
        body.addLine(to: CGPoint(x: 671, y: 349))
        body.addCurve(to: CGPoint(x: 680, y: 430), control1: CGPoint(x: 669, y: 364), control2: CGPoint(x: 673, y: 392))
        body.addCurve(to: CGPoint(x: 609, y: 766), control1: CGPoint(x: 712, y: 585), control2: CGPoint(x: 685, y: 700))
        body.addCurve(to: CGPoint(x: 343, y: 827), control1: CGPoint(x: 529, y: 835), control2: CGPoint(x: 433, y: 824))
        body.closeSubpath()

        let wing = CGMutablePath()
        wing.move(to: CGPoint(x: 239, y: 802))
        wing.addCurve(to: CGPoint(x: 342, y: 527), control1: CGPoint(x: 239, y: 671), control2: CGPoint(x: 273, y: 576))
        wing.addCurve(to: CGPoint(x: 553, y: 491), control1: CGPoint(x: 407, y: 482), control2: CGPoint(x: 477, y: 474))
        wing.addCurve(to: CGPoint(x: 465, y: 757), control1: CGPoint(x: 590, y: 611), control2: CGPoint(x: 552, y: 721))
        wing.addCurve(to: CGPoint(x: 239, y: 802), control1: CGPoint(x: 388, y: 786), control2: CGPoint(x: 320, y: 755))
        wing.closeSubpath()

        let crest = CGMutablePath()
        crest.move(to: CGPoint(x: 310, y: 246))
        crest.addCurve(to: CGPoint(x: 517, y: 190), control1: CGPoint(x: 384, y: 258), control2: CGPoint(x: 448, y: 192))
        crest.addCurve(to: CGPoint(x: 655, y: 249), control1: CGPoint(x: 570, y: 184), control2: CGPoint(x: 613, y: 204))
        crest.addCurve(to: CGPoint(x: 508, y: 249), control1: CGPoint(x: 595, y: 214), control2: CGPoint(x: 542, y: 215))
        crest.addCurve(to: CGPoint(x: 401, y: 333), control1: CGPoint(x: 465, y: 284), control2: CGPoint(x: 442, y: 327))
        crest.addCurve(to: CGPoint(x: 310, y: 246), control1: CGPoint(x: 366, y: 328), control2: CGPoint(x: 330, y: 288))
        crest.closeSubpath()

        var bird = [Layer(path: body, pigment: .ink), Layer(path: wing, pigment: .mint)]
        if includesQuotes {
            bird.append(Layer(path: quote(x: 341, y: 573), pigment: .ink))
            bird.append(Layer(path: quote(x: 435, y: 573), pigment: .ink))
        }
        bird.append(Layer(path: CGPath(ellipseIn: CGRect(x: 466, y: 223, width: 224, height: 230), transform: nil), pigment: .white))
        bird.append(Layer(path: crest, pigment: .coral))
        if pose == .rest {
            let eye = CGMutablePath()
            eye.move(to: CGPoint(x: 574, y: 298))
            eye.addCurve(to: CGPoint(x: 616, y: 298), control1: CGPoint(x: 585, y: 319), control2: CGPoint(x: 605, y: 319))
            bird.append(Layer(path: eye.copy(strokingWithWidth: 13, lineCap: .round, lineJoin: .round, miterLimit: 1), pigment: .ink))
        } else {
            bird.append(Layer(path: CGPath(ellipseIn: CGRect(x: 574, y: 277, width: 42, height: 42), transform: nil), pigment: .ink))
        }

        let angle: CGFloat
        switch pose {
        case .saved: angle = 20 * .pi / 180
        case .recall: angle = -4 * .pi / 180
        case .idle, .rest: angle = 0
        }
        if angle != 0 {
            var transform = CGAffineTransform(translationX: 520, y: 500)
                .rotated(by: angle).translatedBy(x: -520, y: -500)
            bird = bird.map { Layer(path: $0.path.copy(using: &transform)!, pigment: $0.pigment) }
        }
        result.append(contentsOf: bird)
        return result
    }

    private static func quote(x: CGFloat, y: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + 16, y: y))
        path.addLine(to: CGPoint(x: x + 45, y: y))
        path.addCurve(to: CGPoint(x: x + 61, y: y + 16), control1: CGPoint(x: x + 54, y: y), control2: CGPoint(x: x + 61, y: y + 7))
        path.addLine(to: CGPoint(x: x + 61, y: y + 49))
        path.addCurve(to: CGPoint(x: x + 11, y: y + 111), control1: CGPoint(x: x + 60, y: y + 78), control2: CGPoint(x: x + 43, y: y + 101))
        path.addLine(to: CGPoint(x: x + 4, y: y + 92))
        path.addCurve(to: CGPoint(x: x + 30, y: y + 65), control1: CGPoint(x: x + 21, y: y + 84), control2: CGPoint(x: x + 28, y: y + 74))
        path.addLine(to: CGPoint(x: x + 16, y: y + 65))
        path.addCurve(to: CGPoint(x: x, y: y + 49), control1: CGPoint(x: x + 7, y: y + 65), control2: CGPoint(x: x, y: y + 58))
        path.addLine(to: CGPoint(x: x, y: y + 16))
        path.addCurve(to: CGPoint(x: x + 16, y: y), control1: CGPoint(x: x, y: y + 7), control2: CGPoint(x: x + 7, y: y))
        path.closeSubpath()
        return path
    }

    private static func svgPath(_ path: CGPath) -> String {
        var commands: [String] = []
        func number(_ value: CGFloat) -> String {
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
                .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
        func point(_ p: CGPoint) -> String { "\(number(p.x)) \(number(p.y))" }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: commands.append("M\(point(element.points[0]))")
            case .addLineToPoint: commands.append("L\(point(element.points[0]))")
            case .addQuadCurveToPoint: commands.append("Q\(point(element.points[0])) \(point(element.points[1]))")
            case .addCurveToPoint: commands.append("C\(point(element.points[0])) \(point(element.points[1])) \(point(element.points[2]))")
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return commands.joined(separator: " ")
    }
}
