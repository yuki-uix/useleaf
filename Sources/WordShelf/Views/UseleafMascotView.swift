import SwiftUI

/// Shared, decorative artwork. Learning state and controls remain in their
/// existing views; the character never supplies or reveals an answer.
struct UseleafMascotView: View {
    var pose: UseleafMascotPose = .idle
    var size: CGFloat = 42

    var body: some View {
        Canvas { context, dimensions in
            context.withCGContext { graphics in
                UseleafArtwork.draw(in: graphics, size: dimensions, pose: pose, includesTile: false)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// One short, silent acknowledgement for a new insertion. The task is tied to
/// its event and cancelled when the confirmation leaves the lookup view.
struct UseleafSaveConfirmationView: View {
    let confirmation: SaveConfirmation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPecking = false

    var body: some View {
        HStack(spacing: 8) {
            UseleafMascotView(size: 40)
                .rotationEffect(.degrees(isPecking ? 12 : 0), anchor: .center)
            Text("已收好，继续阅读。")
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lookup.saveConfirmation")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isPecking)
        .task(id: confirmation.id) {
            guard !reduceMotion else { return }
            isPecking = true
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled else { return }
            isPecking = false
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { isPecking = false }
        }
        .onDisappear { isPecking = false }
    }
}
