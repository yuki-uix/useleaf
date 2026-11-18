import Foundation
import Testing
@testable import WordShelf
import WordShelfCore

private actor LearningFixtureDictionary: DictionaryLookingUp {
    private let meanings: [String: String]
    private(set) var requests: [String] = []

    init(meanings: [String: String] = [:]) { self.meanings = meanings }

    func lookup(_ word: String) async throws -> DictionaryEntry {
        requests.append(word)
        guard let meaning = meanings[word] else { throw DictionaryError.notFound(word) }
        return DictionaryEntry(word: word, definitions: [DictionaryDefinition(text: meaning)], sourceName: "Fixture")
    }
}

private actor LearningFixtureEvidence: VocabularyEvidenceProviding {
    private(set) var requests: [String] = []
    private let value: VocabularyEvidence?

    init(value: VocabularyEvidence? = VocabularyEvidence(chineseMeaning: "场景词义", bncRank: 321)) {
        self.value = value
    }

    func evidence(for input: String) async -> VocabularyEvidence? {
        requests.append(input)
        return value
    }
}

@MainActor
private final class LearningFixtureTranslator: TextTranslating {
    private(set) var requests: [String] = []
    var failure: TranslationServiceError?
    var translation = "请继续当前方案，周五再检查。"
    func translate(_ text: String) async throws -> String {
        requests.append(text)
        if let failure { throw failure }
        return translation
    }
    func prepareLanguages() async throws {}
}

@MainActor
private final class LearningSilentPronunciation: Pronouncing {
    var isSpeaking = false
    var onSpeakingChanged: ((Bool) -> Void)?
    func speak(_ text: String, accent: PronunciationAccent) throws { isSpeaking = true }
    func stop() { isSpeaking = false; onSpeakingChanged?(false) }
}

@MainActor
private final class LearningFixtureClock {
    var date = Date(timeIntervalSince1970: 1_795_000_000)
}

@MainActor
private final class LearningFixtureRecommender: LearningRecommending {
    struct Request {
        let word: String
        let profile: LearningProfile
        let evidence: LearningLexicalEvidence?
    }
    var results: [String: LearningRecommendation]
    var heldDomains: Set<String> = []
    private(set) var requests: [Request] = []
    private var pending: [String: [(CheckedContinuation<LearningRecommendation, Never>, LearningRecommendation)]] = [:]

    init(_ results: [String: LearningRecommendation] = [:]) { self.results = results }

    func recommend(word: String, profile: LearningProfile, record: LearningRecord?,
                   evidence: LearningLexicalEvidence?) async -> LearningRecommendation {
        requests.append(Request(word: word, profile: profile, evidence: evidence))
        let base = results[word] ?? LearningRecommendation()
        let result = LearningRecommendation(purpose: record?.overridePurpose ?? base.purpose,
            priority: base.priority, reason: "画像：\(profile.workDomain)",
            matchedScenario: base.matchedScenario ?? profile.workScenarios.first,
            frequencyDescription: base.frequencyDescription, confidenceDescription: "Fixture")
        guard heldDomains.contains(profile.workDomain) else { return result }
        return await withCheckedContinuation { pending[profile.workDomain, default: []].append(($0, result)) }
    }

    func pendingCount(_ domain: String) -> Int { pending[domain]?.count ?? 0 }
    func finish(_ domain: String) {
        let values = pending.removeValue(forKey: domain) ?? []
        values.forEach { $0.0.resume(returning: $0.1) }
    }
    func finishAll() { Array(pending.keys).forEach(finish) }
}

