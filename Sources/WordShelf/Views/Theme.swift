import SwiftUI

enum WordShelfTheme {
    static let canvas = Color(red: 0.97, green: 0.965, blue: 0.945)
    static let surface = Color(red: 0.995, green: 0.993, blue: 0.98)
    static let ink = Color(red: 0.17, green: 0.23, blue: 0.20)
    static let secondary = Color(red: 0.43, green: 0.47, blue: 0.43)
    static let accent = Color(red: 0.20, green: 0.37, blue: 0.29)
    static let subtle = Color(red: 0.90, green: 0.925, blue: 0.88)
    static let border = Color(red: 0.86, green: 0.88, blue: 0.83)
    static let warning = Color(red: 0.52, green: 0.36, blue: 0.17)
}

struct WordShelfMark: View {
    var size: CGFloat = 32

    var body: some View {
        Canvas { context, dimensions in
            let scale = dimensions.width / 1024
            context.scaleBy(x: scale, y: scale)
            var leaf = Path()
            leaf.move(to: CGPoint(x: 292, y: 650))
            leaf.addCurve(to: CGPoint(x: 362, y: 339), control1: CGPoint(x: 239, y: 544), control2: CGPoint(x: 270, y: 411))
            leaf.addCurve(to: CGPoint(x: 787, y: 235), control1: CGPoint(x: 470, y: 254), control2: CGPoint(x: 632, y: 282))
            leaf.addCurve(to: CGPoint(x: 682, y: 661), control1: CGPoint(x: 811, y: 415), control2: CGPoint(x: 791, y: 571))
            leaf.addCurve(to: CGPoint(x: 424, y: 718), control1: CGPoint(x: 615, y: 717), control2: CGPoint(x: 511, y: 737))
            leaf.addLine(to: CGPoint(x: 270, y: 800))
            leaf.closeSubpath()
            context.fill(leaf, with: .color(Color(red: 247 / 255, green: 244 / 255, blue: 232 / 255)))
            for x: CGFloat in [384, 518] {
                var quote = Path()
                quote.move(to: CGPoint(x: x + 24, y: 445))
                quote.addLine(to: CGPoint(x: x + 62, y: 445))
                quote.addCurve(to: CGPoint(x: x + 86, y: 469), control1: CGPoint(x: x + 76, y: 445), control2: CGPoint(x: x + 86, y: 455))
                quote.addLine(to: CGPoint(x: x + 86, y: 511))
                quote.addCurve(to: CGPoint(x: x + 15, y: 598), control1: CGPoint(x: x + 84, y: 553), control2: CGPoint(x: x + 60, y: 585))
                quote.addLine(to: CGPoint(x: x + 5, y: 572))
                quote.addCurve(to: CGPoint(x: x + 42, y: 534), control1: CGPoint(x: x + 29, y: 561), control2: CGPoint(x: x + 39, y: 547))
                quote.addLine(to: CGPoint(x: x + 24, y: 534))
                quote.addCurve(to: CGPoint(x: x, y: 510), control1: CGPoint(x: x + 10, y: 534), control2: CGPoint(x: x, y: 524))
                quote.addLine(to: CGPoint(x: x, y: 469))
                quote.addCurve(to: CGPoint(x: x + 24, y: 445), control1: CGPoint(x: x, y: 455), control2: CGPoint(x: x + 10, y: 445))
                quote.closeSubpath()
                context.fill(quote, with: .color(Color(red: 30 / 255, green: 91 / 255, blue: 79 / 255)))
            }
        }
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(red: 47 / 255, green: 125 / 255, blue: 109 / 255), Color(red: 18 / 255, green: 63 / 255, blue: 59 / 255)], startPoint: .topTrailing, endPoint: .bottomLeading),
                in: RoundedRectangle(cornerRadius: size * 0.23)
            )
            .accessibilityHidden(true)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WordShelfTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                configuration.isPressed ? WordShelfTheme.subtle : WordShelfTheme.surface,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(WordShelfTheme.border, lineWidth: 1)
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : WordShelfTheme.secondary)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(
                isEnabled ? WordShelfTheme.accent.opacity(configuration.isPressed ? 0.8 : 1) : WordShelfTheme.subtle,
                in: RoundedRectangle(cornerRadius: 9)
            )
    }
}

struct ShortcutKey: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(WordShelfTheme.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(WordShelfTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(WordShelfTheme.border.opacity(0.8), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
