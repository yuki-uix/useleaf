import Foundation
import Testing
@testable import WordShelf
import WordShelfCore

private actor ControlledDictionary: DictionaryLookingUp {
    private var pending: [String: CheckedContinuation<DictionaryEntry, Error>] = [:]

    func lookup(_ word: String) async throws -> DictionaryEntry {
        try await withCheckedThrowingContinuation { pending[word] = $0 }
    }

    func isPending(_ word: String) -> Bool { pending[word] != nil }

    func finish(_ word: String) {
        pending.removeValue(forKey: word)?.resume(returning: DictionaryEntry(
            word: word, definitions: [DictionaryDefinition(text: "测试释义")], sourceName: "Test"
        ))
    }

    func miss(_ word: String) {
        pending.removeValue(forKey: word)?.resume(throwing: DictionaryError.notFound(word))
    }
}

private actor MissingDictionary: DictionaryLookingUp {
    func lookup(_ word: String) async throws -> DictionaryEntry {
        throw DictionaryError.notFound(word)
    }
}

private actor SaveFeedbackDictionary: DictionaryLookingUp {
    func lookup(_ word: String) async throws -> DictionaryEntry {
        DictionaryEntry(word: word, definitions: [DictionaryDefinition(text: "测试释义")], sourceName: "Test")
    }
}

@MainActor
private final class ControlledTranslator: TextTranslating {
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private(set) var requests: [String] = []
    func translate(_ text: String) async throws -> String {
        requests.append(text)
        return try await withCheckedThrowingContinuation { pending[text] = $0 }
    }
    func prepareLanguages() async throws {}
    func isPending(_ text: String) -> Bool { pending[text] != nil }
    func finish(_ text: String, translated: String) { pending.removeValue(forKey: text)?.resume(returning: translated) }
    func fail(_ text: String, error: TranslationServiceError) { pending.removeValue(forKey: text)?.resume(throwing: error) }
}

@MainActor
private final class SetupTranslator: TextTranslating {
    private(set) var prepared = false
    func translate(_ text: String) async throws -> String {
        guard prepared else { throw TranslationServiceError.needsLanguages }
        return "请继续阅读。"
    }
    func prepareLanguages() async throws { prepared = true }
}

@MainActor
private final class CancelledSetupTranslator: TextTranslating {
    func translate(_ text: String) async throws -> String { throw TranslationServiceError.needsLanguages }
    func prepareLanguages() async throws { throw CancellationError() }
}

