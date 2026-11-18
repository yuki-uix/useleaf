import Foundation
import Testing
@testable import WordShelf
import WordShelfCore

@MainActor
private final class FakePronunciation: Pronouncing {
    var isSpeaking = false
    var onSpeakingChanged: ((Bool) -> Void)?
    private(set) var spoken: [String] = []
    private(set) var accents: [PronunciationAccent] = []
    private(set) var stopRequests = 0
    var nextError: Error?

    func speak(_ text: String, accent: PronunciationAccent) throws {
        finish()
        if let error = nextError { nextError = nil; throw error }
        spoken.append(text)
        accents.append(accent)
        isSpeaking = true
        onSpeakingChanged?(true)
    }

    func stop() {
        stopRequests += 1
        finish()
    }

    func finish() {
        guard isSpeaking else { return }
        isSpeaking = false
        onSpeakingChanged?(false)
    }
}

private actor SpeechFixtureDictionary: DictionaryLookingUp {
    private(set) var requests: [String] = []

    func lookup(_ word: String) async throws -> DictionaryEntry {
        requests.append(word)
        return DictionaryEntry(word: word, definitions: [DictionaryDefinition(text: "保留的查询释义")], sourceName: "Test")
    }
}

private enum SpeechFixtureError: LocalizedError {
    case unavailable
    var errorDescription: String? { "当前没有可用的英语语音，请在系统设置中添加。"}
}

@Suite("Pronunciation controls")
@MainActor
struct PronunciationModelTests {
    private func model(_ pronunciation: FakePronunciation) -> AppModel {
        AppModel(store: WordStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                 pronunciation: pronunciation)
    }

