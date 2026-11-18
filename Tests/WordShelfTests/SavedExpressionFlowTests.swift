import AppKit
import Foundation
import Testing
@testable import WordShelf
import WordShelfCore

private actor FinderFixtureDictionary: DictionaryLookingUp {
    let definitions: [String: String]
    let cancels: Bool
    private(set) var requests: [String] = []

    init(definitions: [String: String] = [:], cancels: Bool = false) {
        self.definitions = definitions
        self.cancels = cancels
    }

    func lookup(_ word: String) async throws -> DictionaryEntry {
        requests.append(word)
        if cancels { throw CancellationError() }
        guard let meaning = definitions[word] else { throw DictionaryError.notFound(word) }
        return DictionaryEntry(word: word, definitions: [DictionaryDefinition(text: meaning)], sourceName: "Fixture")
    }
}

@MainActor
private final class FinderFixtureTranslator: TextTranslating {
    let translation: String
    private(set) var requests: [String] = []

    init(translation: String = "本机临时译文") { self.translation = translation }

    func translate(_ text: String) async throws -> String {
        requests.append(text)
        return translation
    }

    func prepareLanguages() async throws {}
}

@MainActor
private func finderWaitFor(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if condition() { return true }
        await Task.yield()
    }
    return false
}

@Suite("Lightweight saved expression flow")
@MainActor
struct SavedExpressionFlowTests {
    private func store(_ originals: [String]) throws -> WordStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Useleaf-finder-tests-\(UUID().uuidString)", isDirectory: true)
        let store = WordStore(directoryURL: directory)
        for original in originals.reversed() { try store.add(original) }
        return store
    }

    @Test func inlineDefinitionLeavesTheLookupAndUsageFilesUntouched() async throws {
        let saved = "stick with"
        let store = try store([saved])
        let directory = store.fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let learningStore = LearningStore(directoryURL: directory)
        try learningStore.recordEncounter(saved, at: Date(timeIntervalSince1970: 1_600_000_000))
        let dictionary = FinderFixtureDictionary(definitions: [saved: "继续采用", "current": "当前的"])
        let translator = FinderFixtureTranslator()
        let app = AppModel(store: store, dictionary: dictionary, translator: translator)
        defer { app.cancelLookup() }
        app.lookup("current")
        #expect(await finderWaitFor { if case .found = app.lookupState { return true }; return false })
        app.notice = "已有提示"
        app.captureMessage = "已有划词提示"
        let originalState = app.lookupState
        let beforeWords = try Data(contentsOf: store.fileURL)
        let beforeLearning = try Data(contentsOf: learningStore.fileURL)
        let beforeRecords = app.learning.store.records

        let result = try await app.savedDefinition(for: saved)

        #expect(result.word == saved)
        #expect(result.definitions.first?.text == "继续采用")
        #expect(app.query == "current")
        #expect(app.lookupWord == "current")
        #expect(app.lookupState == originalState)
        #expect(app.notice == "已有提示")
        #expect(app.captureMessage == "已有划词提示")
        #expect(app.learning.store.records == beforeRecords)
        #expect(try Data(contentsOf: store.fileURL) == beforeWords)
        #expect(try Data(contentsOf: learningStore.fileURL) == beforeLearning)
        #expect(translator.requests.isEmpty)
    }

    @Test func untranslatedOriginalUsesTemporaryTranslationWithoutAddingMetadataOrEncounters() async throws {
        let original = "Could you clarify this?\nI mean the deployment."
        let store = try store([original])
        let directory = store.fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = FinderFixtureDictionary()
        let translator = FinderFixtureTranslator(translation: "能解释一下吗？我是指部署。")
        let app = AppModel(store: store, dictionary: dictionary, translator: translator)
        let beforeWords = try Data(contentsOf: store.fileURL)
        let learningURL = app.learning.store.fileURL
        let beforeLearning = try? Data(contentsOf: learningURL)

        let entry = try await app.savedDefinition(for: original)

        #expect(entry.word == original)
        #expect(entry.definitions.first?.text == "能解释一下吗？我是指部署。")
        #expect(await dictionary.requests == [original])
        #expect(translator.requests == [original])
        #expect(app.query.isEmpty)
        #expect(app.lookupWord == nil)
        #expect(app.lookupState == .idle)
        #expect(app.learning.store.record(for: original) == nil)
        #expect(try Data(contentsOf: store.fileURL) == beforeWords)
        #expect((try? Data(contentsOf: learningURL)) == beforeLearning)
        #expect(try JSONDecoder().decode([String].self, from: beforeWords) == [original])
    }

    @Test func unsavedAndRemovedOriginalsAreRejectedBeforeLookupOrTranslation() async throws {
        let original = "stick with"
        let store = try store([original])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let dictionary = FinderFixtureDictionary()
        let translator = FinderFixtureTranslator()
        let app = AppModel(store: store, dictionary: dictionary, translator: translator)

        await #expect(throws: (any Error).self) { try await app.savedDefinition(for: "not collected") }
        app.removeWord(original)
        await #expect(throws: (any Error).self) { try await app.savedDefinition(for: original) }

        #expect(await dictionary.requests.isEmpty)
        #expect(translator.requests.isEmpty)
        #expect(app.query.isEmpty)
        #expect(app.lookupState == .idle)
    }

    @Test func dictionaryCancellationDoesNotStartFallbackTranslation() async throws {
        let original = "stick with"
        let store = try store([original])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let translator = FinderFixtureTranslator()
        let app = AppModel(store: store, dictionary: FinderFixtureDictionary(cancels: true), translator: translator)

        await #expect(throws: CancellationError.self) { try await app.savedDefinition(for: original) }

        #expect(translator.requests.isEmpty)
        #expect(app.lookupState == .idle)
        #expect(app.learning.store.record(for: original) == nil)
    }

    @Test func emptyTranslationIsNotReturnedAsASuccessfulDefinition() async throws {
        let original = "A sentence missing from the dictionary."
        let store = try store([original])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let app = AppModel(store: store, dictionary: FinderFixtureDictionary(),
                           translator: FinderFixtureTranslator(translation: " \n\t "))

        await #expect(throws: (any Error).self) { try await app.savedDefinition(for: original) }

        #expect(app.lookupState == .idle)
        #expect(app.words == [original])
    }

    @Test(arguments: ["Resilient", "stick with", "Could you clarify this?\nI mean the deployment."])
    func copyingUsesTheExactOriginalAndLeavesLookupAndSavedFilesUntouched(original: String) throws {
        let store = try store([original])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let app = AppModel(store: store, dictionary: FinderFixtureDictionary())
        let pasteboard = NSPasteboard(name: .init("Useleaf-copy-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("Existing clipboard", forType: .string))
        let binaryType = NSPasteboard.PasteboardType("com.useleaf.tests.binary")
        #expect(pasteboard.setData(Data([0, 1, 2]), forType: binaryType))
        #expect(pasteboard.setData(Data("{\\rtf1 Existing clipboard}".utf8), forType: .rtf))
        let beforeWords = try Data(contentsOf: store.fileURL)
        let beforeLearning = try? Data(contentsOf: app.learning.store.fileURL)
        app.query = "Keep my current lookup text."

        #expect(app.copySavedOriginal(original, to: pasteboard))

        #expect(pasteboard.string(forType: .string) == original)
        let copiedTypes = pasteboard.types ?? []
        #expect(copiedTypes.contains(.string))
        #expect(!copiedTypes.contains(binaryType))
        #expect(!copiedTypes.contains(.rtf))
        // macOS may advertise its legacy plain-text alias alongside .string.
        let legacyString = NSPasteboard.PasteboardType("NSStringPboardType")
        if copiedTypes.contains(legacyString) {
            #expect(pasteboard.string(forType: legacyString) == original)
        }
        #expect(app.query == "Keep my current lookup text.")
        #expect(app.lookupWord == nil)
        #expect(app.lookupState == .idle)
        #expect(app.learning.store.record(for: original) == nil)
        #expect(try Data(contentsOf: store.fileURL) == beforeWords)
        #expect((try? Data(contentsOf: app.learning.store.fileURL)) == beforeLearning)
    }

    @Test func rejectingUnsavedOrRemovedCopyKeepsTheExistingClipboardIntact() throws {
        let original = "stick with"
        let store = try store([original])
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let app = AppModel(store: store, dictionary: FinderFixtureDictionary())
        let pasteboard = NSPasteboard(name: .init("Useleaf-copy-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let binaryType = NSPasteboard.PasteboardType("com.useleaf.tests.binary")
        pasteboard.clearContents()
        #expect(pasteboard.setString("Keep this clipboard", forType: .string))
        #expect(pasteboard.setData(Data([7, 8, 9]), forType: binaryType))
        let beforeChange = pasteboard.changeCount

        #expect(!app.copySavedOriginal("not collected", to: pasteboard))
        app.removeWord(original)
        #expect(!app.copySavedOriginal(original, to: pasteboard))

        #expect(pasteboard.changeCount == beforeChange)
        #expect(pasteboard.string(forType: .string) == "Keep this clipboard")
        #expect(pasteboard.data(forType: binaryType) == Data([7, 8, 9]))
        #expect(app.query.isEmpty)
        #expect(app.lookupState == .idle)
    }
}
