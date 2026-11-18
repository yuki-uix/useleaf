import Foundation

public enum LearningScenarioUse: String, Codable, CaseIterable, Sendable {
    case speaking
    case writing
    case both
    case understanding

    public var title: String {
        switch self {
        case .speaking: return "主要说"
        case .writing: return "主要写"
        case .both: return "说写都用"
        case .understanding: return "读听理解"
        }
    }
}

public enum LearningScenarioFrequency: String, Codable, CaseIterable, Sendable {
    case unspecified
    case daily
    case weekly
    case occasional
    case upcoming

    public var title: String {
        switch self {
        case .unspecified: return "暂不确定"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .occasional: return "偶尔"
        case .upcoming: return "近期重要"
        }
    }

    fileprivate var phrase: String {
        switch self {
        case .unspecified: return ""
        case .daily: return "每天"
        case .weekly: return "每周"
        case .occasional: return "偶尔"
        case .upcoming: return "近期"
        }
    }
}

public struct LearningScenarioChoice: Codable, Equatable, Sendable, Identifiable {
    public var presetID: String
    public var use: LearningScenarioUse
    public var frequency: LearningScenarioFrequency
    public var id: String { presetID }

    public init(presetID: String, use: LearningScenarioUse = .both, frequency: LearningScenarioFrequency = .unspecified) {
        self.presetID = presetID
        self.use = use
        self.frequency = frequency
    }
}

public struct LearningScenarioPreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// A noun phrase suitable for either input or output practice.
    public let topic: String
    public let defaultUse: LearningScenarioUse

    public init(id: String, title: String, topic: String, defaultUse: LearningScenarioUse = .both) {
        self.id = id
        self.title = title
        self.topic = topic
        self.defaultUse = defaultUse
    }

    public func choice() -> LearningScenarioChoice {
        LearningScenarioChoice(presetID: id, use: defaultUse)
    }
}

public struct LearningProfileDomain: Identifiable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum LearningProfileCatalog {
    public static let domains: [LearningProfileDomain] = [
        .init(id: "software", title: "软件与技术"),
        .init(id: "design", title: "产品与设计"),
        .init(id: "business", title: "商务与市场"),
        .init(id: "research", title: "学术与科研"),
        .init(id: "finance", title: "财务与金融"),
        .init(id: "health", title: "医疗与健康"),
        .init(id: "legal", title: "法律与合规"),
        .init(id: "other", title: "其他专业")
    ]

    public static let workScenarios: [LearningScenarioPreset] = [
        .init(id: "work.read_materials", title: "阅读专业资料", topic: "专业资料与技术信息", defaultUse: .understanding),
        .init(id: "work.explain_problems", title: "解释问题", topic: "问题、原因与影响"),
        .init(id: "work.discuss_solutions", title: "讨论方案", topic: "解决方案与取舍"),
        .init(id: "work.report_progress", title: "汇报进度", topic: "项目进度、计划与截止时间"),
        .init(id: "work.clarify_requirements", title: "澄清需求", topic: "需求、约束与理解"),
        .init(id: "work.coordinate", title: "协调安排", topic: "会议安排、时间与协作"),
        .init(id: "work.express_opinions", title: "表达意见", topic: "观点、建议与不同意见"),
        .init(id: "work.introduce_services", title: "介绍产品或服务", topic: "产品、服务与功能")
    ]

    public static let lifeScenarios: [LearningScenarioPreset] = [
        .init(id: "life.travel", title: "旅行办事", topic: "旅行、交通、酒店与预订"),
        .init(id: "life.shopping", title: "购物点餐", topic: "购物、价格、餐饮与点单"),
        .init(id: "life.chat", title: "日常闲聊", topic: "近况、日常生活与聊天"),
        .init(id: "life.interests", title: "兴趣与文娱", topic: "兴趣、影视、游戏与爱好"),
        .init(id: "life.experiences", title: "分享经历", topic: "个人经历、故事与见闻"),
        .init(id: "life.feelings", title: "表达感受", topic: "感受、情绪与想法"),
        .init(id: "life.plans", title: "邀请与计划", topic: "邀请、活动安排与未来计划"),
        .init(id: "life.content", title: "阅读或观看英文内容", topic: "英文文章、影视与节目内容", defaultUse: .understanding)
    ]

    public static let expressionGoals: [LearningProfileDomain] = [
        .init(id: "explain_reasons", title: "说明原因"),
        .init(id: "suggest", title: "提出建议"),
        .init(id: "disagree", title: "表达不同意见"),
        .init(id: "decline", title: "委婉拒绝"),
        .init(id: "clarify", title: "澄清理解"),
        .init(id: "thank", title: "表达感谢"),
        .init(id: "follow_up", title: "跟进事情"),
        .init(id: "preferences", title: "表达偏好")
    ]
}

public struct LearningProfileOptions: Codable, Equatable, Sendable {
    public var domainID: String?
    public var work: [LearningScenarioChoice]
    public var life: [LearningScenarioChoice]
    public var expressionIDs: [String]
    public var legacyDomain: String?
    public var legacyWork: [String]
    public var legacyLife: [String]
    public var legacyExpressions: [String]