    private func savedStore(_ words: [String]) throws -> WordStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordShelf-saved-pronunciation-\(UUID().uuidString)")
        let store = WordStore(directoryURL: directory)
        for word in words { try store.add(word) }
        return store
    }

    private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }

    @Test("Pronunciation works before any dictionary or translation result and never saves data",
          arguments: ["stick", "stick with", "Please stick with this plan until Friday."])
    func pronounceOriginal(source: String) {
        let speech = FakePronunciation()
        let app = model(speech)
        app.query = source
        #expect(app.canPronounce)
        #expect(app.lookupState == .idle)
        #expect(!app.isPronouncing)
        app.pronounce(.american)
        #expect(speech.spoken == [source])
        #expect(app.isPronouncing)
        #expect(app.playingAccent == .american)
        #expect(speech.accents == [.american])
        #expect(app.words.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: app.store.fileURL.path))
        speech.finish()
        #expect(!app.isPronouncing)
        #expect(app.playingAccent == nil)
    }

    @Test func repeatedClickStopsInsteadOfQueuingAndCanReplay() {
        let speech = FakePronunciation()
        let app = model(speech)
        app.query = "stick with"
        app.pronounce(.american)
        app.pronounce(.american)
        #expect(!app.isPronouncing)
        #expect(speech.spoken.count == 1)
        app.pronounce(.american)
        #expect(app.isPronouncing)
        #expect(speech.spoken == ["stick with", "stick with"])
    }

    @Test func editingOrSubmittingAnotherQueryStopsThePreviousPronunciation() {
        let speech = FakePronunciation()
        let app = model(speech)
        app.query = "stick with"
        app.pronounce(.american)
        app.query = "Please keep reading."
        #expect(!app.isPronouncing)
        app.pronounce(.american)
        app.lookup("cache")
        #expect(!app.isPronouncing)
        #expect(speech.spoken == ["stick with", "Please keep reading."])
    }

    @Test func closingOrResettingLookupStopsPlayback() {
        let speech = FakePronunciation()
        let app = model(speech)
        app.query = "Read this sentence aloud."
        app.pronounce(.american)
        app.cancelLookup()
        #expect(!app.isPronouncing)
        app.pronounce(.american)
        app.prepareManualLookup()
        #expect(!app.isPronouncing)
        #expect(!app.canPronounce)
    }

    @Test func unavailableVoiceShowsRecoveryAndRetryClearsTheError() {
        let speech = FakePronunciation()
        speech.nextError = SpeechFixtureError.unavailable
        let app = model(speech)
        app.query = "hello"
        app.pronounce(.american)
        #expect(!app.isPronouncing)
        #expect(app.pronunciationError?.contains("英语语音") == true)
        app.pronounce(.american)
        #expect(app.pronunciationError == nil)
        #expect(app.isPronouncing)
    }

    @Test func invalidOrOverlongTextCannotStartPlayback() {
        let speech = FakePronunciation()
        let app = model(speech)
        for text in ["", "  \n", String(repeating: "x", count: SelectionText.maximumLength + 1)] {
            app.query = text
            #expect(!app.canPronounce)
            app.pronounce(.american)
        }
        #expect(speech.spoken.isEmpty)
    }

    @Test func changingAccentPlaysTheRequestedVariantWithoutASeparateStopClick() {
        let speech = FakePronunciation()
        let app = model(speech)
        app.query = "schedule"
        app.pronounce(.british)
        #expect(app.playingAccent == .british)
        app.pronounce(.american)
        #expect(app.isPronouncing)
        #expect(app.playingAccent == .american)
        #expect(speech.spoken == ["schedule", "schedule"])
        #expect(speech.accents == [.british, .american])
        speech.finish()
        #expect(!app.isPronouncing)
        #expect(app.playingAccent == nil)
    }

    @Test func clickingTheActiveBritishControlStopsAndDoesNotReplay() {
        let speech = FakePronunciation()
        let app = model(speech)
        app.query = "stick with"
        app.pronounce(.british)
        app.pronounce(.british)
        #expect(!app.isPronouncing)
        #expect(app.playingAccent == nil)
        #expect(speech.accents == [.british])
    }

    @Test func missingRequestedAccentIsExplainedAndAnotherAccentCanBePlayed() {
        let speech = FakePronunciation()
        let app = model(speech)
        app.query = "schedule"
        speech.nextError = PronunciationError.noVoice(.british)
        app.pronounce(.british)
        #expect(app.pronunciationError?.contains("英式") == true)
        #expect(app.playingAccent == nil)
        #expect(!app.isPronouncing)
        app.pronounce(.american)
        #expect(app.pronunciationError == nil)
        #expect(app.playingAccent == .american)
        #expect(speech.accents == [.american])
        #expect(app.words.isEmpty)
    }

    @Test func savedPronunciationKeepsTheLookupResultAndCollectionBytesUnchanged() async throws {
        let sentence = "The API is idempotent, so retry it.\nKeep the Original!"
        let other = "Schedule"
        let store = try savedStore([sentence, other])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let before = try Data(contentsOf: store.fileURL)
        let speech = FakePronunciation()
        let dictionary = SpeechFixtureDictionary()
        let app = AppModel(store: store, dictionary: dictionary, pronunciation: speech)
        app.lookup("cache")
        #expect(await waitFor { if case .found = app.lookupState { return true }; return false })
        let query = app.query
        let lookupWord = app.lookupWord
        let lookupState = app.lookupState
        let words = app.words
        var popupRequests = 0
        app.onShowManualLookup = { popupRequests += 1 }
        app.onShowCurrentLookup = { popupRequests += 1 }

        app.pronounceSavedWord(sentence, accent: .british)
        #expect(app.pronunciationSource == .notebook(sentence))
        #expect(app.playingAccent == .british)
        app.pronounceSavedWord(other, accent: .american)
        #expect(app.pronunciationSource == .notebook(other))
        #expect(app.playingAccent == .american)
        #expect(speech.spoken == [sentence, other])
        #expect(speech.accents == [.british, .american])
        #expect(app.query == query)
        #expect(app.lookupWord == lookupWord)
        #expect(app.lookupState == lookupState)
        #expect(await dictionary.requests == ["cache"])
        #expect(popupRequests == 0)
        #expect(app.words == words)
        #expect(try Data(contentsOf: store.fileURL) == before)
        #expect(WordStore(directoryURL: store.fileURL.deletingLastPathComponent()).words == words)
    }

    @Test func lookupAndSavedRowsWithTheSameAccentReplaceEachOtherAndOnlyTheActiveControlStops() throws {
        let first = "schedule"
        let second = "stick with"
        let store = try savedStore([first, second])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let speech = FakePronunciation()
        let app = AppModel(store: store, pronunciation: speech)
        app.query = first
        app.pronounce(.american)
        #expect(app.pronunciationSource == .lookup)

        app.pronounceSavedWord(first, accent: .american)
        #expect(app.isPronouncing)
        #expect(app.pronunciationSource == .notebook(first))
        app.pronounceSavedWord(second, accent: .american)
        #expect(app.isPronouncing)
        #expect(app.pronunciationSource == .notebook(second))
        app.pronounceSavedWord(second, accent: .british)
        #expect(app.isPronouncing)
        #expect(app.playingAccent == .british)
        app.pronounceSavedWord(second, accent: .british)
        #expect(!app.isPronouncing)
        #expect(app.playingAccent == nil)
        #expect(app.pronunciationSource == nil)
        #expect(speech.spoken == [first, first, second, second])
        app.pronounceSavedWord(second, accent: .british)
        #expect(app.isPronouncing)
        #expect(app.pronunciationSource == .notebook(second))
        #expect(speech.accents == [.american, .american, .american, .british, .british])

        app.pronounce(.british)
        #expect(app.isPronouncing)
        #expect(app.pronunciationSource == .lookup)
        #expect(speech.spoken.last == first)
    }

    @Test func savedPronunciationRejectsUncollectedTextAndPreservesTheStoredSpelling() throws {
        let store = try savedStore(["Cache"])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let before = try Data(contentsOf: store.fileURL)
        let speech = FakePronunciation()
        let app = AppModel(store: store, pronunciation: speech)
        app.pronounceSavedWord("never collected", accent: .british)
        #expect(speech.spoken.isEmpty)
        #expect(app.pronunciationSource == nil)

        app.pronounceSavedWord("Cache", accent: .american)
        let stops = speech.stopRequests
        // WordStore deduplicates words ignoring case; only the actual saved
        // row is a valid playback target, so a different spelling cannot take it over.
        app.pronounceSavedWord("cache", accent: .british)
        app.pronounceSavedWord("never collected", accent: .british)
        #expect(app.isPronouncing)
        #expect(app.pronunciationSource == .notebook("Cache"))
        #expect(app.playingAccent == .american)
        #expect(speech.spoken == ["Cache"])
        #expect(speech.stopRequests == stops)
        #expect(try Data(contentsOf: store.fileURL) == before)
    }

    @Test func missingVoiceErrorBelongsToItsSavedRowAndAnotherRowOrAccentCanRecover() throws {
        let first = "schedule"
        let second = "cache"
        let store = try savedStore([first, second])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let before = try Data(contentsOf: store.fileURL)
        let speech = FakePronunciation()
        let app = AppModel(store: store, pronunciation: speech)
        speech.nextError = PronunciationError.noVoice(.british)
        app.pronounceSavedWord(first, accent: .british)
        #expect(app.pronunciationSource == .notebook(first))
        #expect(app.pronunciationError?.contains("英式") == true)
        #expect(!app.isPronouncing)
        #expect(app.playingAccent == nil)

        app.pronounceSavedWord(second, accent: .american)
        #expect(app.pronunciationSource == .notebook(second))
        #expect(app.pronunciationError == nil)
        #expect(app.isPronouncing)
        speech.nextError = PronunciationError.noVoice(.british)
        app.pronounceSavedWord(first, accent: .british)
        #expect(app.pronunciationSource == .notebook(first))
        #expect(app.pronunciationError?.contains("英式") == true)
        #expect(!speech.isSpeaking)
        app.pronounceSavedWord(first, accent: .american)
        #expect(app.pronunciationSource == .notebook(first))
        #expect(app.pronunciationError == nil)
        #expect(app.playingAccent == .american)
        #expect(speech.spoken == [second, first])
        #expect(try Data(contentsOf: store.fileURL) == before)
    }

    @Test func naturalCompletionKeepsTheSourceAndNotebookStopLeavesLookupPlaybackAlone() throws {
        let saved = "stick with"
        let store = try savedStore([saved])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let speech = FakePronunciation()
        let app = AppModel(store: store, pronunciation: speech)
        app.pronounceSavedWord(saved, accent: .british)
        speech.finish()
        #expect(!app.isPronouncing)
        #expect(app.playingAccent == nil)
        #expect(app.pronunciationSource == .notebook(saved))
        app.stopNotebookPronunciation()
        #expect(app.pronunciationSource == nil)
        app.pronounceSavedWord(saved, accent: .british)
        app.stopNotebookPronunciation()
        #expect(!speech.isSpeaking)
        #expect(app.pronunciationSource == nil)

        app.query = "Read this lookup aloud."
        app.pronounce(.american)
        let stops = speech.stopRequests
        app.stopNotebookPronunciation()
        #expect(speech.stopRequests == stops)
        #expect(app.isPronouncing)
        #expect(app.playingAccent == .american)
        #expect(app.pronunciationSource == .lookup)
        speech.finish()
        #expect(!app.isPronouncing)
        #expect(app.pronunciationSource == .lookup)
        app.stopPronunciation()
        #expect(app.pronunciationSource == nil)
    }

    @Test(arguments: [false, true])
    func deletingAnotherSavedRowKeepsPlaybackOrErrorAndDeletingItsSourceClearsIt(failedPlayback: Bool) throws {
        let current = "schedule"
        let other = "cache"
        let remaining = "Keep this complete sentence."
        let store = try savedStore([current, other, remaining])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let speech = FakePronunciation()
        let app = AppModel(store: store, pronunciation: speech)
        if failedPlayback { speech.nextError = PronunciationError.noVoice(.british) }
        app.pronounceSavedWord(current, accent: .british)
        let isPronouncing = app.isPronouncing
        let accent = app.playingAccent
        let error = app.pronunciationError
        let stops = speech.stopRequests

        app.removeWord(other)
        #expect(app.pronunciationSource == .notebook(current))
        #expect(app.isPronouncing == isPronouncing)
        #expect(app.playingAccent == accent)
        #expect(app.pronunciationError == error)
        #expect(speech.stopRequests == stops)
        #expect(!app.words.contains(other))
        app.removeWord(current)
        #expect(!app.isPronouncing)
        #expect(app.playingAccent == nil)
        #expect(app.pronunciationSource == nil)
        #expect(app.pronunciationError == nil)
        #expect(!speech.isSpeaking)
        #expect(speech.stopRequests == stops + 1)
        #expect(app.words == [remaining])
        #expect(try JSONDecoder().decode([String].self, from: Data(contentsOf: store.fileURL)) == [remaining])
    }
}