@MainActor
private func waitFor(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

@Suite("Lookup and collection flow")
@MainActor
struct AppModelTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WordShelf-model-tests-\(UUID().uuidString)")
    }

    @Test func onlyExplicitCollectionPersistsAndChangedInputCannotSaveOldResult() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = ControlledDictionary()
        let store = WordStore(directoryURL: directory)
        let model = AppModel(store: store, dictionary: dictionary)
        model.lookup("  Resilient  ")
        #expect(model.lookupWord == "Resilient")
        #expect(model.words.isEmpty)
        #expect(await waitFor { await dictionary.isPending("Resilient") })
        await dictionary.finish("Resilient")
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        model.query = "ephemeral"
        #expect(!model.canSaveCurrentWord)
        model.saveCurrentWord()
        #expect(model.words.isEmpty)
        model.query = "Resilient"
        model.saveCurrentWord()
        model.saveCurrentWord()
        #expect(model.words == ["Resilient"])
        #expect(model.currentWordIsSaved)
        let saved = try JSONDecoder().decode([String].self, from: Data(contentsOf: store.fileURL))
        #expect(saved == ["Resilient"])
        #expect(WordStore(directoryURL: directory).words == ["Resilient"])
    }

    @Test func aNewSaveConfirmsThePersistedOriginalWithoutAddingCollectionMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        let model = AppModel(store: store, dictionary: SaveFeedbackDictionary())
        defer { model.cancelLookup() }
        let original = "Could you clarify this?\nI mean the deployment."
        model.lookup(original)
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        #expect(model.saveConfirmation == nil)
        model.saveCurrentWord()

        let confirmation = try #require(model.saveConfirmation)
        #expect(confirmation.original == original)
        #expect(model.currentSaveConfirmation == confirmation)
        #expect(model.notice == nil)
        let bytes = try Data(contentsOf: store.fileURL)
        #expect(try JSONDecoder().decode([String].self, from: bytes) == [original])
        let reopened = AppModel(store: WordStore(directoryURL: directory), dictionary: SaveFeedbackDictionary())
        #expect(reopened.words == [original])
        #expect(reopened.saveConfirmation == nil)

        model.lookup("Follow up")
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        model.saveCurrentWord()
        let next = try #require(model.saveConfirmation)
        #expect(next.id != confirmation.id)
        #expect(next.original == "Follow up")
        #expect(try JSONDecoder().decode([String].self, from: Data(contentsOf: store.fileURL)) == ["Follow up", original])
    }

    @Test func existingAndRepeatedSavesDoNotReplayConfirmationOrRewriteTheCollection() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        try store.add("Resilient")
        let existingBytes = try Data(contentsOf: store.fileURL)
        let model = AppModel(store: store, dictionary: SaveFeedbackDictionary())
        defer { model.cancelLookup() }
        model.lookup("resilient")
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        #expect(model.currentWordIsSaved)
        #expect(model.saveConfirmation == nil)
        model.saveCurrentWord()
        #expect(model.saveConfirmation == nil)
        #expect(model.currentSaveConfirmation == nil)
        #expect(try Data(contentsOf: store.fileURL) == existingBytes)

        model.lookup("New expression")
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        model.saveCurrentWord()
        #expect(model.saveConfirmation != nil)
        let insertedBytes = try Data(contentsOf: store.fileURL)
        model.saveCurrentWord()
        #expect(model.saveConfirmation == nil)
        #expect(model.currentSaveConfirmation == nil)
        #expect(try Data(contentsOf: store.fileURL) == insertedBytes)
        #expect(model.words == ["New expression", "Resilient"])
    }

    @Test func saveFailuresNeverConfirmSuccessAndPreserveTheBlockingOrCorruptFile() async throws {
        for corruptCollection in [false, true] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let preservedURL: URL
            let originalBytes: Data
            if corruptCollection {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                preservedURL = directory.appendingPathComponent("words.json")
                originalBytes = Data("{not a vocabulary array}".utf8)
            } else {
                // A regular file at the directory path makes createDirectory fail
                // deterministically, including when tests run with elevated rights.
                preservedURL = directory
                originalBytes = Data("keep this file".utf8)
            }
            try originalBytes.write(to: preservedURL)
            let model = AppModel(store: WordStore(directoryURL: directory), dictionary: SaveFeedbackDictionary())
            defer { model.cancelLookup() }
            model.lookup("cache")
            #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
            model.saveCurrentWord()
            #expect(model.saveConfirmation == nil)
            #expect(model.currentSaveConfirmation == nil)
            #expect(model.words.isEmpty)
            #expect(model.notice?.contains("收藏失败") == true)
            #expect(try Data(contentsOf: preservedURL) == originalBytes)
        }
    }

    @Test func saveConfirmationDoesNotFollowEditingRequeryOrLeavingThePopup() async throws {
        for action in ["edit", "new lookup", "same lookup", "cancel", "dismiss", "manual", "remove and undo"] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = WordStore(directoryURL: directory)
            let model = AppModel(store: store, dictionary: SaveFeedbackDictionary())
            defer { model.cancelLookup() }
            model.lookup("Resilient")
            #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
            model.saveCurrentWord()
            #expect(model.currentSaveConfirmation != nil)
            let savedBytes = try Data(contentsOf: store.fileURL)

            switch action {
            case "edit": model.query = "Resilient!"
            case "new lookup": model.lookup("ephemeral")
            case "same lookup": model.lookup("Resilient")
            case "cancel": model.cancelLookup()
            case "dismiss": model.dismissPopup()
            case "remove and undo":
                model.removeWord("Resilient")
                #expect(model.saveConfirmation == nil)
                model.undoRemoval()
            default: model.prepareManualLookup()
            }
            #expect(model.saveConfirmation == nil)
            #expect(model.currentSaveConfirmation == nil)
            if action.contains("lookup") {
                #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
                #expect(model.saveConfirmation == nil)
            }
            #expect(model.words == ["Resilient"])
            #expect(try Data(contentsOf: store.fileURL) == savedBytes)
        }
    }

    @Test func manualLookupClearsPriorCaptureFailure() async {
        let dictionary = ControlledDictionary()
        let model = AppModel(store: WordStore(directoryURL: temporaryDirectory()), dictionary: dictionary)
        model.captureMessage = "之前没有读取到选词"
        model.lookup("cache")
        #expect(model.captureMessage == nil)
        #expect(await waitFor { await dictionary.isPending("cache") })
        await dictionary.finish("cache")
    }

    @Test func olderLookupCannotReplaceNewerResult() async {
        let dictionary = ControlledDictionary()
        let model = AppModel(store: WordStore(directoryURL: temporaryDirectory()), dictionary: dictionary)
        model.lookup("old")
        #expect(await waitFor { await dictionary.isPending("old") })
        model.lookup("new")
        #expect(await waitFor { await dictionary.isPending("new") })
        await dictionary.finish("new")
        #expect(await waitFor { if case .found(let entry) = model.lookupState { return entry.word == "new" }; return false })
        await dictionary.finish("old")
        await Task.yield()
        #expect(model.lookupWord == "new")
        if case .found(let entry) = model.lookupState { #expect(entry.word == "new") }
        else { Issue.record("A successful newer result should remain visible") }
    }

    @Test func invalidQueryClearsPreviousSaveTargetAndManualModeResets() async {
        let dictionary = ControlledDictionary()
        let model = AppModel(store: WordStore(directoryURL: temporaryDirectory()), dictionary: dictionary)
        model.lookup("word")
        #expect(await waitFor { await dictionary.isPending("word") })
        model.lookup("")
        #expect(model.lookupWord == nil)
        #expect(!model.canSaveCurrentWord)
        model.saveCurrentWord()
        #expect(model.words.isEmpty)
        await dictionary.finish("word")
        model.prepareManualLookup()
        #expect(model.query.isEmpty)
        #expect(model.lookupState == .idle)
    }

    @Test func removalCanBeUndoneAndRestoredOnDisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        try store.add("ephemeral")
        let model = AppModel(store: store)
        model.removeWord("ephemeral")
        #expect(model.words.isEmpty)
        #expect(model.canUndoRemoval)
        model.undoRemoval()
        #expect(model.words == ["ephemeral"])
        #expect(!model.canUndoRemoval)
        #expect(WordStore(directoryURL: directory).words == ["ephemeral"])
    }

    @Test func reportedPhraseUsesRealOfflineEntryAndPreservesOldCollection() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        try store.add("stick")
        let translator = ControlledTranslator()
        let model = AppModel(store: store, translator: translator)
        model.lookup("stick with")
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        if case .found(let entry) = model.lookupState {
            #expect(entry.word == "stick with")
            #expect(entry.definitions.contains { $0.text.contains("继续做") })
        }
        #expect(translator.requests.isEmpty)
        model.saveCurrentWord()
        #expect(model.words == ["stick with", "stick"])
        #expect(WordStore(directoryURL: directory).words == ["stick with", "stick"])
    }

    @Test func sentenceCanBeCollectedWhileTranslatingAndKeepsItsOriginalContent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let translator = ControlledTranslator()
        let model = AppModel(store: WordStore(directoryURL: directory), dictionary: MissingDictionary(), translator: translator)
        let source = "The API is idempotent, so retry the request."
        model.lookup(source)
        #expect(await waitFor { translator.isPending(source) })
        #expect(model.canSaveCurrentWord)
        model.saveCurrentWord()
        #expect(model.words == [source])
        translator.finish(source, translated: "该 API 是幂等的，因此可以重试请求。")
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        if case .found(let entry) = model.lookupState {
            #expect(entry.word == source)
            #expect(entry.definitions.first?.text == "该 API 是幂等的，因此可以重试请求。")
        }
        let disk = try Data(contentsOf: model.store.fileURL)
        #expect(try JSONDecoder().decode([String].self, from: disk) == [source])
        #expect(!String(decoding: disk, as: UTF8.self).contains("该 API"))
        #expect(model.currentWordIsSaved)
    }

    @Test func failedTranslationStillAllowsOriginalCollectionAndShowsSetupAction() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let translator = ControlledTranslator()
        let model = AppModel(store: WordStore(directoryURL: directory), dictionary: MissingDictionary(), translator: translator)
        let source = "Keep the original text, please!"
        model.lookup(source)
        #expect(await waitFor { translator.isPending(source) })
        translator.fail(source, error: .needsLanguages)
        #expect(await waitFor { model.translationSetupRequired })
        #expect(model.canSaveCurrentWord)
        model.saveCurrentWord()
        #expect(model.words == [source])
    }

    @Test func olderTranslationCannotReplaceNewerSelection() async {
        let translator = ControlledTranslator()
        let model = AppModel(store: WordStore(directoryURL: temporaryDirectory()), dictionary: MissingDictionary(), translator: translator)
        let first = "The first sentence."
        let latest = "The second sentence!"
        model.lookup(first)
        #expect(await waitFor { translator.isPending(first) })
        model.lookup(latest)
        #expect(await waitFor { translator.isPending(latest) })
        translator.finish(latest, translated: "第二个句子！")
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        translator.finish(first, translated: "第一个句子。")
        await Task.yield()
        if case .found(let entry) = model.lookupState {
            #expect(entry.word == latest)
            #expect(entry.definitions.first?.text == "第二个句子！")
        } else { Issue.record("The latest translation should remain visible") }
    }

    @Test func languageSetupRetriesThePendingSentenceWithoutAutoCollectingIt() async {
        let translator = SetupTranslator()
        let model = AppModel(store: WordStore(directoryURL: temporaryDirectory()), dictionary: MissingDictionary(), translator: translator)
        var notebookOpened = false
        var popupReopened = false
        model.onShowNotebook = { notebookOpened = true }
        model.onShowCurrentLookup = { popupReopened = true }
        model.lookup("Please keep reading.")
        #expect(await waitFor { model.translationSetupRequired })
        model.prepareTranslation()
        #expect(await waitFor { if case .found = model.lookupState { return true }; return false })
        #expect(notebookOpened && popupReopened && translator.prepared)
        #expect(!model.isPreparingTranslation)
        #expect(!model.translationSetupRequired)
        #expect(model.words.isEmpty)
    }

    @Test func overlongSelectionIsExplicitlyRejectedWithoutTruncationOrStaleSave() {
        let model = AppModel(store: WordStore(directoryURL: temporaryDirectory()))
        model.lookup(String(repeating: "x", count: SelectionText.maximumLength + 1))
        #expect(model.lookupWord == nil)
        #expect(!model.canSaveCurrentWord)
        #expect(model.query.count == SelectionText.maximumLength + 1)
        if case .failed(let message) = model.lookupState { #expect(message.contains("4000")) }
        else { Issue.record("An overlong selection should report a useful error") }
    }

    @Test func cancelledLanguageSetupExplainsRecoveryWithoutInternalErrorNames() async {
        let model = AppModel(store: WordStore(directoryURL: temporaryDirectory()), dictionary: MissingDictionary(), translator: CancelledSetupTranslator())
        model.lookup("Keep reading this sentence.")
        #expect(await waitFor { model.translationSetupRequired })
        model.prepareTranslation()
        #expect(await waitFor { !model.isPreparingTranslation })
        #expect(model.notice?.contains("取消") == true)
        #expect(model.notice?.contains("CancellationError") == false)
        #expect(model.canSaveCurrentWord)
    }
}
