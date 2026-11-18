import Foundation
import NaturalLanguage
import WordShelfCore

struct LearningLexicalEvidence: Equatable, Sendable {
    let chineseMeaning: String
    let bncRank: Int?
    // ECDICT calls this its contemporary-corpus rank. Do not display it as a
    // measured personal frequency or as a live COCA query.
    let cocaRank: Int?
    let isWholeEntryRank: Bool
    let englishMeaning: String

    init(chineseMeaning: String = "", bncRank: Int? = nil, cocaRank: Int? = nil,
         isWholeEntryRank: Bool = true, englishMeaning: String = "") {
        self.chineseMeaning = chineseMeaning
        self.bncRank = bncRank.flatMap { $0 > 0 ? $0 : nil }
        self.cocaRank = cocaRank.flatMap { $0 > 0 ? $0 : nil }
        self.isWholeEntryRank = isWholeEntryRank
        self.englishMeaning = englishMeaning
    }
}

struct LearningRecommendation: Equatable, Sendable {
    let purpose: LearningPurpose
    let priority: Int
    let reason: String
    let matchedScenario: String?
    let frequencyDescription: String
    let confidenceDescription: String

    init(purpose: LearningPurpose = .reference, priority: Int = 10, reason: String = "",
         matchedScenario: String? = nil, frequencyDescription: String = "词频未知",
         confidenceDescription: String = "场景证据不足") {
        self.purpose = purpose
        self.priority = max(0, min(priority, 100))
        self.reason = reason
        self.matchedScenario = matchedScenario
        self.frequencyDescription = frequencyDescription
        self.confidenceDescription = confidenceDescription
    }
}

struct LearningFeedbackSample: Equatable, Sendable {
    let word: String
    let purpose: LearningPurpose
    let evidence: LearningLexicalEvidence?

    init(word: String, purpose: LearningPurpose, evidence: LearningLexicalEvidence? = nil) {
        self.word = word
        self.purpose = purpose
        self.evidence = evidence
    }
}

@MainActor
protocol LearningRecommending {
    func updateFeedback(_ samples: [LearningFeedbackSample]) async
    func recommend(word: String, profile: LearningProfile, record: LearningRecord?,
                   evidence: LearningLexicalEvidence?) async -> LearningRecommendation
}

extension LearningRecommending {
    func updateFeedback(_ samples: [LearningFeedbackSample]) async {}
}

/// Ranks explicit personal tasks, lexical evidence and optional installed local
/// embeddings. This is a conservative recommendation, not an LLM assessment of
/// the user's profession, mastery or future behaviour.
@MainActor
final class LearningRecommendationService: LearningRecommending {
    private let worker: RecommendationWorker

    init(usesSemanticModels: Bool = true) {
        worker = RecommendationWorker(usesSemanticModels: usesSemanticModels)
    }

    func updateFeedback(_ samples: [LearningFeedbackSample]) async {
        await worker.updateFeedback(samples)
    }

    func recommend(word: String, profile: LearningProfile, record: LearningRecord?,
                   evidence: LearningLexicalEvidence?) async -> LearningRecommendation {
        await worker.recommend(word: word, profile: profile, record: record, evidence: evidence)
    }
}

