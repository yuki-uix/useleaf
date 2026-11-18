import Combine
import Foundation
import WordShelfCore

enum SavedExpressionDefinitionState: Equatable {
    case idle
    case loading
    case found(DictionaryEntry)
    case failed(String, needsLanguages: Bool)
}

/// Finder meanings live only for the current selection. A provider that finishes
/// after cancellation, dismissal or a new selection cannot replace that state.
@MainActor
final class SavedExpressionDetailModel: ObservableObject {
    @Published private(set) var state: SavedExpressionDefinitionState = .idle
    private var requestID = UUID()

    func clear() {
        requestID = UUID()
        state = .idle
    }

    func load(
        _ word: String?,
        using lookup: @MainActor (String) async throws -> DictionaryEntry
    ) async {
        let id = UUID()
        requestID = id
        guard let word else {
            state = .idle
            return
        }
        state = .loading
        do {
            let entry = try await lookup(word)
            guard !Task.isCancelled, requestID == id else { return }
            state = .found(entry)
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            let message = error is CancellationError ? "本次查译已取消，可以重试。" : error.localizedDescription
            state = .failed(message,
                            needsLanguages: (error as? TranslationServiceError) == .needsLanguages)
        }
    }
}
