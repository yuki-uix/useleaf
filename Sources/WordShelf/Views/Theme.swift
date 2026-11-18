import SwiftUI

enum WordShelfTheme {
    static let canvas = Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255)
    static let surface = Color.white
    static let ink = Color(red: 25 / 255, green: 48 / 255, blue: 68 / 255)
    static let secondary = Color(red: 88 / 255, green: 105 / 255, blue: 121 / 255)
    static let accent = Color(red: 25 / 255, green: 48 / 255, blue: 68 / 255)
    static let subtle = Color(red: 232 / 255, green: 247 / 255, blue: 241 / 255)
    static let border = Color(red: 216 / 255, green: 226 / 255, blue: 233 / 255)
    static let warning = Color(red: 148 / 255, green: 74 / 255, blue: 41 / 255)
}

struct WordShelfMark: View {
    var size: CGFloat = 32

    var body: some View {
        Canvas { context, dimensions in
            context.withCGContext { graphics in
                UseleafArtwork.draw(in: graphics, size: dimensions)
            }
        }
        .frame(width: size, height: size)
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
