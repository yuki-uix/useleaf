import Combine
import Foundation
import WordShelfCore

@MainActor
final class LearningModel: ObservableObject {
    @Published private(set) var profile: LearningProfile
    @Published private(set) var recommendations: [String: LearningRecommendation] = [:]
    @Published private(set) var isAnalyzing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var reviewWords: [String] = []
    @Published private(set) var reviewIndex = 0
    @Published private(set) var reviewRevealed = false
    @Published var reviewAnswer = ""
    @Published private(set) var reviewPrompt = ""
    @Published private(set) var reviewReference = ""
    @Published private(set) var reviewIsLoading = false
    @Published private(set) var reviewLoadError: String?
    @Published private(set) var reviewCompleted = 0

    let store: LearningStore
    private let dictionary: any DictionaryLookingUp
    private let translator: any TextTranslating
    private let recommender: any LearningRecommending
    private let evidenceProvider: any VocabularyEvidenceProviding
    private let now: () -> Date
    private var words: [String] = []
    private var evidenceCache: [String: VocabularyEvidence] = [:]
    private var analysisTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var analysisID = UUID()
    private var reviewID = UUID()
    private var referenceMeaning = ""
    private var clockTimer: Timer?

    init(store: LearningStore, dictionary: any DictionaryLookingUp = DictionaryService(),
         translator: any TextTranslating, recommender: (any LearningRecommending)? = nil,
         evidenceProvider: any VocabularyEvidenceProviding = VocabularyEvidenceService(),
         now: @escaping () -> Date = Date.init) {
        self.store = store
        profile = store.profile
        errorMessage = store.loadError
        self.dictionary = dictionary
        self.translator = translator
        self.recommender = recommender ?? LearningRecommendationService()
        self.evidenceProvider = evidenceProvider
        self.now = now
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }
    }

    isolated deinit {
        clockTimer?.invalidate()
        analysisTask?.cancel()
        reviewTask?.cancel()
    }

    var eligibleCount: Int { eligibleWords.count }
    var dueCount: Int { dueWords.count }
    var nextDueDate: Date? {
        eligibleWords.compactMap { progress(for: $0)?.dueAt }.filter { $0 > now() }.min()
    }
    var currentReviewWord: String? { reviewWords.indices.contains(reviewIndex) ? reviewWords[reviewIndex] : nil }
    var currentReviewRecommendation: LearningRecommendation? { currentReviewWord.flatMap { recommendations[$0] } }
    var currentReviewPurpose: LearningPurpose? { currentReviewRecommendation?.purpose }
    var reviewFinished: Bool { !reviewWords.isEmpty && reviewIndex >= reviewWords.count }

    func syncCollection(_ currentWords: [String]) {
        guard currentWords != words else { return }
        words = currentWords
        let currentSet = Set(currentWords)
        recommendations = recommendations.filter { currentSet.contains($0.key) }
        evidenceCache = evidenceCache.filter { currentSet.contains($0.key) }
        if let current = currentReviewWord, !currentSet.contains(current) { endReview() }
        refreshRecommendations()
    }

    @discardableResult
    func saveProfile(_ value: LearningProfile) -> Bool {
        do {
            try store.saveProfile(value)
            profile = store.profile
            errorMessage = nil
            endReview()
            refreshRecommendations()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setPurpose(_ purpose: LearningPurpose?, for word: String) {
        guard words.contains(word) else { return }
        do {
            try store.setPurpose(purpose, for: word)
            errorMessage = nil
            if currentReviewWord == word { endReview() }
            refreshRecommendations()
        } catch { errorMessage = error.localizedDescription }
    }

    func noteEncounter(_ word: String) {
        // Keep only dates for explicitly collected originals. A transient lookup
        // is not written into a separate query-history database.
        guard let identity = SelectionText.identity(word),
              let saved = words.first(where: { SelectionText.identity($0) == identity }) else { return }
        do {
            let before = store.record(for: saved)?.encounterDates
            try store.recordEncounter(saved, at: now())
            if before != store.record(for: saved)?.encounterDates { refreshRecommendations() }
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshRecommendations() {
        analysisTask?.cancel()
        analysisID = UUID()
        let id = analysisID
        let snapshot = words
        let profile = self.profile
        let records = snapshot.map { store.record(for: $0) }
        isAnalyzing = !snapshot.isEmpty
        analysisTask = Task { [weak self, recommender, evidenceProvider, translator] in
            var lexicalByWord: [String: LearningLexicalEvidence] = [:]
            for word in snapshot {
                guard !Task.isCancelled, let self, self.analysisID == id else { return }
                var evidence: VocabularyEvidence?
                if let cached = self.evidenceCache[word] { evidence = cached }
                else {
                    evidence = await evidenceProvider.evidence(for: word)
                    guard !Task.isCancelled, self.analysisID == id else { return }
                    if let evidence { self.evidenceCache[word] = evidence }
                }
                let needsChinese = ([profile.workDomain] + profile.workScenarios + profile.lifeScenarios + profile.expressionGoals)
                    .contains { $0.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) } }
                if profile.isConfigured, needsChinese, evidence?.chineseMeaning.isEmpty != false {
                    // Installed-language translation provides temporary meaning
                    // for unlisted phrases/sentences. No frequency is inferred,
                    // no language download is triggered, and no translation is persisted.
                    if let translated = try? await translator.translate(word),
                       !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        guard !Task.isCancelled, self.analysisID == id else { return }
                        evidence = VocabularyEvidence(chineseMeaning: translated,
                                                      englishMeaning: evidence?.englishMeaning ?? "",
                                                      bncRank: evidence?.bncRank, contemporaryRank: evidence?.contemporaryRank)
                        self.evidenceCache[word] = evidence
                    }
                    guard !Task.isCancelled, self.analysisID == id else { return }
                }
                let lexical = evidence.map {
                    LearningLexicalEvidence(chineseMeaning: $0.chineseMeaning,
                                            bncRank: $0.bncRank, cocaRank: $0.contemporaryRank, isWholeEntryRank: true,
                                            englishMeaning: $0.englishMeaning)
                }
                lexicalByWord[word] = lexical
            }
            let feedback = snapshot.enumerated().compactMap { index, word -> LearningFeedbackSample? in
                guard let purpose = records[index]?.overridePurpose else { return nil }
                return LearningFeedbackSample(word: word, purpose: purpose, evidence: lexicalByWord[word])
            }
            await recommender.updateFeedback(feedback)
            for (index, word) in snapshot.enumerated() {
                guard !Task.isCancelled, let self, self.analysisID == id else { return }
                let recommendation = await recommender.recommend(word: word, profile: profile, record: records[index], evidence: lexicalByWord[word])
                guard !Task.isCancelled, self.analysisID == id else { return }
                self.recommendations[word] = recommendation
            }
            guard let self, !Task.isCancelled, self.analysisID == id else { return }
            self.isAnalyzing = false
        }
    }

    private var eligibleWords: [String] {
        words.filter { word in
            guard let recommendation = recommendations[word] else { return false }
            return recommendation.purpose != .reference
        }
    }

    private var dueWords: [String] {
        eligibleWords.filter { word in
            (progress(for: word)?.dueAt ?? .distantPast) <= now()
        }.sorted { lhs, rhs in
            // Due reviews precede new material so new collections cannot keep
            // pushing previously scheduled practice out of a bounded session.
            let leftDate = progress(for: lhs)?.dueAt ?? .distantFuture
            let rightDate = progress(for: rhs)?.dueAt ?? .distantFuture
            // Among new entries, prioritize relevance instead of collection order.
            if leftDate != rightDate { return leftDate < rightDate }
            let leftPriority = recommendations[lhs]?.priority ?? 0
            let rightPriority = recommendations[rhs]?.priority ?? 0
            if leftPriority != rightPriority { return leftPriority > rightPriority }
            return (words.firstIndex(of: lhs) ?? 0) < (words.firstIndex(of: rhs) ?? 0)
        }
    }

    private func progress(for word: String) -> LearningProgress? {
        guard let record = store.record(for: word), record.reviewedPurpose == recommendations[word]?.purpose else { return nil }
        return record.progress
    }

    func startReview() {
        guard !isAnalyzing else { return }
        endReview()
        reviewWords = Array(dueWords.prefix(10))
        reviewIndex = 0
        reviewCompleted = 0
        if currentReviewWord != nil { loadReview() }
    }

    func revealReview() {
        guard currentReviewWord != nil, !reviewIsLoading, reviewLoadError == nil else { return }
        reviewRevealed = true
        updateReference()
    }

    func rateReview(_ rating: ReviewRating) {
        guard let word = currentReviewWord, words.contains(word), reviewRevealed, !reviewIsLoading, reviewLoadError == nil else { return }
        guard recommendations[word]?.purpose != .reference else { endReview(); return }
        do {
            try store.rate(word, rating: rating, purpose: currentReviewPurpose, at: now())
            errorMessage = nil
            reviewCompleted += 1
            reviewIndex += 1
            reviewAnswer = ""
            reviewRevealed = false
            reviewReference = ""
            reviewPrompt = ""
            if currentReviewWord != nil { loadReview() }
        } catch { errorMessage = error.localizedDescription }
    }

    func skipReview() {
        guard currentReviewWord != nil else { return }
        reviewTask?.cancel()
        reviewID = UUID()
        reviewIndex += 1
        reviewAnswer = ""
        reviewRevealed = false
        reviewReference = ""
        reviewPrompt = ""
        reviewIsLoading = false
        reviewLoadError = nil
        if currentReviewWord != nil { loadReview() }
    }

    func retryReview() {
        guard currentReviewWord != nil, !reviewIsLoading else { return }
        loadReview()
    }

    func endReview() {
        reviewTask?.cancel()
        reviewID = UUID()
        reviewWords = []
        reviewIndex = 0
        reviewCompleted = 0
        reviewRevealed = false
        reviewIsLoading = false
        reviewLoadError = nil
        reviewAnswer = ""
        reviewPrompt = ""
        reviewReference = ""
        referenceMeaning = ""
    }

    private func loadReview() {
        reviewTask?.cancel()
        reviewID = UUID()
        let id = reviewID
        guard let word = currentReviewWord else { return }
        reviewRevealed = false
        reviewIsLoading = true
        reviewLoadError = nil
        referenceMeaning = ""
        reviewTask = Task { [weak self, dictionary, translator, evidenceProvider] in
            var meaning: String
            var failure: String?
            var usedTranslation = false
            do {
                let entry = try await dictionary.lookup(word)
                meaning = entry.definitions.map(\.text).joined(separator: "\n")
            } catch {
                guard !Task.isCancelled else { return }
                do { meaning = try await translator.translate(word); usedTranslation = true }
                catch { meaning = ""; failure = error.localizedDescription }
            }
            if usedTranslation, failure == nil {
                let hints = await LearningTermHints.find(in: word, using: evidenceProvider)
                guard !Task.isCancelled else { return }
                if !hints.isEmpty {
                    let glossary = hints.map { "\($0.word)：\($0.meaning)" }.joined(separator: "\n")
                    meaning = "词典术语提示（部分）：\n\(glossary)\n\n本机句译（供参考）：\n\(meaning)"
                }
            }
            guard let self, !Task.isCancelled, self.reviewID == id, self.currentReviewWord == word else { return }
            self.referenceMeaning = meaning
            if let failure {
                self.reviewLoadError = "暂未取得回忆提示：\(failure)"
                self.reviewPrompt = "可以重试或跳过本条；提示准备好前不会记录学习表现。"
                self.reviewIsLoading = false
                return
            }
            guard !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.reviewLoadError = "暂未得到可用的释义，可以重试或跳过本条。"
                self.reviewPrompt = "提示准备好前不会记录学习表现。"
                self.reviewIsLoading = false
                return
            }
            let recommendation = self.recommendations[word]
            let scenario = recommendation?.matchedScenario ?? (self.profile.workScenarios + self.profile.lifeScenarios).first
            if recommendation?.purpose == .use {
                let hint = self.promptHint(meaning, hiding: word)
                let scene = scenario.map { "\n联系你的场景：\(self.hide(word, in: $0))" } ?? ""
                let previousReviews = self.progress(for: word)?.reviews ?? 0
                let tasks = ["先用英文说出来，或写一句能用于实际沟通的话。",
                             "换成你最近遇到的一个实际例子，用英文组织一句话。",
                             "设想对方问你原因，用这个表达说明或补充你的意思。",
                             "换一个主语或时间，尝试用这个表达重新组织一句话。"]
                self.reviewPrompt = "\(tasks[previousReviews % tasks.count])\n含义提示（结合场景选择合适义项）：\(hint)\(scene)\n尝试想起本次目标表达，再查看参考。"
            } else {
                self.reviewPrompt = "先回忆这段原文的含义。可以说出来，也可以用中文简短写下理解，然后查看参考。"
            }
            self.reviewIsLoading = false
        }
    }

    private func updateReference() {
        guard let word = currentReviewWord else { return }
        if currentReviewPurpose == .use {
            let answer = reviewAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            let note: String
            if answer.isEmpty { note = "对照原文和释义，检查刚才口头表达的意思、搭配与语气，再评估是否需要提示。" }
            else if answer.range(of: word, options: .caseInsensitive) != nil {
                note = "你的回答包含目标原文。请继续对照释义检查意思、搭配和语气；包含目标表达并不等于用法一定正确。"
            } else {
                note = "你的回答可以有其他合理表达。请对照本次原文，检查能否用它表达刚才的意思。"
            }
            reviewReference = "\(word)\n\n\(referenceMeaning)\n\n\(note)\n本轮采用对照参考自评，不自动判定语法或表达正确性。"
        } else { reviewReference = "\(word)\n\n\(referenceMeaning)\n\n对照参考，评估自己刚才能否独立理解。" }
    }

    private func promptHint(_ meaning: String, hiding word: String) -> String {
        // Preserve several senses instead of forcing a noun's first definition
        // onto a productive verb task (e.g. address / address an issue).
        let cueMeaning = meaning.components(separatedBy: "\n\n本机句译（供参考）：").first ?? meaning
        let senses = cueMeaning.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { String($0.prefix(150)) }
        return hide(word, in: senses.joined(separator: "\n"))
    }

    private func hide(_ word: String, in text: String) -> String {
        let pattern = "(?i)(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z])"
        return text.replacingOccurrences(of: pattern, with: "目标表达", options: .regularExpression)
    }
}
