import Foundation
import Testing
@testable import WordShelfCore

@Suite("Controlled learning profile options")
@MainActor
struct LearningProfileOptionsTests {
    private func populated() -> LearningProfileOptions {
        var options = LearningProfileOptions()
        options.domainID = "software"
        options.work = [LearningScenarioChoice(presetID: "work.explain_problems", use: .writing, frequency: .weekly)]
        options.life = [LearningScenarioChoice(presetID: "life.travel", use: .speaking, frequency: .upcoming)]
        options.expressionIDs = ["explain_reasons", "suggest"]
        return options
    }

    @Test func profileCanBeConfiguredEntirelyByOptionsWithoutInventingFrequency() throws {
        var options = LearningProfileOptions()
        options.work = [try #require(LearningProfileCatalog.workScenarios.first { $0.id == "work.read_materials" }).choice()]
        let profile = options.makeProfile()
        #expect(profile.isConfigured)
        #expect(options.validationMessage == nil)
        #expect(profile.validationMessage == nil)
        #expect(profile.workDomain.isEmpty)
        #expect(profile.options == options)
        #expect(profile.workScenarios[0].hasPrefix("学习目标：看懂即可。工作场景："))
        #expect(!["每天", "每周", "偶尔", "近期"].contains { profile.workScenarios[0].contains($0) })
    }

    @Test func savedChoicesReopenWithTheirIDsUsesAndFrequenciesIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let options = populated()
        let profile = options.makeProfile()
        let store = LearningStore(directoryURL: directory)
        try store.saveProfile(profile)
        let reloaded = LearningStore(directoryURL: directory)
        #expect(reloaded.loadError == nil)
        #expect(reloaded.profile == profile)
        #expect(LearningProfileOptions(profile: reloaded.profile) == options)
        #expect(reloaded.profile.workScenarios[0].contains("每周"))
        #expect(reloaded.profile.workScenarios[0].contains("书面表达"))
        #expect(reloaded.profile.lifeScenarios[0].contains("近期"))
        #expect(reloaded.profile.lifeScenarios[0].contains("口头表达"))
    }

