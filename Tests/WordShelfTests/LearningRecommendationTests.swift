import Foundation
import NaturalLanguage
import Testing
@testable import WordShelf
import WordShelfCore

@Suite("Personal learning recommendations")
@MainActor
struct LearningRecommendationTests {
    private func service() -> LearningRecommendationService {
        LearningRecommendationService(usesSemanticModels: false)
    }

    @Test func noProfileDoesNotInventAProfessionOrEnrolACommonWord() async {
        let recommendation = await service().recommend(word: "project", profile: LearningProfile(), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 项目，计划", bncRank: 430, cocaRank: 275))
        #expect(recommendation.purpose == .reference)
        #expect(recommendation.reason.contains("选择"))
        #expect(recommendation.matchedScenario == nil)
        #expect(recommendation.confidenceDescription == "等待场景资料")
    }

    @Test func aSpecialistTermNeedsItsOwnUsageTaskBeforeProductivePractice() async {
        let evidence = LearningLexicalEvidence(chineseMeaning: "[计] 幂等", bncRank: 39_000, cocaRank: 46_000,
            englishMeaning: "An operation that produces the same result if it is performed more than once.")
        let read = LearningProfile(workDomain: "软件开发", workScenarios: ["每周阅读英文接口技术文档"])
        let broad = LearningProfile(workDomain: "软件开发", workScenarios: ["每周向同事解释接口重试和技术方案"])
        let explain = LearningProfile(workDomain: "软件开发", workScenarios: ["每周向同事解释幂等 idempotent 的概念与实际用法"])
        let first = await service().recommend(word: "idempotent", profile: read, record: nil, evidence: evidence)
        let domainOnly = await service().recommend(word: "idempotent", profile: broad, record: nil, evidence: evidence)
        let second = await service().recommend(word: "idempotent", profile: explain, record: nil, evidence: evidence)
        #expect(first.purpose == .understand)
        #expect(domainOnly.purpose == .understand)
        #expect(domainOnly.priority < 70)
        #expect(second.purpose == .use)
        #expect(second.priority >= 70)
        #expect(second.matchedScenario == explain.workScenarios.first)
        #expect(second.frequencyDescription.contains("39000"))
        #expect(!second.reason.contains("低频"))
    }

    @Test func chineseAndEnglishLifeTasksMatchRealDictionaryMeanings() async {
        let chinese = LearningProfile(lifeScenarios: ["下个月出国旅行，需要更改酒店预订和询问交通"])
        let english = LearningProfile(lifeScenarios: ["Write to a hotel to change my reservation before an upcoming trip."])
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 预订，预约；保留", bncRank: 6_500,
            englishMeaning: "An arrangement to save a room in a hotel for a customer.")
        for profile in [chinese, english] {
            let result = await service().recommend(word: "reservation", profile: profile, record: nil, evidence: evidence)
            #expect(result.purpose == .use)
            #expect(result.matchedScenario == profile.lifeScenarios.first)
            #expect(result.priority >= 70)
        }
    }

    @Test func changedProfileReevaluatesAWordInsteadOfKeepingAnOldClassification() async {
        let recommender = service()
        let evidence = LearningLexicalEvidence(chineseMeaning: "[医] 血管造影术")
        let unrelated = LearningProfile(workDomain: "软件开发", workScenarios: ["向同事解释数据库设计和接口方案"])
        let related = LearningProfile(workDomain: "临床医学", workScenarios: ["向患者解释血管造影术的用途和检查过程"])
        let old = await recommender.recommend(word: "angiography", profile: unrelated, record: nil, evidence: evidence)
        let new = await recommender.recommend(word: "angiography", profile: related, record: nil, evidence: evidence)
        #expect(old.purpose == .reference)
        #expect(new.purpose == .use)
        #expect(new.matchedScenario == related.workScenarios.first)
    }

