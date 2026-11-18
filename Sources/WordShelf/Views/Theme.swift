import AppKit
import SwiftUI

enum WordShelfTheme {
    static let canvas = adaptive(0xF3F6F8, 0x1E292F)
    static let surface = adaptive(0xFCFCFB, 0x243139)
    static let ink = adaptive(0x203546, 0xE3EDF3)
    static let secondary = adaptive(0x657681, 0xA4B4BF)
    static let accent = adaptive(0x203B4C, 0xDCEAF0)
    static let onAccent = adaptive(0xFFFFFF, 0x19303C)
    static let subtle = adaptive(0xE5F4ED, 0x294139)
    static let success = adaptive(0x286C59, 0x92DFC6)
    static let border = adaptive(0xD9E2E6, 0x40515B)
    static let warning = adaptive(0x944A29, 0xEFBD91)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        })
    }
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
            .foregroundStyle(isEnabled ? WordShelfTheme.onAccent : WordShelfTheme.secondary)
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