private actor RecommendationWorker {
    private let usesSemanticModels: Bool
    private var englishEmbedding: NLEmbedding?
    private var chineseEmbedding: NLEmbedding?
    private var prepared = false
    private var feedback: [FeedbackItem] = []

    init(usesSemanticModels: Bool) { self.usesSemanticModels = usesSemanticModels }

    private struct FeedbackItem {
        let word: String
        let purpose: LearningPurpose
        let target: Target
    }

    func updateFeedback(_ samples: [LearningFeedbackSample]) {
        feedback = samples.prefix(50).compactMap { sample in
            guard SelectionText.normalize(sample.word) != nil else { return nil }
            return FeedbackItem(word: sample.word, purpose: sample.purpose,
                                target: Target(word: sample.word, evidence: sample.evidence))
        }
    }

    private func prepareModels() {
        guard !prepared else { return }
        prepared = true
        guard usesSemanticModels else { return }
        // These APIs return nil when the model is absent. They do not ask for a
        // download, Apple Intelligence activation, account or network service.
        englishEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        chineseEmbedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
    }

    func recommend(word: String, profile: LearningProfile, record: LearningRecord?,
                   evidence: LearningLexicalEvidence?) -> LearningRecommendation {
        let base = baseRecommendation(word: word, profile: profile, record: record, evidence: evidence)
        guard profile.isConfigured, record?.overridePurpose == nil, !feedback.isEmpty else { return base }
        let target = Target(word: word, evidence: evidence)
        var adjustment = 0
        var matches = 0
        for sample in feedback {
            guard SelectionText.dictionaryKey(sample.word) != SelectionText.dictionaryKey(word),
                  clearlySimilar(target, to: sample.target) else { continue }
            switch sample.purpose {
            case .use: adjustment += 8
            case .understand: break
            case .reference: adjustment -= 12
            }
            matches += 1
            if matches >= 3 { break }
        }
        adjustment = max(-12, min(12, adjustment))
        guard adjustment != 0 else { return base }
        return LearningRecommendation(purpose: base.purpose, priority: base.priority + adjustment,
            reason: base.reason + "参考你对相近内容的反馈，调整学习顺序。",
            matchedScenario: base.matchedScenario, frequencyDescription: base.frequencyDescription,
            confidenceDescription: base.confidenceDescription)
    }

    private func clearlySimilar(_ target: Target, to other: Target) -> Bool {
        let shared = target.tokens.intersection(other.tokens)
        let chineseMatch = shared.contains { hasChinese($0) && $0.count >= 2 }
        if chineseMatch || shared.count >= 2 { return true }
        // Only strong installed-model matches can affect another entry. Domain
        // membership or a nearby frequency rank is insufficient.
        let description = other.english.isEmpty ? other.chinese : other.english
        guard !description.isEmpty else { return false }
        let scenario = Scenario(text: description, isWork: false, isGoal: false)
        return (semanticMatch(target: target, scenario: scenario) ?? 0) >= 0.76
    }

    private func baseRecommendation(word: String, profile: LearningProfile, record: LearningRecord?,
                                    evidence: LearningLexicalEvidence?) -> LearningRecommendation {
        let frequency = frequencyDescription(evidence)
        let rank = evidence.flatMap { value -> Int? in
            guard value.isWholeEntryRank else { return nil }
            return [value.bncRank, value.cocaRank].compactMap { $0 }.min()
        }
        let repeatedDays = Set(record?.encounterDates ?? []).count
        if let manual = record?.overridePurpose {
            return LearningRecommendation(purpose: manual,
                priority: manual == .reference ? 5 : manual == .use ? 88 : 53,
                reason: manual == .reference ? "按你的反馈，近期先不投入学习；保留原文供查询。"
                    : manual == .use ? "按你的反馈，优先练到能主动说写；后续复习按作答表现安排。"
                    : "按你的反馈，以再次遇到时能理解为目标。",
                frequencyDescription: frequency, confidenceDescription: "你的选择优先")
        }
        guard profile.isConfigured else {
            return LearningRecommendation(reason: "先选择常见工作或生活场景，系统才能判断哪些表达与你相关。",
                frequencyDescription: frequency, confidenceDescription: "等待场景资料")
        }
        prepareModels()
        let scenarios = profile.workScenarios.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Scenario(text: $0, isWork: true, isGoal: false) }
            + profile.lifeScenarios.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Scenario(text: $0, isWork: false, isGoal: false) }
            + profile.expressionGoals.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Scenario(text: $0, isWork: false, isGoal: true) }
        let target = Target(word: word, evidence: evidence)
        let candidates = scenarios.map { scenario in
            match(target: target, scenario: scenario, workDomain: profile.workDomain)
        }
        func precedes(_ lhs: Match, _ rhs: Match) -> Bool {
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.scenario.isGoal != rhs.scenario.isGoal { return !lhs.scenario.isGoal }
            let leftOutput = purpose(for: lhs.scenario) == .use
            let rightOutput = purpose(for: rhs.scenario) == .use
            if leftOutput != rightOutput { return !leftOutput }
            let leftCadence = scenarioFrequencyBoost(lhs.scenario.text)
            let rightCadence = scenarioFrequencyBoost(rhs.scenario.text)
            if leftCadence != rightCadence { return leftCadence < rightCadence }
            // A final literal order makes the observable recommendation stable
            // when users select the same scenarios in a different order.
            return lhs.scenario.text > rhs.scenario.text
        }
        // Actual word-level use needs are a separate gate from topic relevance.
        // A high domain score, cadence, corpus rank, repeated lookups or nearby
        // feedback cannot supply that missing evidence.
        let actualUse = candidates.filter {
            $0.score >= 0.70 && purpose(for: $0.scenario) == .use && $0.outputNeed != nil
        }.max(by: precedes)
        let best = actualUse ?? candidates.max(by: precedes)
        if let best, best.score >= 0.70 {
            let wantsOutput = purpose(for: best.scenario) == .use
            let purpose: LearningPurpose = wantsOutput && best.outputNeed != nil ? .use : .understand
            let frequencyBoost = rank.map { $0 <= 3_000 ? 6 : $0 <= 10_000 ? 3 : 0 } ?? 0
            let repetitionBoost = min(max(repeatedDays - 1, 0) * 2, 6)
            let taskFrequencyBoost = scenarioFrequencyBoost(best.scenario.text)
            let priority = (purpose == .use ? 69 : 55) + Int((best.score - 0.70) * 30)
                + frequencyBoost + repetitionBoost + taskFrequencyBoost
            let explanation: String
            let action: String
            if purpose == .use {
                explanation = best.outputNeed ?? best.explanation
                action = "有具体说写用途，适合练习从意图想出英文。"
            } else if wantsOutput {
                explanation = best.domainRelated ? "与你的专业领域或主题相关。" : best.explanation
                action = "尚未找到这个表达的具体说写需求，先以理解为目标。"
            } else {
                explanation = best.explanation
                action = "该场景侧重阅读或听懂，先练到能理解。"
            }
            return LearningRecommendation(purpose: purpose, priority: priority,
                reason: "\(explanation)\(action)" + recurrenceNote(repeatedDays),
                matchedScenario: best.scenario.text, frequencyDescription: frequency,
                confidenceDescription: best.kind)
        }
        if let best, best.score >= 0.50 {
            return LearningRecommendation(purpose: .understand, priority: 43 + min(repeatedDays, 5),
                reason: "与该场景可能相关，但输出用途证据还不充分，先以理解为主。" + recurrenceNote(repeatedDays),
                matchedScenario: best.scenario.text, frequencyDescription: frequency,
                confidenceDescription: best.kind + " · 待校准")
        }
        if repeatedDays >= 3 {
            return LearningRecommendation(purpose: .understand, priority: 43,
                reason: "你在 \(repeatedDays) 个不同日期主动查询过它，建议先练到再次遇见时能理解；尚未匹配到明确输出场景。",
                frequencyDescription: frequency, confidenceDescription: "主动查词信号")
        }
        if let rank, rank <= 5_000 {
            return LearningRecommendation(purpose: .understand, priority: 40,
                reason: "该词条在通用语料排名较靠前；尚未匹配到你的具体说写任务，先以理解为主。",
                frequencyDescription: frequency, confidenceDescription: "通用语料参考")
        }
        return LearningRecommendation(purpose: .reference, priority: 15,
            reason: rank == nil
                ? "尚未匹配到具体使用场景，词频也未知；先保留参考，之后可随需求调整。"
                : "尚未匹配到你的具体使用场景，先保留参考，暂不安排复习。",
            frequencyDescription: frequency,
            confidenceDescription: englishEmbedding == nil && chineseEmbedding == nil ? "词法规则 · 本机语义模型不可用" : "场景证据不足")
    }

    private func recurrenceNote(_ days: Int) -> String {
        days > 1 ? "你已在 \(days) 个不同日期主动查询。" : ""
    }

    private func frequencyDescription(_ evidence: LearningLexicalEvidence?) -> String {
        guard let evidence else { return "词频未知" }
        guard evidence.isWholeEntryRank else { return "整段频率未知；未用组成词排名推算" }
        let parts = [evidence.bncRank.map { "BNC 第 \($0) 位" },
                     evidence.cocaRank.map { "ECDICT 当代语料第 \($0) 位" }].compactMap { $0 }
        return parts.isEmpty ? "词频未知" : parts.joined(separator: " · ")
    }

    private struct Scenario {
        let text: String
        let isWork: Bool
        let isGoal: Bool

        /// Structured options put the user's learning objective before the
        /// actual task. That metadata controls the goal, but must not become
        /// evidence that every scenario is relevant to words such as "learn".
        var matchingText: String {
            let content = text.replacingOccurrences(of: "^\\s*学习目标\\s*[:：]\\s*(?:希望会用|看懂即可)[。.]?\\s*",
                                                    with: "", options: .regularExpression)
            guard content != text else { return text }
            let task = content.replacingOccurrences(of: "^\\s*(?:工作|生活)场景\\s*[:：]\\s*", with: "", options: .regularExpression)
            // The options catalog wraps its topic in a channel-specific
            // sentence. Match the topic, not shared UI metadata such as 场景,
            // 学习 or 练习; channel/goal/cadence are handled separately.
            let templates = [
                "^(?:每天|每周|偶尔|近期)?就(.+)与他人交流，练习口头表达。$",
                "^(?:每天|每周|偶尔|近期)?围绕(.+)撰写消息或文字，练习书面表达。$",
                "^(?:每天|每周|偶尔|近期)?围绕(.+)与他人沟通，练习口头和书面表达。$",
                "^(?:每天|每周|偶尔|近期)?阅读或听懂有关(.+)的内容，以理解为目标。$"
            ]
            for pattern in templates {
                guard let expression = try? NSRegularExpression(pattern: pattern),
                      let match = expression.firstMatch(in: task, range: NSRange(task.startIndex..., in: task)),
                      let range = Range(match.range(at: 1), in: task) else { continue }
                return String(task[range])
            }
            return task.replacingOccurrences(of: "(?:工作领域|生活领域|领域|任务|话题|实际通道|通道|使用频率|频率)\\s*[:：]",
                                            with: "", options: .regularExpression)
        }
    }

    private struct Target {
        let word: String
        let chinese: String
        let english: String
        let tokens: Set<String>

        init(word: String, evidence: LearningLexicalEvidence?) {
            self.word = word
            chinese = evidence?.chineseMeaning ?? ""
            english = evidence?.englishMeaning ?? ""
            tokens = RecommendationWorker.tokens(word + " " + chinese + " " + english)
        }
    }

    private struct Match {
        let scenario: Scenario
        var score: Double
        var explanation: String
        var kind: String
        var outputNeed: String?
        var domainRelated = false
    }

    private func match(target: Target, scenario: Scenario, workDomain: String) -> Match {
        let raw = scenario.matchingText.lowercased()
        var result = Match(scenario: scenario, score: 0, explanation: "", kind: "词法匹配")
        if containsWholeExpression(target.word, in: scenario.matchingText) {
            result.score = 0.96
            result.explanation = scenario.isGoal ? "与你明确想表达的内容直接匹配。" : "该场景中直接出现了这段英文。"
            result.outputNeed = scenario.isGoal ? "你明确希望用这段原文表达意思。" : "这段原文直接出现在你的具体说写任务中。"
            return result
        }
        let shared = target.tokens.intersection(Self.tokens(scenario.matchingText))
        if !shared.isEmpty {
            let strongestLength = shared.map(\.count).max() ?? 0
            result.score = shared.count > 1 ? 0.91 : strongestLength >= 3 ? 0.85 : 0.76
            result.explanation = scenario.isGoal ? "词条含义与你想表达的内容有直接用词匹配。" : "词条含义与该场景的关键词匹配。"
            let concrete = shared.subtracting(Self.broadTopicTokens)
            if !concrete.isEmpty {
                let anchors = concrete.sorted().prefix(3).joined(separator: "、")
                result.outputNeed = "词条的具体含义“\(anchors)”与你的说写任务匹配。"
            }
        }
        // Rare short Chinese concepts can be split into single characters by
        // NLTokenizer. Match complete dictionary concepts as well, without a
        // per-headword exception or treating generic descriptions as concepts.
        let concepts = concreteChineseConcepts(in: target.chinese, mentionedIn: scenario.matchingText)
        if !concepts.isEmpty {
            let anchors = concepts.sorted().prefix(2).joined(separator: "、")
            result.outputNeed = "你的说写任务明确涉及词典中的具体概念“\(anchors)”。"
            if result.score < 0.85 {
                result.score = 0.85
                result.explanation = "词典中的具体概念与你的任务直接匹配。"
                result.kind = "具体概念匹配"
            }
        }
        let domain = domainMatch(target: target, scene: scenario.matchingText, workDomain: scenario.isWork ? workDomain : "")
        result.domainRelated = domain > 0
        if domain > result.score {
            result.score = domain
            result.explanation = "词条的领域或用途线索与该场景相关。"
            result.kind = "领域规则估计"
        }
        if let semantic = semanticMatch(target: target, scenario: scenario), semantic > result.score {
            result.score = semantic
            result.explanation = "本机语义模型估计词条含义与该场景相关。"
            result.kind = "本机语义估计"
            // For specialist terms, semantic proximity to a broad professional
            // task still establishes only subject relevance. A concrete concept
            // or original expression must establish the output need separately.
            if semantic >= 0.70, domain == 0, !hasSpecialistMarker(target) {
                result.outputNeed = "本机语义模型估计该表达与你的具体说写意图匹配。"
            }
        }
        // A work-domain match requires a work task. It is never transferred to
        // unrelated life scenes, and it never claims a word frequency.
        if result.score == 0 && raw.contains(target.word.lowercased()) && target.word.count > 2 {
            result.score = 0.45
        }
        return result
    }

    private func semanticMatch(target: Target, scenario: Scenario) -> Double? {
        // A short dictionary headword is not a sentence embedding. On the
        // installed models, such comparisons were often driven by length or
        // generic wording. Only use sufficiently descriptive texts, and compare
        // against unrelated anchors to reject that generic similarity.
        let scene = scenario.matchingText
        if hasChinese(scene), hasChinese(target.chinese), target.chinese.count >= 12,
           let model = chineseEmbedding {
            let meaning = String(target.chinese.prefix(600))
            let distance = model.distance(between: meaning, and: scene)
            let anchor = ["阅读自然科学文章，了解海洋动物的生活。", "与朋友讨论音乐、饮食和周末活动。", "办理旅行预订，询问交通和住宿。"]
                .map { model.distance(between: meaning, and: $0) }.min() ?? 0
            if distance.isFinite, distance < 0.32, anchor - distance >= 0.07 { return 0.76 }
            if distance.isFinite, distance < 0.40, anchor - distance >= 0.09 { return 0.57 }
        }
        if !hasChinese(scene), let model = englishEmbedding {
            let description = target.english.isEmpty ? target.word : target.word + ". " + target.english
            guard Self.englishTokenCount(description) >= 7, Self.englishTokenCount(scene) >= 5 else { return nil }
            let text = String(description.prefix(900))
            let distance = model.distance(between: text, and: scene)
            let anchor = ["Read articles about marine animals and scientific discoveries.", "Discuss music, food, hobbies and weekend activities with friends.", "Book travel accommodation and ask about transport and hotel reservations."]
                .map { model.distance(between: text, and: $0) }.min() ?? 0
            if distance.isFinite, distance < 0.93, anchor - distance >= 0.08 { return 0.78 }
            if distance.isFinite, distance < 1.02, anchor - distance >= 0.18 { return 0.76 }
            if distance.isFinite, distance < 1.04, anchor - distance >= 0.10 { return 0.58 }
        }
        return nil
    }

    private func containsWholeExpression(_ expression: String, in scene: String) -> Bool {
        let cleaned = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: cleaned)
        return scene.range(of: "(?<![\\p{Latin}0-9])" + escaped + "(?![\\p{Latin}0-9])",
                           options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func explicitPurpose(in scenario: String) -> LearningPurpose? {
        guard let range = scenario.range(of: "^\\s*学习目标\\s*[:：]\\s*(希望会用|看懂即可)[。.]?",
                                         options: .regularExpression) else { return nil }
        return scenario[range].contains("希望会用") ? .use : .understand
    }

    private func purpose(for scenario: Scenario) -> LearningPurpose {
        explicitPurpose(in: scenario.text)
            ?? (scenario.isGoal || isOutputScenario(scenario.text) ? .use : .understand)
    }

    private func isOutputScenario(_ scenario: String) -> Bool {
        if let explicit = explicitPurpose(in: scenario) { return explicit == .use }
        let scene = scenario.lowercased()
        let inputOnly = ["只需看懂", "只需要看懂", "看懂即可", "只需读懂", "只需要读懂", "只阅读", "只需阅读", "只需要阅读", "仅阅读", "仅需理解", "不用自己说", "不需要自己表达", "不需要说", "不需要写", "不需要自己说", "不需要自己写", "不需要自己解释", "不需要自己介绍", "read only", "reading only", "only read", "only need to read", "only need to understand"]
        // Remove negated output actions before deciding. This preserves mixed
        // intent, e.g. “不需要说，主要写邮件” is still productive practice.
        let chinesePositive = scene.replacingOccurrences(
            of: "(?:不需要|无需|不用|不必)(?:自己)?(?:说(?:或写|和写)?|写(?:或说|和说)?|口头表达|表达|解释|介绍)",
            with: "", options: .regularExpression)
        let positive = chinesePositive.replacingOccurrences(
            of: "(?:do not|don't|does not|doesn't|no need to|not required to|do not need to|don't need to)\\s+(?:speak|write|explain|present|talk|discuss)(?:\\s+it)?",
            with: "", options: .regularExpression)
        let output = ["说", "写", "沟通", "交流", "解释", "讨论", "汇报", "表达", "询问", "聊天", "建议", "介绍", "办理", "预订", "投诉", "speak", "write", "explain", "discuss", "present", "report", "ask", "talk", "chat", "negotiate", "book", "order", "describe", "summarize", "respond", "reply"]
        if containsAny(positive, output) { return true }
        if positive != scene { return false }
        if containsAny(scene, inputOnly) { return false }
        let input = ["读", "听", "阅读", "看懂", "听懂", "理解", "文档", "论文", "read", "listen", "understand", "documentation", "paper"]
        if containsAny(positive, input) { return false }
        return true // The user's stated default objective is productive use.
    }

    private func scenarioFrequencyBoost(_ text: String) -> Int {
        let scene = text.lowercased()
        if containsAny(scene, ["下周", "下个月", "即将", "近期", "马上", "next week", "next month", "upcoming", "tomorrow"]) { return 4 }
        if containsAny(scene, ["每天", "每日", "经常", "daily", "every day", "frequently", "often"]) { return 5 }
        if containsAny(scene, ["每周", "每星期", "weekly", "every week"]) { return 3 }
        return 0
    }

    private struct DomainRule {
        let markers: [String]
        let vocabulary: [String]
        let scenes: [String]
    }

    private func hasSpecialistMarker(_ target: Target) -> Bool {
        domains.contains { domain in
            domain.markers.contains { target.chinese.contains($0) || target.english.contains($0) }
        }
    }

    private func concreteChineseConcepts(in meaning: String, mentionedIn scene: String) -> Set<String> {
        guard let expression = try? NSRegularExpression(pattern: "[\\p{Han}]{2,}") else { return [] }
        let generic = Self.broadTopicTokens.union(Self.stopWords).union(["一种", "用于", "具有", "有关", "以及", "不同"])
            .filter { hasChinese($0) && $0.count >= 2 }.sorted { $0.count > $1.count }
        return Set(expression.matches(in: meaning, range: NSRange(meaning.startIndex..., in: meaning)).compactMap { match in
            guard let range = Range(match.range, in: meaning) else { return nil }
            let concept = String(meaning[range])
            guard concept.count <= 20, scene.contains(concept) else { return nil }
            var remainder = concept
            for token in generic { remainder = remainder.replacingOccurrences(of: token, with: "") }
            guard remainder.unicodeScalars.filter({ (0x3400...0x9fff).contains($0.value) }).count >= 2 else { return nil }
            return concept
        })
    }

    /// Shared industry labels and generic task words are evidence of subject
    /// relevance, not evidence that this particular term is needed in speech.
    /// This filters evidence tokens; it does not blacklist any headwords.
    private static let broadTopicTokens: Set<String> = [
        "软件", "技术", "科技", "计算机", "电脑", "医学", "医疗", "法律", "金融", "财务", "会计", "化学", "专业", "领域", "行业", "工作", "系统", "问题", "方法", "操作", "处理", "内容", "信息", "数据", "产品", "服务", "功能", "方案", "原因", "影响", "流程", "过程", "方式", "情况", "相关", "检查", "治疗", "临床", "患者", "病人", "实验", "风险",
        "software", "technical", "technology", "computer", "computing", "medical", "medicine", "legal", "law", "finance", "financial", "accounting", "chemical", "chemistry", "professional", "field", "domain", "industry", "work", "business", "system", "problem", "issue", "method", "process", "operation", "information", "data", "product", "service", "function", "solution", "cause", "reason", "effect", "procedure", "content", "way", "treatment", "clinical", "patient", "examination", "experiment", "risk"
    ]

    private let domains: [DomainRule] = [
        DomainRule(markers: ["[计]", "[计 ", "[计算机]"],
            vocabulary: ["api", "software", "database", "compiler", "cache", "debug", "server", "request", "transaction", "interface", "algorithm", "retry", "程序", "软件", "编译", "缓存", "数据库", "接口", "算法", "服务器"],
            scenes: ["编程", "软件", "接口", "数据库", "api", "software", "programming", "developer", "coding", "database"]),
        DomainRule(markers: ["[医]", "[解]", "[生理]"],
            vocabulary: ["medical", "patient", "diagnosis", "treatment", "clinical", "symptom", "病人", "诊断", "治疗", "临床", "医学"],
            scenes: ["医疗", "医学", "医生", "护理", "患者", "病人", "medical", "medicine", "patient", "nursing", "clinical"]),
        DomainRule(markers: ["[法]"],
            vocabulary: ["legal", "law", "contract", "litigation", "lawsuit", "法律", "合同", "诉讼", "条款"],
            scenes: ["法律", "法务", "合同", "律师", "合规", "legal", "law", "contract", "compliance"]),
        DomainRule(markers: ["[经]", "[会计]"],
            vocabulary: ["financial", "accounting", "invoice", "revenue", "investment", "budget", "会计", "财务", "发票", "收入", "投资", "预算"],
            scenes: ["财务", "金融", "会计", "预算", "投资", "报表", "finance", "accounting", "financial", "investment", "budget"]),
        DomainRule(markers: ["[化]", "[化学]"],
            vocabulary: ["chemical", "molecule", "reagent", "reaction", "化学", "分子", "试剂", "化合物"],
            scenes: ["化学", "化工", "实验", "chemistry", "chemical", "laboratory", "experiment"]),
        DomainRule(markers: [],
            vocabulary: ["reservation", "airport", "flight", "boarding", "passport", "luggage", "酒店", "预订", "机场", "航班", "登机", "护照", "行李"],
            scenes: ["旅行", "旅游", "出国", "酒店", "住宿", "航班", "登机", "travel", "trip", "hotel", "airport", "flight", "reservation"]),
        DomainRule(markers: [],
            vocabulary: ["deadline", "progress", "schedule", "feedback", "proposal", "clarify", "remind", "negotiate", "进度", "截止", "期限", "日程", "反馈", "方案", "澄清", "提醒", "协商"],
            scenes: ["进度", "项目", "邮件", "方案", "协作", "沟通", "同事", "客户", "progress", "project", "email", "colleague", "client", "proposal", "meeting"])
    ]

    private func domainMatch(target: Target, scene: String, workDomain: String) -> Double {
        let meaning = (target.word + " " + target.chinese + " " + target.english).lowercased()
        var result = 0.0
        for domain in domains {
            let fieldMatch = containsAny(workDomain.lowercased(), domain.scenes)
            // “Technical/技术” alone does not imply software development.
            // It strengthens a task only after the user supplied its field.
            let taskMatch = containsAny(scene.lowercased(), domain.scenes)
                || (fieldMatch && containsAny(scene.lowercased(), ["技术", "technical"]))
            guard taskMatch || fieldMatch else { continue }
            if domain.markers.contains(where: { target.chinese.contains($0) || target.english.contains($0) }) {
                result = max(result, taskMatch ? 0.82 : 0.62)
            } else if containsAny(meaning, domain.vocabulary) {
                result = max(result, taskMatch ? 0.74 : 0.56)
            }
        }
        return result
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { term in
            if !hasChinese(term) {
                let pattern = "(?<![a-z])" + NSRegularExpression.escapedPattern(for: term) + "(?![a-z])"
                return text.range(of: pattern, options: .regularExpression) != nil
            }
            return text.contains(term)
        }
    }

    private func hasChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
    }

    private static func englishTokenCount(_ text: String) -> Int {
        text.split { !$0.isLetter }.filter { $0.unicodeScalars.allSatisfy { $0.value < 128 } }.count
    }

    private static let stopWords: Set<String> = [
        "the", "a", "an", "to", "of", "and", "or", "in", "on", "at", "for", "with", "from", "by", "as", "be", "is", "are", "was", "were", "this", "that", "it", "its", "my", "our", "your", "their", "i", "we", "they", "you", "have", "has", "had", "can", "could", "would", "should", "do", "does", "did", "not", "no", "some", "any", "than", "then", "when", "where", "which", "what", "who", "how", "such", "one", "two", "other", "use", "used", "using", "english", "word", "words", "every", "daily", "weekly", "week", "month", "often", "want", "need",
        "工作", "生活", "英语", "英文", "每周", "每天", "希望", "需要", "能够", "可以", "想要", "自己", "相关", "一个", "一些", "经常", "时候", "内容", "事情", "对方", "其他", "为了", "进行", "方面"
    ]

    private static func tokens(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set<String>()
        // NLTokenizer segments Chinese compounds instead of matching arbitrary
        // shared single characters such as 生/工/用.
        for language in [NLLanguage.english, .simplifiedChinese] {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.setLanguage(language)
            tokenizer.string = lower
            tokenizer.enumerateTokens(in: lower.startIndex..<lower.endIndex) { range, _ in
                let token = String(lower[range])
                if token.count >= 2, !stopWords.contains(token), token.rangeOfCharacter(from: .letters) != nil {
                    tokens.insert(token)
                }
                return true
            }
        }
        // Lemmas join ordinary inflections (requests/request, explaining/explain)
        // without rewriting the stored original or claiming a word-family rank.
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = lower
        tagger.enumerateTags(in: lower.startIndex..<lower.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let token = tag?.rawValue.lowercased() ?? String(lower[range])
            if token.count >= 2, !stopWords.contains(token) { tokens.insert(token) }
            return true
        }
        return tokens
    }
}