    @Test func jobTitleAloneCannotMakeEverySpecialistWordAnOutputPriority() async {
        let profile = LearningProfile(workDomain: "临床医学", workScenarios: ["写邮件协调团队的下周安排"])
        let result = await service().recommend(word: "angiography", profile: profile, record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "[医] 血管造影术"))
        #expect(result.purpose == .understand)
        #expect(result.priority < 70)
    }

    @Test func genericTechnicalWorkDoesNotInventASoftwareProfession() async {
        let profile = LearningProfile(workScenarios: ["经常向同事解释技术问题"])
        let result = await service().recommend(word: "idempotent", profile: profile, record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "[计] 幂等"))
        #expect(result.purpose == .reference)
        #expect(result.matchedScenario == nil)
    }

    @Test func explicitExpressionGoalsTakePriorityWithoutInventingPhraseFrequency() async {
        let profile = LearningProfile(workScenarios: ["参与工作会议，解释自己的选择"], expressionGoals: ["希望学会建议继续采用当前方案"])
        let result = await service().recommend(word: "stick with", profile: profile, record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "继续采用，坚持；跟着", bncRank: 93,
                                              cocaRank: 123, isWholeEntryRank: false))
        #expect(result.purpose == .use)
        #expect(result.matchedScenario == profile.expressionGoals.first)
        #expect(result.frequencyDescription.contains("整段频率未知"))
        #expect(!result.frequencyDescription.contains("93"))
        #expect(!result.frequencyDescription.contains("123"))
    }

    @Test func wholePhraseCanUseItsOwnRankButUnknownDoesNotMeanLowFrequency() async {
        let profile = LearningProfile(workScenarios: ["阅读英文资料，了解历史事件"])
        let recommender = service()
        let unknown = await recommender.recommend(word: "unlisted expression", profile: profile, record: nil, evidence: nil)
        #expect(unknown.purpose == .reference)
        #expect(unknown.frequencyDescription == "词频未知")
        #expect(unknown.reason.contains("未知"))
        #expect(!unknown.reason.contains("低频"))
        let ranked = await recommender.recommend(word: "in fact", profile: profile, record: nil,
            evidence: LearningLexicalEvidence(bncRank: 2_100, isWholeEntryRank: true))
        #expect(ranked.purpose == .understand)
        #expect(ranked.frequencyDescription == "BNC 第 2100 位")
    }

    @Test func manualFeedbackWinsOverCommonnessRepetitionAndProfileChanges() async {
        let profile = LearningProfile(workDomain: "软件开发", workScenarios: ["向同事解释接口重试"])
        let record = LearningRecord(overridePurpose: .reference,
            encounterDates: ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04"])
        let result = await service().recommend(word: "retry", profile: profile, record: record,
            evidence: LearningLexicalEvidence(chineseMeaning: "[计] 重试", bncRank: 1_000))
        #expect(result.purpose == .reference)
        #expect(result.priority < 40)
        #expect(result.confidenceDescription == "你的选择优先")
        let use = await service().recommend(word: "unlisted expression", profile: LearningProfile(),
            record: LearningRecord(overridePurpose: .use), evidence: nil)
        #expect(use.purpose == .use)
        #expect(use.reason.contains("你的反馈"))
    }

    @Test func onlyDistinctEncounterDatesAreAWeakPersonalSignal() async {
        let profile = LearningProfile(lifeScenarios: ["和朋友聊旅行经历"])
        let recommender = service()
        let duplicates = await recommender.recommend(word: "quixotic", profile: profile,
            record: LearningRecord(encounterDates: ["2026-11-01", "2026-11-01", "2026-11-01"]), evidence: nil)
        let repeated = await recommender.recommend(word: "quixotic", profile: profile,
            record: LearningRecord(encounterDates: ["2026-11-01", "2026-11-02", "2026-11-03"]), evidence: nil)
        #expect(duplicates.purpose == .reference)
        #expect(repeated.purpose == .understand)
        #expect(repeated.reason.contains("主动查询"))
        #expect(!repeated.reason.contains("阅读了"))
    }

    @Test func substringAndSingleChineseCharacterOverlapCannotCreateAUseRecommendation() async {
        let profile = LearningProfile(workScenarios: ["Explain database design and addressable memory to colleagues."])
        let recommender = service()
        let result = await recommender.recommend(word: "address", profile: profile, record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 住址"))
        #expect(result.purpose == .reference)
        let chinese = await recommender.recommend(word: "workmanship",
            profile: LearningProfile(workScenarios: ["每周工作中讨论项目"]), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 工艺"))
        #expect(chinese.purpose == .reference)
    }

    @Test func installedModelPathKeepsLexicalEvidenceAndTheSourceTextIntact() async {
        let source = "Please change my reservation.\nKeep Friday!"
        let profile = LearningProfile(lifeScenarios: ["Write to a hotel to change my reservation for Friday."])
        let result = await LearningRecommendationService().recommend(word: source, profile: profile, record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "请更改我的预订，保留星期五。", isWholeEntryRank: false))
        #expect(result.purpose == .use)
        #expect(result.matchedScenario == profile.lifeScenarios.first)
        #expect(result.frequencyDescription.contains("整段频率未知"))
        #expect(source == "Please change my reservation.\nKeep Friday!")
    }

    @Test func installedSemanticModelCanRelateADefinitionToADifferentlyWordedTask() async {
        guard NLEmbedding.sentenceEmbedding(for: .english) != nil else { return }
        let profile = LearningProfile(lifeScenarios: ["Talk to a friend to say I am sorry for being late."])
        let evidence = LearningLexicalEvidence(englishMeaning: "To express regret for something that one has done wrong.")
        let lexical = await service().recommend(word: "apologize", profile: profile, record: nil, evidence: evidence)
        let semantic = await LearningRecommendationService().recommend(word: "apologize", profile: profile, record: nil, evidence: evidence)
        #expect(lexical.purpose == .reference)
        #expect(semantic.purpose == .use)
        #expect(semantic.matchedScenario == profile.lifeScenarios.first)
        #expect(semantic.confidenceDescription == "本机语义估计")
        #expect(semantic.frequencyDescription == "词频未知")
    }

    @Test(arguments: [
        ["idempotent", "[计] 幂等", "每周阅读英文技术文档，只需看懂，不需要自己说或写"],
        ["idempotent", "[计] 幂等", "I only read API documentation and do not need to explain it."],
        ["progress", "n. 进度，进展", "阅读项目进度邮件，看懂即可"]
    ])
    func negatedSpeakingOrWritingDoesNotBecomeAnOutputTask(_ sample: [String]) async {
        let result = await service().recommend(word: sample[0],
            profile: LearningProfile(workDomain: "软件开发", workScenarios: [sample[2]]), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: sample[1]))
        #expect(result.purpose == .understand)
    }

    @Test(arguments: ["阅读后写项目进度总结给同事", "不需要自己说，主要写项目进度邮件", "Read progress reports and then write a summary for colleagues."])
    func mixedReadingAndPositiveWritingKeepsTheProductiveGoal(_ scenario: String) async {
        let result = await service().recommend(word: "progress",
            profile: LearningProfile(workScenarios: [scenario]), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 进度，进展", englishMeaning: "The progress of a project."))
        #expect(result.purpose == .use)
    }

    @Test func scenarioCadenceOnlyAdjustsPriorityWithoutChangingTheReportedWordFrequency() async {
        let recommender = service()
        let daily = await recommender.recommend(word: "progress",
            profile: LearningProfile(workScenarios: ["每天汇报项目进度"]), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 进度，进展"))
        let occasional = await recommender.recommend(word: "progress",
            profile: LearningProfile(workScenarios: ["偶尔汇报项目进度"]), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 进度，进展"))
        #expect(daily.purpose == occasional.purpose)
        #expect(daily.priority > occasional.priority)
        #expect(daily.frequencyDescription == "词频未知")
        #expect(daily.frequencyDescription == occasional.frequencyDescription)
    }

    @Test func feedbackSlightlyReordersClearlyRelatedEntriesAndCanBeCleared() async {
        let recommender = service()
        let profile = LearningProfile(workScenarios: ["解释接口失败后如何重试"])
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 重试，重新尝试")
        let base = await recommender.recommend(word: "reattempt", profile: profile, record: nil, evidence: evidence)
        await recommender.updateFeedback([LearningFeedbackSample(word: "retry", purpose: .use,
            evidence: LearningLexicalEvidence(chineseMeaning: "v. 重试，重新尝试"))])
        let promoted = await recommender.recommend(word: "reattempt", profile: profile, record: nil, evidence: evidence)
        #expect(promoted.purpose == base.purpose)
        #expect(promoted.priority > base.priority)
        #expect(promoted.priority - base.priority <= 12)
        #expect(promoted.reason.contains("相近内容的反馈"))
        await recommender.updateFeedback([])
        let cleared = await recommender.recommend(word: "reattempt", profile: profile, record: nil, evidence: evidence)
        #expect(cleared == base)
    }

    @Test func feedbackCannotSpreadAcrossAnEntireDomainOrOverrideAManualPurpose() async {
        let recommender = service()
        let profile = LearningProfile(workScenarios: ["解释接口失败后如何重试和缓存数据"])
        let evidence = LearningLexicalEvidence(chineseMeaning: "[计] 缓存，缓冲存储器")
        let base = await recommender.recommend(word: "cache", profile: profile, record: nil, evidence: evidence)
        await recommender.updateFeedback([LearningFeedbackSample(word: "retry", purpose: .reference,
            evidence: LearningLexicalEvidence(chineseMeaning: "[计] 重试"))])
        let unchanged = await recommender.recommend(word: "cache", profile: profile, record: nil, evidence: evidence)
        #expect(unchanged == base)
        await recommender.updateFeedback([LearningFeedbackSample(word: "buffer", purpose: .reference,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 缓存，缓冲存储器"))])
        let manual = await recommender.recommend(word: "cache", profile: profile,
            record: LearningRecord(overridePurpose: .use), evidence: evidence)
        #expect(manual.purpose == .use)
        #expect(manual.priority == 88)
        #expect(!manual.reason.contains("相近内容"))
    }

    @Test func aWordCannotBoostItselfAndReferenceFeedbackHasOnlyABoundedEffect() async {
        let recommender = service()
        let profile = LearningProfile(workScenarios: ["解释接口失败后如何重试"])
        let evidence = LearningLexicalEvidence(chineseMeaning: "v. 重试，重新尝试")
        let base = await recommender.recommend(word: "retry", profile: profile, record: nil, evidence: evidence)
        await recommender.updateFeedback([LearningFeedbackSample(word: "RETRY", purpose: .use, evidence: evidence)])
        let sameWord = await recommender.recommend(word: "retry", profile: profile, record: nil, evidence: evidence)
        #expect(sameWord == base)
        await recommender.updateFeedback([LearningFeedbackSample(word: "reattempt", purpose: .reference, evidence: evidence)])
        let adjusted = await recommender.recommend(word: "retry", profile: profile, record: nil, evidence: evidence)
        #expect(adjusted.purpose == base.purpose)
        #expect(base.priority - adjusted.priority == 12)
        #expect(adjusted.reason.contains("相近内容的反馈"))
    }

    @Test func explicitSelectedLearningGoalControlsTheSameTopicAndExpression() async {
        let recommender = service()
        let content = "工作领域：软件开发。任务：阅读技术文档。话题：解释接口重试方案和表达意见。实际通道：阅读。频率：未确定。"
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 意见，观点；建议")
        let useScene = "学习目标：希望会用。" + content
        let understandScene = "学习目标：看懂即可。" + content
        let use = await recommender.recommend(word: "opinion",
            profile: LearningProfile(workDomain: "软件开发", workScenarios: [useScene]), record: nil, evidence: evidence)
        let understand = await recommender.recommend(word: "opinion",
            profile: LearningProfile(workDomain: "软件开发", workScenarios: [understandScene]), record: nil, evidence: evidence)
        #expect(use.purpose == .use)
        #expect(understand.purpose == .understand)
        #expect(use.matchedScenario == useScene)
        #expect(understand.matchedScenario == understandScene)
        #expect(use.frequencyDescription == "词频未知")
        #expect(understand.frequencyDescription == "词频未知")
    }

    @Test(arguments: ["表达意见与介绍自己的兴趣", "如何说明原因、提出建议和询问问题"])
    func selectedReadingGoalWinsOverProductiveWordsInsideTheTopic(_ topic: String) async {
        let scene = "学习目标：看懂即可。生活领域：社交。任务：阅读文章。话题：\(topic)。实际通道：阅读。频率：未确定。"
        let result = await service().recommend(word: "opinion",
            profile: LearningProfile(lifeScenarios: [scene]), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "n. 意见，观点；建议"))
        #expect(result.purpose == .understand)
    }

    @Test func aStructuredGoalIsNotLexicalEvidenceAndUnknownCadenceGetsNoBoost() async {
        let recommender = service()
        let plain = "向同事解释接口重试方案"
        let withUnspecified = "学习目标：希望会用。" + plain + "。使用频率：未确定。"
        let evidence = LearningLexicalEvidence(chineseMeaning: "[计] 幂等")
        let a = await recommender.recommend(word: "idempotent",
            profile: LearningProfile(workScenarios: [plain]), record: nil, evidence: evidence)
        let b = await recommender.recommend(word: "idempotent",
            profile: LearningProfile(workScenarios: [withUnspecified]), record: nil, evidence: evidence)
        #expect(a.purpose == b.purpose)
        #expect(a.priority == b.priority)
        let unrelated = await recommender.recommend(word: "goal",
            profile: LearningProfile(lifeScenarios: ["学习目标：希望会用。任务：办理酒店预订。实际通道：口语。频率：未确定。"]),
            record: nil, evidence: LearningLexicalEvidence(chineseMeaning: "n. 学习目标，目的"))
        #expect(unrelated.purpose == .reference)
        #expect(unrelated.matchedScenario == nil)
    }

    @Test func selectedOptionsGenerateProfileAndRespectTheChosenLearningGoal() async {
        var options = LearningProfileOptions()
        options.domainID = "software"
        options.work = [LearningScenarioChoice(presetID: "work.report_progress", use: .both, frequency: .unspecified)]
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 进度，进展")
        let recommender = service()
        let use = await recommender.recommend(word: "progress", profile: options.makeProfile(), record: nil, evidence: evidence)
        options.work[0].use = .understanding
        let understand = await recommender.recommend(word: "progress", profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(use.purpose == .use)
        #expect(understand.purpose == .understand)
        #expect(use.frequencyDescription == "词频未知")
        #expect(understand.frequencyDescription == "词频未知")
    }

    @Test func genericCoordinationOptionDoesNotMakeAllWordsInTheUsersDomainProductive() async {
        var options = LearningProfileOptions()
        options.domainID = "software"
        options.work = [LearningScenarioChoice(presetID: "work.coordinate", use: .both, frequency: .weekly)]
        let result = await service().recommend(word: "idempotent", profile: options.makeProfile(), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: "[计] 幂等"))
        #expect(result.purpose == .understand)
        #expect(result.priority < 70)
    }

    @Test func selectedTravelOptionsKeepFrequencyUnspecifiedAndOnlyCadenceChangesOrder() async {
        var options = LearningProfileOptions()
        options.life = [LearningScenarioChoice(presetID: "life.travel", use: .speaking, frequency: .unspecified)]
        let recommender = service()
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 预订，预约")
        let unspecified = await recommender.recommend(word: "reservation", profile: options.makeProfile(), record: nil, evidence: evidence)
        options.life[0].frequency = .occasional
        let occasional = await recommender.recommend(word: "reservation", profile: options.makeProfile(), record: nil, evidence: evidence)
        options.life[0].frequency = .daily
        let daily = await recommender.recommend(word: "reservation", profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(unspecified.purpose == .use)
        #expect(unspecified.priority == occasional.priority)
        #expect(daily.priority > occasional.priority)
        #expect(unspecified.frequencyDescription == "词频未知")
        #expect(occasional.frequencyDescription == "词频未知")
        #expect(daily.frequencyDescription == "词频未知")
    }

    @Test(arguments: [["scenario", "n. 场景，情景"], ["practice", "n. 练习，学习"]])
    func optionsBoilerplateIsNotEvidenceThatEveryEntryMatchesTheTask(_ sample: [String]) async {
        var options = LearningProfileOptions()
        options.life = [LearningScenarioChoice(presetID: "life.travel", use: .both)]
        let result = await service().recommend(word: sample[0], profile: options.makeProfile(), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: sample[1]))
        #expect(result.purpose == .reference)
        #expect(result.matchedScenario == nil)
    }

    @Test func equallyRelevantSelectedReadingAndWritingPreferUseInEitherSelectionOrder() async {
        var options = LearningProfileOptions()
        let reading = LearningScenarioChoice(presetID: "work.report_progress", use: .understanding, frequency: .unspecified)
        let writing = LearningScenarioChoice(presetID: "work.coordinate", use: .writing, frequency: .weekly)
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 计划，安排")
        let recommender = service()
        options.work = [reading]
        let readingOnly = await recommender.recommend(word: "schedule", profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(readingOnly.purpose == .understand)
        options.work = [reading, writing]
        let firstProfile = options.makeProfile()
        let forward = await recommender.recommend(word: "schedule", profile: firstProfile, record: nil, evidence: evidence)
        options.work.reverse()
        let reversed = await recommender.recommend(word: "schedule", profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(forward.purpose == .use)
        #expect(forward.matchedScenario == firstProfile.workScenarios[1])
        #expect(reversed == forward)
    }

    @Test func weakerCoordinationEvidenceCannotOverrideAStrongerReadingMatch() async {
        var options = LearningProfileOptions()
        options.domainID = "software"
        options.work = [
            LearningScenarioChoice(presetID: "work.read_materials", use: .understanding, frequency: .occasional),
            LearningScenarioChoice(presetID: "work.coordinate", use: .writing, frequency: .daily)
        ]
        let evidence = LearningLexicalEvidence(chineseMeaning: "[计] 幂等")
        let recommender = service()
        let profile = options.makeProfile()
        let first = await recommender.recommend(word: "idempotent", profile: profile, record: nil, evidence: evidence)
        options.work.reverse()
        let reversed = await recommender.recommend(word: "idempotent", profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(first.purpose == .understand)
        #expect(first.matchedScenario == profile.workScenarios[0])
        #expect(reversed == first)
    }

    @Test func equallyRelevantOutputGoalPrecedesReadingCadenceAndOutputCadenceBreaksRemainingTies() async {
        var options = LearningProfileOptions()
        let reading = LearningScenarioChoice(presetID: "work.report_progress", use: .understanding, frequency: .daily)
        let writing = LearningScenarioChoice(presetID: "work.coordinate", use: .writing, frequency: .occasional)
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 计划，安排")
        let recommender = service()
        options.work = [reading, writing]
        let profile = options.makeProfile()
        let output = await recommender.recommend(word: "schedule", profile: profile, record: nil, evidence: evidence)
        #expect(output.purpose == .use)
        #expect(output.matchedScenario == profile.workScenarios[1])

        options.work = [
            LearningScenarioChoice(presetID: "work.report_progress", use: .writing, frequency: .weekly),
            LearningScenarioChoice(presetID: "work.coordinate", use: .writing, frequency: .daily)
        ]
        let outputProfile = options.makeProfile()
        let frequent = await recommender.recommend(word: "schedule", profile: outputProfile, record: nil, evidence: evidence)
        options.work.reverse()
        let reversed = await recommender.recommend(word: "schedule", profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(frequent.matchedScenario == outputProfile.workScenarios[1])
        #expect(reversed == frequent)
    }

    @Test func equalScoreExpressionGoalsAndRemainingLiteralTiesAreStable() async {
        let recommender = service()
        let goals = LearningProfile(workScenarios: ["每天阅读 retry 的接口文档，看懂即可"], expressionGoals: ["想用 retry 表达重新尝试"])
        let expression = await recommender.recommend(word: "retry", profile: goals, record: nil, evidence: nil)
        #expect(expression.purpose == .use)
        #expect(expression.matchedScenario == goals.expressionGoals.first)

        var options = LearningProfileOptions()
        options.work = [
            LearningScenarioChoice(presetID: "work.report_progress", use: .writing, frequency: .weekly),
            LearningScenarioChoice(presetID: "work.coordinate", use: .writing, frequency: .weekly)
        ]
        let evidence = LearningLexicalEvidence(chineseMeaning: "n. 计划，安排")
        let first = await recommender.recommend(word: "schedule", profile: options.makeProfile(), record: nil, evidence: evidence)
        options.work.reverse()
        let reversed = await recommender.recommend(word: "schedule", profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(first.purpose == .use)
        #expect(reversed == first)
    }

    @Test(arguments: [
        ["软件开发", "idempotent", "[计] 幂等", "每天向同事解释软件问题，介绍产品和服务"],
        ["临床医学", "angiography", "[医] 血管造影术", "每天向患者解释临床检查和治疗方案"],
        ["法律合规", "tortfeasor", "[法] 侵权行为人", "每周向客户解释法律问题和合同服务"],
        ["财务金融", "amortization", "[经] 摊销", "每周介绍会计服务并说明财务报表"],
        ["化学研究", "stoichiometry", "[化] 化学计量学", "每周向同事解释化学实验的问题和方案"]
    ])
    func domainRelevanceAloneDefaultsToUnderstandingAcrossProfessions(_ sample: [String]) async {
        let profile = LearningProfile(workDomain: sample[0], workScenarios: [sample[3]])
        let evidence = LearningLexicalEvidence(chineseMeaning: sample[2])
        for recommender in [service(), LearningRecommendationService()] {
            let result = await recommender.recommend(word: sample[1], profile: profile, record: nil, evidence: evidence)
            #expect(result.purpose == .understand)
            #expect(result.priority < 70)
            #expect(result.frequencyDescription == "词频未知")
            #expect(!result.reason.contains("适合练习从意图想出英文"))
        }
    }

    @Test(arguments: [
        ["software", "idempotent", "[计] 幂等"],
        ["software", "reentrancy", "[计] 可重入"],
        ["software", "serialization", "[计] 串行化"],
        ["health", "angiography", "[医] 血管造影术"],
        ["legal", "tortfeasor", "[法] 侵权行为人"],
        ["finance", "amortization", "[经] 摊销"]
    ])
    func broadOutputOptionsDoNotPromoteEveryTermInTheirDomain(_ sample: [String]) async {
        var options = LearningProfileOptions()
        options.domainID = sample[0]
        options.work = [
            LearningScenarioChoice(presetID: "work.explain_problems", use: .both, frequency: .daily),
            LearningScenarioChoice(presetID: "work.introduce_services", use: .writing, frequency: .upcoming)
        ]
        let recommender = service()
        let evidence = LearningLexicalEvidence(chineseMeaning: sample[2])
        let first = await recommender.recommend(word: sample[1], profile: options.makeProfile(), record: nil, evidence: evidence)
        options.work.reverse()
        let reversed = await recommender.recommend(word: sample[1], profile: options.makeProfile(), record: nil, evidence: evidence)
        #expect(first.purpose == .understand)
        #expect(first.priority < 70)
        #expect(reversed == first)
    }

    @Test(arguments: [false, true])
    func frequencyRepetitionCadenceAndRelatedFeedbackCannotSubstituteForAnActualUsageNeed(_ hasRank: Bool) async {
        let recommender = service()
        let profile = LearningProfile(workDomain: "软件开发", workScenarios: ["每天向同事解释软件问题和产品功能"])
        let evidence = LearningLexicalEvidence(chineseMeaning: "[计] 幂等",
                                              bncRank: hasRank ? 100 : nil, cocaRank: hasRank ? 200 : nil)
        let dates = (1...8).map { String(format: "2026-11-%02d", $0) }
        let record = LearningRecord(encounterDates: dates)
        let before = await recommender.recommend(word: "idempotent", profile: profile, record: record, evidence: evidence)
        await recommender.updateFeedback([LearningFeedbackSample(word: "idempotence", purpose: .use,
            evidence: LearningLexicalEvidence(chineseMeaning: "[计] 幂等"))])
        let calibrated = await recommender.recommend(word: "idempotent", profile: profile, record: record, evidence: evidence)
        #expect(before.purpose == .understand)
        #expect(calibrated.purpose == .understand)
        #expect(before.frequencyDescription == calibrated.frequencyDescription)
        if !hasRank { #expect(calibrated.frequencyDescription == "词频未知") }
    }

    @Test(arguments: [
        ["软件开发", "idempotent", "[计] 幂等", "向同事解释幂等的概念及其在接口中的用法"],
        ["临床医学", "angiography", "[医] 血管造影术", "向患者解释血管造影术的过程和用途"],
        ["法律合规", "tortfeasor", "[法] 侵权行为人", "向客户解释 tortfeasor 的法律责任"],
        ["财务金融", "amortization", "[经] 摊销", "撰写 amortization 的计算说明"],
        ["化学研究", "stoichiometry", "[化] 化学计量学", "向实验同事解释 stoichiometry 的计算方法"]
    ])
    func specificUsageNeedsCanPromoteSpecialistTermsWhileReadingStillOnlyRequiresUnderstanding(_ sample: [String]) async {
        let recommender = service()
        let evidence = LearningLexicalEvidence(chineseMeaning: sample[2])
        let output = "学习目标：希望会用。" + sample[3]
        let reading = "学习目标：看懂即可。" + sample[3]
        let use = await recommender.recommend(word: sample[1],
            profile: LearningProfile(workDomain: sample[0], workScenarios: [output]), record: nil, evidence: evidence)
        let understand = await recommender.recommend(word: sample[1],
            profile: LearningProfile(workDomain: sample[0], workScenarios: [reading]), record: nil, evidence: evidence)
        #expect(use.purpose == .use)
        #expect(use.matchedScenario == output)
        #expect(understand.purpose == .understand)
        #expect(use.frequencyDescription == "词频未知")
    }

    @Test func theReportedProfileDefaultsSpecialistVocabularyToUnderstandingWithoutAPerWordException() async {
        var options = LearningProfileOptions()
        options.domainID = "software"
        options.work = ["work.express_opinions", "work.explain_problems", "work.introduce_services"]
            .map { LearningScenarioChoice(presetID: $0, use: .both, frequency: .unspecified) }
        options.life = ["life.experiences", "life.feelings", "life.interests"]
            .map { LearningScenarioChoice(presetID: $0, use: .both, frequency: .unspecified) }
        options.expressionIDs = ["clarify", "disagree", "explain_reasons"]
        let profile = options.makeProfile()
        let recommender = service()
        for (word, meaning) in [("idempotent", "[计] 幂等"), ("reentrancy", "[计] 可重入")] {
            let result = await recommender.recommend(word: word, profile: profile,
                record: LearningRecord(encounterDates: ["2026-11-18"]),
                evidence: LearningLexicalEvidence(chineseMeaning: meaning))
            #expect(result.purpose == .understand)
            #expect(result.priority < 70)
            #expect(result.frequencyDescription == "词频未知")
        }
        let explicitChoice = await recommender.recommend(word: "idempotent", profile: profile,
            record: LearningRecord(overridePurpose: .use), evidence: LearningLexicalEvidence(chineseMeaning: "[计] 幂等"))
        #expect(explicitChoice.purpose == .use)
        #expect(explicitChoice.confidenceDescription == "你的选择优先")
    }

    @Test(arguments: [
        ["abstraction", "[计] 一种组织内容和处理问题的方法", "软件开发", "每天讨论软件问题的方法与内容"],
        ["angiography", "[医] 一种检查方法", "临床医学", "向患者解释临床检查的方法"]
    ])
    func genericDefinitionWordsDoNotProveANeedToProduceASpecialistTerm(_ sample: [String]) async {
        let result = await service().recommend(word: sample[0],
            profile: LearningProfile(workDomain: sample[2], workScenarios: [sample[3]]), record: nil,
            evidence: LearningLexicalEvidence(chineseMeaning: sample[1]))
        #expect(result.purpose == .understand)
        #expect(result.priority < 70)
    }
}