    @Test func oldFreeFormProfileIsDecodedAndPreservedWithoutGuessingOptions() throws {
        let old = Data(#"{"workDomain":"软件开发","workScenarios":["每周向同事解释 API 问题。","Read a paper, then write a summary."],"lifeScenarios":["和朋友聊最近的经历。"],"expressionGoals":["这个方案先继续试试。"]}"#.utf8)
        let profile = try JSONDecoder().decode(LearningProfile.self, from: old)
        #expect(profile.options == nil)
        let options = LearningProfileOptions(profile: profile)
        #expect(options.domainID == nil)
        #expect(options.legacyDomain == "软件开发")
        #expect(options.work.isEmpty && options.life.isEmpty && options.expressionIDs.isEmpty)
        #expect(options.legacyWork == profile.workScenarios)
        #expect(options.legacyLife == profile.lifeScenarios)
        #expect(options.legacyExpressions == profile.expressionGoals)
        let result = options.makeProfile()
        #expect(result.workDomain == profile.workDomain)
        #expect(result.workScenarios == profile.workScenarios)
        #expect(result.lifeScenarios == profile.lifeScenarios)
        #expect(result.expressionGoals == profile.expressionGoals)
        #expect(result.fingerprint == profile.fingerprint)
        #expect(result.validationMessage == nil)
    }

    @Test func onlyAnExactExistingDomainTitleRestoresAKnownDomainOption() {
        let exact = LearningProfileOptions(profile: LearningProfile(workDomain: "软件与技术", workScenarios: ["阅读接口文档。 "]))
        #expect(exact.domainID == "software")
        #expect(exact.legacyDomain == nil)
        #expect(exact.legacyWork == ["阅读接口文档。 "])
        let other = LearningProfileOptions(profile: LearningProfile(workDomain: "软件架构与平台工程", workScenarios: ["阅读接口文档。 "]))
        #expect(other.domainID == nil)
        #expect(other.legacyDomain == "软件架构与平台工程")
    }

    @Test func limitsIncludeRetainedCustomEntriesAndNeverDropThemSilently() {
        var options = populated()
        options.legacyWork = ["旧工作一", "旧工作二", "旧工作三"]
        #expect(options.validationMessage?.contains("工作场景最多") == true)
        #expect(options.makeProfile().workScenarios.suffix(3) == ["旧工作一", "旧工作二", "旧工作三"])
        options.legacyWork = []
        options.legacyLife = ["旧生活一", "旧生活二", "旧生活三"]
        #expect(options.validationMessage?.contains("生活场景最多") == true)
        options.legacyLife = []
        options.legacyExpressions = ["旧目标一", "旧目标二", "旧目标三", "旧目标四"]
        #expect(options.validationMessage?.contains("表达目标最多") == true)
    }

    @Test func unknownOrDuplicateIDsAndEmptyProfilesAreRejected() {
        #expect(LearningProfileOptions().validationMessage != nil)
        var options = populated()
        options.domainID = "not-a-domain"
        #expect(options.validationMessage?.contains("工作领域选项") == true)
        options.domainID = nil
        options.work = [.init(presetID: "life.travel")]
        #expect(options.validationMessage?.contains("场景选项") == true)
        options.work = [.init(presetID: "work.coordinate"), .init(presetID: "work.coordinate")]
        #expect(options.validationMessage?.contains("重复") == true)
        options.work = [.init(presetID: "work.coordinate")]
        options.expressionIDs = ["not-an-expression"]
        #expect(options.validationMessage?.contains("表达目标选项") == true)
        options.expressionIDs = ["thank", "thank"]
        #expect(options.validationMessage?.contains("重复") == true)
        #expect(options.makeProfile().validationMessage != nil)
    }

    @Test func explicitUseAndFrequencyProduceDeterministicUnderstandableScenarios() {
        for use in LearningScenarioUse.allCases {
            for frequency in LearningScenarioFrequency.allCases {
                var options = LearningProfileOptions()
                options.work = [.init(presetID: "work.explain_problems", use: use, frequency: frequency)]
                let profile = options.makeProfile()
                let text = profile.workScenarios[0]
                let expected = use == .understanding ? "学习目标：看懂即可。" : "学习目标：希望会用。"
                #expect(text.hasPrefix(expected))
                #expect(text.contains("问题、原因与影响"))
                if use == .understanding {
                    #expect(text.contains("阅读或听懂"))
                    #expect(!text.contains("解释问题"))
                }
                if frequency != .unspecified {
                    #expect(text.contains(frequency == .upcoming ? "近期" : frequency.title))
                }
                #expect(profile == options.makeProfile())
            }
        }
    }

    @Test func specialistDomainOnlyQualifiesRelevantWorkTasks() {
        var options = populated()
        options.work = [.init(presetID: "work.explain_problems"), .init(presetID: "work.coordinate"), .init(presetID: "work.report_progress")]
        let profile = options.makeProfile()
        #expect(profile.workScenarios[0].contains("软件与技术方面的问题"))
        #expect(!profile.workScenarios[1].contains("软件与技术"))
        #expect(!profile.workScenarios[2].contains("软件与技术"))
        #expect(!profile.lifeScenarios[0].contains("软件与技术"))
        options.domainID = "other"
        #expect(!options.makeProfile().workScenarios[0].contains("其他专业方面"))
        options.domainID = nil
        #expect(!options.makeProfile().workScenarios[0].contains("方面"))
    }

    @Test func fingerprintTracksSemanticChoicesWhileIgnoringSelectionOrder() {
        var first = populated()
        first.work.append(.init(presetID: "work.coordinate"))
        var reordered = first
        reordered.work.reverse()
        reordered.expressionIDs.reverse()
        #expect(first.makeProfile().fingerprint == reordered.makeProfile().fingerprint)
        reordered.work[0].frequency = .daily
        #expect(first.makeProfile().fingerprint != reordered.makeProfile().fingerprint)
    }

    @Test func invalidStoredOptionIDsArePreservedAndCannotBeOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directoryURL: directory)
        try store.saveProfile(populated().makeProfile())
        var saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        var profile = try #require(saved["profile"] as? [String: Any])
        var options = try #require(profile["options"] as? [String: Any])
        options["domainID"] = "unknown-future-domain"
        profile["options"] = options
        saved["profile"] = profile
        let damaged = try JSONSerialization.data(withJSONObject: saved)
        try damaged.write(to: store.fileURL)
        let reloaded = LearningStore(directoryURL: directory)
        #expect(reloaded.loadError != nil)
        #expect(throws: (any Error).self) { try reloaded.saveProfile(populated().makeProfile()) }
        #expect(try Data(contentsOf: store.fileURL) == damaged)
    }
}