@Suite("Learning collection and practice flow")
@MainActor
struct LearningModelTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WordShelf-learning-model-\(UUID().uuidString)")
    }

    private func waitFor(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<3000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    private func model(store: LearningStore, recommender: LearningFixtureRecommender,
                       dictionary: LearningFixtureDictionary = LearningFixtureDictionary(),
                       evidence: LearningFixtureEvidence = LearningFixtureEvidence(),
                       clock: LearningFixtureClock? = nil) -> LearningModel {
        let clock = clock ?? LearningFixtureClock()
        return LearningModel(store: store, dictionary: dictionary, translator: LearningFixtureTranslator(),
                      recommender: recommender, evidenceProvider: evidence, now: { clock.date })
    }

    @Test func recommendationsAndEncountersOnlyUseCollectedOriginalsAndDistinctDays() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let clock = LearningFixtureClock()
        let recommender = LearningFixtureRecommender(["Cache": LearningRecommendation(purpose: .understand, priority: 40)])
        let evidence = LearningFixtureEvidence()
        let learning = model(store: store, recommender: recommender, evidence: evidence, clock: clock)
        learning.syncCollection(["Cache", "stick with"])
        #expect(await waitFor { !learning.isAnalyzing && learning.recommendations["Cache"] != nil })
        #expect(Set(learning.recommendations.keys) == ["Cache", "stick with"])
        #expect(await evidence.requests == ["Cache", "stick with"])
        #expect(recommender.requests.first?.evidence?.bncRank == 321)

        learning.noteEncounter("never collected")
        learning.noteEncounter("Stick with") // Phrase identity retains original casing.
        learning.setPurpose(.use, for: "never collected")
        #expect(store.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))

        learning.noteEncounter("cache")
        let firstFile = try Data(contentsOf: store.fileURL)
        let firstDates = try #require(store.record(for: "Cache")?.encounterDates)
        learning.noteEncounter("CACHE")
        clock.date.addTimeInterval(60)
        learning.noteEncounter("Cache")
        #expect(store.record(for: "Cache")?.encounterDates == firstDates)
        #expect(try Data(contentsOf: store.fileURL) == firstFile)
        clock.date.addTimeInterval(86_400)
        learning.noteEncounter("cAcHe")
        #expect(store.record(for: "Cache")?.encounterDates.count == 2)
        #expect(LearningStore(directoryURL: folder).record(for: "Cache")?.encounterDates.count == 2)
        #expect(store.record(for: "stick with") == nil)
    }

    @Test func savingAProfileRecomputesAndAnOlderAsyncResultCannotOverwriteIt() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let old = LearningProfile(workDomain: "旧领域", workScenarios: ["阅读项目资料"])
        let new = LearningProfile(workDomain: "新领域", workScenarios: ["向同事解释方案"])
        try store.saveProfile(old)
        let recommender = LearningFixtureRecommender(["proposal": LearningRecommendation(purpose: .use, priority: 80)])
        recommender.heldDomains = [old.workDomain, new.workDomain]
        defer { recommender.finishAll() }
        let learning = model(store: store, recommender: recommender)
        learning.syncCollection(["proposal"])
        #expect(await waitFor { recommender.pendingCount(old.workDomain) == 1 })
        #expect(learning.saveProfile(new))
        #expect(await waitFor { recommender.pendingCount(new.workDomain) == 1 })
        recommender.finish(new.workDomain)
        #expect(await waitFor { !learning.isAnalyzing && learning.recommendations["proposal"]?.reason == "画像：新领域" })
        recommender.finish(old.workDomain)
        for _ in 0..<50 { await Task.yield() }
        #expect(learning.profile == new)
        #expect(learning.recommendations["proposal"]?.reason == "画像：新领域")
        #expect(LearningStore(directoryURL: folder).profile == new)
        #expect(learning.currentReviewWord == nil)
    }

    @Test func unlistedExpressionsUseTemporaryChineseEvidenceWithoutPersistingTranslationsOrInventingFrequency() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "I see where you're coming from."
        let words = WordStore(directoryURL: folder)
        try words.add(original)
        let originalFile = try Data(contentsOf: words.fileURL)
        let store = LearningStore(directoryURL: folder)
        try store.saveProfile(LearningProfile(workScenarios: ["每周与同事交流方案，表达理解对方想法"]))
        let learningFile = try Data(contentsOf: store.fileURL)
        let translator = LearningFixtureTranslator()
        translator.translation = "我能理解你的立场。"
        let evidence = LearningFixtureEvidence(value: nil)
        let recommender = LearningFixtureRecommender([original: LearningRecommendation(purpose: .use, priority: 80)])
        let learning = LearningModel(store: store, dictionary: LearningFixtureDictionary(), translator: translator,
                                     recommender: recommender, evidenceProvider: evidence)
        learning.syncCollection(words.words)
        #expect(await waitFor { !learning.isAnalyzing && learning.recommendations[original] != nil })
        #expect(await evidence.requests == [original])
        #expect(translator.requests == [original])
        let lexical = try #require(recommender.requests.first?.evidence)
        #expect(lexical.chineseMeaning == translator.translation)
        #expect(lexical.bncRank == nil)
        #expect(lexical.cocaRank == nil)
        #expect(learning.recommendations[original]?.purpose == .use)
        #expect(try Data(contentsOf: words.fileURL) == originalFile)
        #expect(try Data(contentsOf: store.fileURL) == learningFile)
        #expect(!String(decoding: learningFile, as: UTF8.self).contains(translator.translation))
        #expect(store.records.isEmpty)

        learning.refreshRecommendations()
        #expect(await waitFor { !learning.isAnalyzing && recommender.requests.count == 2 })
        #expect(translator.requests.count == 1) // Reuse is in memory, not in words.json or learning.json.
        #expect(WordStore(directoryURL: folder).words == [original])
        #expect(LearningStore(directoryURL: folder).records.isEmpty)
    }

    @Test func productiveHintsPreserveMultipleSensesWhileHidingTheOriginalUntilReveal() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let dictionary = LearningFixtureDictionary(meanings: [
            "address": "n. 住址 address\nvt. 处理问题，Address concerns\n[计] 地址"
        ])
        let recommender = LearningFixtureRecommender([
            "address": LearningRecommendation(purpose: .use, priority: 80,
                matchedScenario: "每周向同事解释如何 address an issue")
        ])
        let learning = model(store: store, recommender: recommender, dictionary: dictionary)
        learning.syncCollection(["address"])
        #expect(await waitFor { !learning.isAnalyzing })
        learning.startReview()
        #expect(await waitFor { !learning.reviewIsLoading })
        #expect(learning.currentReviewPurpose == .use)
        #expect(learning.reviewPrompt.contains("n. 住址"))
        #expect(learning.reviewPrompt.contains("vt. 处理问题"))
        #expect(learning.reviewPrompt.contains("[计] 地址"))
        #expect(learning.reviewPrompt.contains("结合场景选择合适义项"))
        #expect(learning.reviewPrompt.range(of: "address", options: .caseInsensitive) == nil)
        #expect(learning.reviewReference.isEmpty)
        #expect(!learning.reviewRevealed)
        learning.revealReview()
        #expect(learning.reviewReference.contains("address"))
        #expect(learning.reviewReference.contains("Address concerns"))
        #expect(learning.reviewReference.contains("n. 住址"))
        #expect(learning.reviewReference.contains("vt. 处理问题"))
        #expect(store.records.isEmpty)
    }

    @Test func duePracticePrecedesNewEntriesThenNewEntriesUsePriorityAndReferencesStayOut() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let clock = LearningFixtureClock()
        try store.rate("early", rating: .good, purpose: .use, at: clock.date.addingTimeInterval(-3 * 86_400))
        try store.rate("late", rating: .good, purpose: .use, at: clock.date.addingTimeInterval(-2 * 86_400))
        try store.rate("future", rating: .good, purpose: .use, at: clock.date)
        let recommender = LearningFixtureRecommender([
            "early": LearningRecommendation(purpose: .use, priority: 20),
            "late": LearningRecommendation(purpose: .use, priority: 99),
            "future": LearningRecommendation(purpose: .use, priority: 100),
            "new low": LearningRecommendation(purpose: .understand, priority: 30),
            "new high": LearningRecommendation(purpose: .use, priority: 90),
            "reference": LearningRecommendation(purpose: .reference, priority: 100)
        ])
        let learning = model(store: store, recommender: recommender, clock: clock)
        learning.syncCollection(["reference", "new low", "future", "late", "new high", "early"])
        #expect(await waitFor { !learning.isAnalyzing })
        #expect(learning.eligibleCount == 5)
        #expect(learning.dueCount == 4)
        #expect(learning.nextDueDate == clock.date.addingTimeInterval(86_400))
        learning.startReview()
        #expect(learning.reviewWords == ["early", "late", "new high", "new low"])
        learning.endReview()
        clock.date.addTimeInterval(86_401)
        #expect(learning.dueCount == 5)
    }

    @Test func productivePracticeHidesTheTargetAndRequiresRevealBeforeRatingWhileSkipWritesNothing() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let clock = LearningFixtureClock()
        let dictionary = LearningFixtureDictionary(meanings: ["stick with": "继续采用 Stick With；坚持", "cache": "缓存"])
        let recommender = LearningFixtureRecommender([
            "stick with": LearningRecommendation(purpose: .use, priority: 90, matchedScenario: "工作中希望能说 stick with this plan"),
            "cache": LearningRecommendation(purpose: .understand, priority: 50)
        ])
        let learning = model(store: store, recommender: recommender, dictionary: dictionary, clock: clock)
        learning.syncCollection(["cache", "stick with"])
        #expect(await waitFor { !learning.isAnalyzing })
        learning.startReview()
        #expect(await waitFor { !learning.reviewIsLoading })
        #expect(learning.currentReviewWord == "stick with")
        #expect(learning.currentReviewPurpose == .use)
        #expect(learning.reviewPrompt.contains("用英文"))
        #expect(learning.reviewPrompt.range(of: "stick with", options: .caseInsensitive) == nil)
        #expect(learning.reviewReference.isEmpty)
        learning.reviewAnswer = "Let's stick with the current plan."
        learning.rateReview(.good)
        #expect(learning.reviewIndex == 0)
        #expect(store.record(for: "stick with")?.progress == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))

        learning.revealReview()
        #expect(learning.reviewRevealed)
        #expect(learning.reviewReference.contains("stick with"))
        #expect(learning.reviewReference.contains("不自动判定"))
        learning.rateReview(.good)
        #expect(await waitFor { !learning.reviewIsLoading && learning.currentReviewWord == "cache" })
        #expect(learning.reviewCompleted == 1)
        #expect(learning.currentReviewPurpose == .understand)
        #expect(learning.reviewPrompt.contains("回忆"))
        #expect(!learning.reviewPrompt.contains("缓存"))
        #expect(learning.reviewAnswer.isEmpty)
        #expect(!learning.reviewRevealed)
        #expect(learning.reviewReference.isEmpty)
        let completedRecord = try #require(store.record(for: "stick with"))
        #expect(completedRecord.reviewedPurpose == .use)
        #expect(completedRecord.progress?.lastReviewedAt == clock.date)
        #expect(completedRecord.progress?.dueAt == clock.date.addingTimeInterval(86_400))
        let beforeSkip = try Data(contentsOf: store.fileURL)
        learning.skipReview()
        #expect(learning.reviewFinished)
        #expect(learning.reviewCompleted == 1)
        #expect(store.record(for: "cache")?.progress == nil)
        #expect(try Data(contentsOf: store.fileURL) == beforeSkip)
        #expect(LearningStore(directoryURL: folder).record(for: "stick with") == completedRecord)
    }

    @Test func failedProgressWriteKeepsTheCurrentAnswerAndDoesNotAdvanceTheSession() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let recommender = LearningFixtureRecommender(["proposal": LearningRecommendation(purpose: .use, priority: 80)])
        let learning = model(store: store, recommender: recommender,
                             dictionary: LearningFixtureDictionary(meanings: ["proposal": "提议，方案"]))
        learning.syncCollection(["proposal"])
        #expect(await waitFor { !learning.isAnalyzing })
        learning.startReview()
        #expect(await waitFor { !learning.reviewIsLoading })
        learning.reviewAnswer = "I have a proposal."
        learning.revealReview()
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        learning.rateReview(.good)
        #expect(learning.errorMessage != nil)
        #expect(learning.currentReviewWord == "proposal")
        #expect(learning.reviewIndex == 0)
        #expect(learning.reviewCompleted == 0)
        #expect(learning.reviewRevealed)
        #expect(learning.reviewAnswer == "I have a proposal.")
        #expect(store.record(for: "proposal")?.progress == nil)
        try FileManager.default.removeItem(at: store.fileURL)
        learning.rateReview(.good)
        #expect(learning.errorMessage == nil)
        #expect(learning.reviewFinished)
        #expect(learning.reviewCompleted == 1)
    }

    @Test func failedHintCannotBeRevealedOrRatedAndRetryRecoversAfterASkipWithoutFalseProgress() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let clock = LearningFixtureClock()
        let translator = LearningFixtureTranslator()
        translator.failure = .needsLanguages
        let recommender = LearningFixtureRecommender([
            "first phrase": LearningRecommendation(purpose: .use, priority: 90),
            "next phrase": LearningRecommendation(purpose: .use, priority: 80)
        ])
        let learning = LearningModel(store: store, dictionary: LearningFixtureDictionary(), translator: translator,
                                     recommender: recommender, evidenceProvider: LearningFixtureEvidence(), now: { clock.date })
        learning.syncCollection(["first phrase", "next phrase"])
        #expect(await waitFor { !learning.isAnalyzing })
        learning.startReview()
        #expect(await waitFor { !learning.reviewIsLoading && learning.reviewLoadError != nil })
        #expect(learning.currentReviewWord == "first phrase")
        #expect(learning.reviewLoadError?.contains("语言包") == true)
        #expect(learning.reviewPrompt.contains("不会记录"))
        learning.revealReview()
        learning.rateReview(.good)
        #expect(!learning.reviewRevealed)
        #expect(learning.reviewReference.isEmpty)
        #expect(learning.reviewIndex == 0)
        #expect(learning.reviewCompleted == 0)
        #expect(store.records.isEmpty)

        learning.skipReview()
        #expect(await waitFor { !learning.reviewIsLoading && learning.currentReviewWord == "next phrase" })
        #expect(learning.reviewLoadError != nil)
        #expect(learning.reviewCompleted == 0)
        #expect(store.record(for: "first phrase")?.progress == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))

        translator.failure = nil
        learning.retryReview()
        #expect(await waitFor { !learning.reviewIsLoading && learning.reviewLoadError == nil })
        #expect(learning.currentReviewWord == "next phrase")
        #expect(learning.reviewPrompt.contains("含义提示"))
        #expect(learning.reviewReference.isEmpty)
        learning.reviewAnswer = "My own English sentence."
        learning.revealReview()
        #expect(learning.reviewRevealed)
        #expect(learning.reviewReference.contains("next phrase"))
        #expect(learning.reviewReference.contains("请继续当前方案"))
        learning.rateReview(.good)
        #expect(learning.reviewFinished)
        #expect(learning.reviewCompleted == 1)
        #expect(store.record(for: "first phrase") == nil)
        #expect(store.record(for: "next phrase")?.progress?.reviews == 1)
        #expect(store.record(for: "next phrase")?.reviewedPurpose == .use)
        #expect(LearningStore(directoryURL: folder).record(for: "next phrase")?.progress?.lastReviewedAt == clock.date)
    }

    @Test func changingTheLearningPurposeRequiresNewPracticeWithoutThrowingAwayItsPreviousRecord() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directoryURL: folder)
        let clock = LearningFixtureClock()
        for days in [4, 3, 2, 1] {
            try store.rate("cache", rating: .good, purpose: .understand, at: clock.date.addingTimeInterval(Double(-days) * 86_400))
        }
        let oldProgress = try #require(store.record(for: "cache")?.progress)
        #expect(oldProgress.dueAt > clock.date)
        let recommender = LearningFixtureRecommender(["cache": LearningRecommendation(purpose: .understand, priority: 60)])
        let learning = model(store: store, recommender: recommender,
                             dictionary: LearningFixtureDictionary(meanings: ["cache": "缓存"]), clock: clock)
        learning.syncCollection(["cache"])
        #expect(await waitFor { !learning.isAnalyzing })
        #expect(learning.dueCount == 0)
        learning.setPurpose(.use, for: "cache")
        #expect(await waitFor { !learning.isAnalyzing && learning.recommendations["cache"]?.purpose == .use })
        #expect(store.record(for: "cache")?.progress == oldProgress)
        #expect(learning.dueCount == 1)
        learning.startReview()
        #expect(await waitFor { !learning.reviewIsLoading })
        learning.revealReview()
        learning.rateReview(.good)
        let newRecord = try #require(store.record(for: "cache"))
        #expect(newRecord.reviewedPurpose == .use)
        #expect(newRecord.progress?.reviews == 1)
        #expect(newRecord.progress?.intervalDays == 1)
        #expect(newRecord.progress?.dueAt == clock.date.addingTimeInterval(86_400))
        #expect(LearningStore(directoryURL: folder).record(for: "cache") == newRecord)
    }

    @Test func learningKeepsCollectedBytesAndLookupStateIntactWhileDeleteAndUndoSyncTheActiveReview() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let words = WordStore(directoryURL: folder)
        let original = "Please keep this plan.\nReview it on Friday!"
        try words.add("cache")
        try words.add(original)
        let originalFile = try Data(contentsOf: words.fileURL)
        let store = LearningStore(directoryURL: folder)
        let clock = LearningFixtureClock()
        try store.rate(original, rating: .good, purpose: .use, at: clock.date.addingTimeInterval(-2 * 86_400))
        let oldRecord = try #require(store.record(for: original))
        let dictionary = LearningFixtureDictionary(meanings: ["lookup": "查询原来的释义", "cache": "缓存"])
        let translator = LearningFixtureTranslator()
        let recommender = LearningFixtureRecommender([
            original: LearningRecommendation(purpose: .use, priority: 80),
            "cache": LearningRecommendation(purpose: .understand, priority: 50)
        ])
        let learning = LearningModel(store: store, dictionary: dictionary, translator: translator,
                                     recommender: recommender, evidenceProvider: LearningFixtureEvidence(), now: { clock.date })
        let app = AppModel(store: words, dictionary: dictionary, translator: translator,
                           pronunciation: LearningSilentPronunciation(), learning: learning)
        app.lookup("lookup")
        #expect(await waitFor { if case .found = app.lookupState { return true }; return false })
        #expect(await waitFor { !learning.isAnalyzing })
        let query = app.query
        let lookupWord = app.lookupWord
        let lookupState = app.lookupState
        learning.startReview()
        #expect(await waitFor { !learning.reviewIsLoading })
        #expect(learning.currentReviewWord == original)
        #expect(translator.requests == [original])
        #expect(learning.reviewPrompt.contains("请继续当前方案"))
        #expect(try Data(contentsOf: words.fileURL) == originalFile)
        #expect(app.query == query)
        #expect(app.lookupWord == lookupWord)
        #expect(app.lookupState == lookupState)

        app.removeWord(original)
        #expect(learning.currentReviewWord == nil)
        #expect(learning.reviewWords.isEmpty)
        #expect(store.record(for: original) == oldRecord)
        app.undoRemoval()
        #expect(await waitFor { !learning.isAnalyzing && learning.recommendations[original] != nil })
        #expect(app.words.contains(original))
        #expect(store.record(for: original) == oldRecord)
        #expect(app.query == query)
        #expect(app.lookupState == lookupState)
        #expect(WordStore(directoryURL: folder).words.contains(original))
    }
}