    public init() {
        domainID = nil
        work = []
        life = []
        expressionIDs = []
        legacyDomain = nil
        legacyWork = []
        legacyLife = []
        legacyExpressions = []
    }

    /// Existing free-form content is kept verbatim. Only an exact domain title
    /// match can be restored as a known option; scene meanings are never guessed.
    public init(profile: LearningProfile) {
        if let saved = profile.options { self = saved; return }
        self.init()
        if let domain = LearningProfileCatalog.domains.first(where: { $0.title == profile.workDomain }) {
            domainID = domain.id
        } else if !profile.workDomain.isEmpty {
            legacyDomain = profile.workDomain
        }
        legacyWork = profile.workScenarios
        legacyLife = profile.lifeScenarios
        legacyExpressions = profile.expressionGoals
    }

    public var validationMessage: String? {
        let domains = Set(LearningProfileCatalog.domains.map(\.id))
        let workIDs = Set(LearningProfileCatalog.workScenarios.map(\.id))
        let lifeIDs = Set(LearningProfileCatalog.lifeScenarios.map(\.id))
        let expressionIDs = Set(LearningProfileCatalog.expressionGoals.map(\.id))
        if let domainID, !domains.contains(domainID) { return "工作领域选项已失效，请重新选择。" }
        if !work.allSatisfy({ workIDs.contains($0.presetID) }) || !life.allSatisfy({ lifeIDs.contains($0.presetID) }) {
            return "场景选项已失效，请重新选择。"
        }
        if !self.expressionIDs.allSatisfy({ expressionIDs.contains($0) }) { return "表达目标选项已失效，请重新选择。" }
        if Set(work.map(\.presetID)).count != work.count || Set(life.map(\.presetID)).count != life.count
            || Set(self.expressionIDs).count != self.expressionIDs.count { return "请不要重复选择相同选项。" }
        if work.count + legacyWork.count > 3 { return "工作场景最多选择 3 条（含保留的已有场景）。" }
        if life.count + legacyLife.count > 3 { return "生活场景最多选择 3 条（含保留的已有场景）。" }
        if self.expressionIDs.count + legacyExpressions.count > 5 { return "表达目标最多选择 5 条（含保留的已有内容）。" }
        if (legacyDomain?.count ?? 0) > 120 { return "已有工作领域最多保留 120 个字符。" }
        if (legacyWork + legacyLife + legacyExpressions).contains(where: { $0.count > 500 }) { return "每条已有场景或表达目标最多保留 500 个字符。" }
        if (legacyWork + legacyLife + legacyExpressions).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "已有场景包含空白条目，请取消保留后重试。"
        }
        if work.isEmpty && life.isEmpty && legacyWork.isEmpty && legacyLife.isEmpty { return "请至少选择一个工作或生活场景。" }
        return nil
    }

    public func makeProfile() -> LearningProfile {
        let domain = domainID.flatMap { selected in LearningProfileCatalog.domains.first { $0.id == selected }?.title }
            ?? legacyDomain ?? ""
        let specificDomain = domainID.flatMap { selected -> String? in
            guard selected != "other" else { return nil }
            return LearningProfileCatalog.domains.first { $0.id == selected }?.title
        }
        return LearningProfile(
            workDomain: domain,
            workScenarios: makeScenarios(work, catalog: LearningProfileCatalog.workScenarios, scope: "工作", specificDomain: specificDomain) + legacyWork,
            lifeScenarios: makeScenarios(life, catalog: LearningProfileCatalog.lifeScenarios, scope: "生活") + legacyLife,
            expressionGoals: expressionIDs.compactMap { selected in LearningProfileCatalog.expressionGoals.first { $0.id == selected }?.title } + legacyExpressions,
            options: self
        )
    }

    private func makeScenarios(_ choices: [LearningScenarioChoice], catalog: [LearningScenarioPreset], scope: String, specificDomain: String? = nil) -> [String] {
        choices.compactMap { choice in
            guard let preset = catalog.first(where: { $0.id == choice.presetID }) else { return nil }
            let goal = choice.use == .understanding ? "看懂即可" : "希望会用"
            let specialistTasks: Set<String> = ["work.read_materials", "work.explain_problems", "work.discuss_solutions", "work.introduce_services"]
            let topic: String
            if let specificDomain, specialistTasks.contains(choice.presetID) {
                topic = "\(specificDomain)方面的\(preset.topic)"
            } else { topic = preset.topic }
            let action: String
            switch choice.use {
            case .speaking: action = "就\(topic)与他人交流，练习口头表达。"
            case .writing: action = "围绕\(topic)撰写消息或文字，练习书面表达。"
            case .both: action = "围绕\(topic)与他人沟通，练习口头和书面表达。"
            case .understanding: action = "阅读或听懂有关\(topic)的内容，以理解为目标。"
            }
            return "学习目标：\(goal)。\(scope)场景：\(choice.frequency.phrase)\(action)"
        }
    }
}
