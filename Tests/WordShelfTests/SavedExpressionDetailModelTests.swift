import Foundation
import Testing
@testable import WordShelf
import WordShelfCore

private actor FinderControlledLookup {
    private var pending: [String: CheckedContinuation<DictionaryEntry, Error>] = [:]

    func lookup(_ word: String) async throws -> DictionaryEntry {
        try await withCheckedThrowingContinuation { pending[word] = $0 }
    }

    func isPending(_ word: String) -> Bool { pending[word] != nil }

    func finish(_ word: String) {
        pending.removeValue(forKey: word)?.resume(returning: DictionaryEntry(
            word: word,
            definitions: [DictionaryDefinition(text: "临时释义")],
            sourceName: "Test"
        ))
    }
}

@Suite("Temporary finder definitions")
@MainActor
struct SavedExpressionDetailModelTests {
    private func waitForPending(_ word: String, in provider: FinderControlledLookup) async -> Bool {
        for _ in 0..<1_000 {
            if await provider.isPending(word) { return true }
            await Task.yield()
        }
        return false
    }

    @Test func latePreviousSelectionCannotReplaceCurrentMeaning() async {
        let provider = FinderControlledLookup()
        let detail = SavedExpressionDetailModel()
        let first = Task { await detail.load("stick with") { try await provider.lookup($0) } }
        #expect(await waitForPending("stick with", in: provider))
        let second = Task { await detail.load("make sense") { try await provider.lookup($0) } }
        #expect(await waitForPending("make sense", in: provider))

        await provider.finish("make sense")
        await second.value
        guard case .found(let current) = detail.state else {
            Issue.record("The current expression should have a definition")
            await provider.finish("stick with")
            await first.value
            return
        }
        #expect(current.word == "make sense")

        await provider.finish("stick with")
        await first.value
        #expect(detail.state == .found(current))
    }

    @Test func dismissedFinderIgnoresProviderThatFinishesAfterCancellation() async {
        let provider = FinderControlledLookup()
        let detail = SavedExpressionDetailModel()
        let pending = Task { await detail.load("stick with") { try await provider.lookup($0) } }
        #expect(await waitForPending("stick with", in: provider))
        pending.cancel()
        detail.clear()

        await provider.finish("stick with")
        await pending.value
        #expect(detail.state == .idle)
    }

    @Test func missingLanguageFailureKeepsAnExplicitRecoveryState() async {
        let detail = SavedExpressionDetailModel()
        await detail.load("stick with") { _ in throw TranslationServiceError.needsLanguages }
        #expect(detail.state == .failed(TranslationServiceError.needsLanguages.localizedDescription,
                                        needsLanguages: true))
    }
}
