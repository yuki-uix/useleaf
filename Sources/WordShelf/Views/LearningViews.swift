import SwiftUI
import WordShelfCore

struct LearningNotebookSummary: View {
    @ObservedObject var learning: LearningModel
    let onProfile: () -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(learning.profile.isConfigured ? "把收藏变成用得上的表达" : "让推荐更贴合你的工作和生活")
                        .font(.system(size: 13, weight: .semibold))
                    if learning.isAnalyzing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("正在根据你的场景整理推荐…")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(WordShelfTheme.secondary)
                    } else {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(WordShelfTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(learning.profile.isConfigured ? "编辑场景" : "设置我的场景", action: onProfile)
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("learning.profile")
                if learning.profile.isConfigured {
                    Button("开始学习", action: onReview)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(learning.isAnalyzing || learning.dueCount == 0)
                        .accessibilityIdentifier("learning.startReview")
                }
            }
            if let error = learning.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("learning.error")
            }
        }
        .padding(14)
        .background(WordShelfTheme.subtle.opacity(0.52), in: RoundedRectangle(cornerRadius: 10))
    }

    private var summary: String {
        guard learning.profile.isConfigured else {
            return "选几个常用场景，自动推荐学习用途；无需逐条输入，查词和收藏照常使用。"
        }
        if learning.dueCount > 0 {
            return "今天可学 \(learning.dueCount) 条 · 从场景回想表达，再对照参考自评。"
        }
        if let date = learning.nextDueDate {
            return "本次已学完 · 下次复习 \(date.formatted(.dateTime.locale(Locale(identifier: "zh_Hans_CN")).year().month().day()))"
        }
        return learning.eligibleCount == 0 ? "还没有进入学习队列的收藏；可以继续积累，或调整一条推荐。" : "当前没有到期内容，稍后再来回想一次。"
    }
}

struct LearningRecommendationView: View {
    let word: String
    let recommendation: LearningRecommendation
    let onPurpose: (LearningPurpose?) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(recommendation.purpose.title)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WordShelfTheme.subtle, in: Capsule())
                    .accessibilityIdentifier("learning.purpose.\(word)")
                Text(priorityLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(WordShelfTheme.secondary)
                Spacer(minLength: 4)
                Menu {
                    Button("我想会用") { onPurpose(.use) }
                    Button("看懂即可") { onPurpose(.understand) }
                    Button("近期用不上") { onPurpose(.reference) }
                    Divider()
                    Button("恢复自动推荐") { onPurpose(nil) }
                } label: {
                    Label("调整", systemImage: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("调整学习用途：\(word)")
                .accessibilityIdentifier("learning.feedback.\(word)")
            }
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.reason)
                    if let scenario = recommendation.matchedScenario {
                        Text("相关场景：\(scenario)")
                    }
                    Text(recommendation.frequencyDescription)
                    Text(recommendation.confidenceDescription)
                }
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            } label: {
                Text(recommendation.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.secondary)
                    .lineLimit(1)
            }
            .accessibilityIdentifier("learning.reason.\(word)")
        }
        .foregroundStyle(WordShelfTheme.accent)
    }

    private var priorityLabel: String {
        if recommendation.purpose == .reference { return "暂不进入复习" }
        return recommendation.priority >= 70 ? "优先学习" : recommendation.priority >= 40 ? "随后学习" : "较低优先级"
    }
}

struct LearningProfileSheet: View {
    @ObservedObject var learning: LearningModel
    @Environment(\.dismiss) private var dismiss
    @State private var options: LearningProfileOptions
    @State private var attemptedSave = false
    @State private var goalsExpanded = false
    private let existingDomain: String?
    private let existingWork: [String]
    private let existingLife: [String]
    private let existingExpressions: [String]
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    init(learning: LearningModel) {
        self.learning = learning
        let initial = LearningProfileOptions(profile: learning.profile)
        _options = State(initialValue: initial)
        existingDomain = initial.legacyDomain
        existingWork = initial.legacyWork
        existingLife = initial.legacyLife
        existingExpressions = initial.legacyExpressions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("我的使用场景")
                    .font(.system(size: 22, weight: .semibold))
                Text("选几个常用场景即可，用途和频率可以按需调整。")
                    .font(.system(size: 12))
                    .foregroundStyle(WordShelfTheme.secondary)
            }
            .padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    domainSection
                    scenarioSection("工作场景", presets: LearningProfileCatalog.workScenarios, isWork: true)
                    scenarioSection("生活场景", presets: LearningProfileCatalog.lifeScenarios, isWork: false)
                    expressionSection
                    Text("至少选择一个工作或生活场景。无需逐条输入，保存后推荐会自动更新。")
                        .font(.system(size: 11))
                        .foregroundStyle(WordShelfTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 5)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
            if attemptedSave, let message = validationMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityIdentifier("learning.profile.validation")
            }
            if attemptedSave, validationMessage == nil, let error = learning.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("learning.profile.cancel")
                Spacer()
                Button("保存并更新推荐") {
                    attemptedSave = true
                    if validationMessage == nil, learning.saveProfile(options.makeProfile()) { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("learning.profile.save")
            }
            .padding(.top, 18)
        }
        .padding(26)
        .frame(width: 590, height: 650)
        .background(WordShelfTheme.canvas)
        .foregroundStyle(WordShelfTheme.ink)
        .tint(WordShelfTheme.accent)
        .environment(\.colorScheme, .light)
    }

    private var validationMessage: String? {
        options.validationMessage ?? options.makeProfile().validationMessage
    }

    private var domainSelection: Binding<String> {
        Binding(get: {
            options.domainID ?? (options.legacyDomain == nil ? "__none" : "__legacy")
        }, set: { value in
            if value == "__legacy" {
                options.domainID = nil
                options.legacyDomain = existingDomain
            } else {
                options.domainID = value == "__none" ? nil : value
                options.legacyDomain = nil
            }
        })
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("工作领域", detail: "可选，帮助识别专业表达")
            Picker("工作领域", selection: domainSelection) {
                Text("暂不指定").tag("__none")
                ForEach(LearningProfileCatalog.domains) { domain in
                    Text(domain.title).tag(domain.id)
                }
                if let existingDomain {
                    Text("已有：\(existingDomain)").tag("__legacy")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("工作领域")
            .accessibilityIdentifier("learning.profile.domain")
        }
    }

    private func scenarioSection(_ title: String, presets: [LearningScenarioPreset], isWork: Bool) -> some View {
        let choices = isWork ? $options.work : $options.life
        let existing = isWork ? existingWork : existingLife
        let selectedLegacy = isWork ? options.legacyWork : options.legacyLife
        let scope = isWork ? "work" : "life"
        let count = choices.wrappedValue.count + selectedLegacy.count
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel(title, detail: "最多选 3 个 · 已选 \(count)/3")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(presets) { preset in
                    let selected = choices.wrappedValue.contains { $0.presetID == preset.id }
                    choiceButton(preset.title, selected: selected, disabled: !selected && count >= 3,
                                 id: "learning.profile.\(scope).\(preset.id)") {
                        if selected { choices.wrappedValue.removeAll { $0.presetID == preset.id } }
                        else if count < 3 { choices.wrappedValue.append(preset.choice()) }
                    }
                }
            }
            if !existing.isEmpty {
                Text("已有自定义场景 · 保留勾选项")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WordShelfTheme.secondary)
                ForEach(Array(existing.enumerated()), id: \.offset) { index, text in
                    let selected = selectedLegacy.contains(text)
                    choiceButton(text, selected: selected, disabled: !selected && count >= 3,
                                 id: "learning.profile.\(scope).legacy.\(index)") {
                        if isWork { toggleLegacy(text, in: &options.legacyWork, selected: selected, limitReached: count >= 3) }
                        else { toggleLegacy(text, in: &options.legacyLife, selected: selected, limitReached: count >= 3) }
                    }
                }
            }
            ForEach(choices) { choice in
                let title = presets.first { $0.id == choice.wrappedValue.presetID }?.title ?? choice.wrappedValue.presetID
                ProfileScenarioConfigurationRow(choice: choice, title: title)
            }
            if count >= 3 {
                Text("已选满 3 个；取消一项后可以更换。")
                    .font(.system(size: 10))
                    .foregroundStyle(WordShelfTheme.secondary)
            }
        }
    }

    private var expressionSection: some View {
        let count = options.expressionIDs.count + options.legacyExpressions.count
        return DisclosureGroup(isExpanded: $goalsExpanded) {
            VStack(alignment: .leading, spacing: 9) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(LearningProfileCatalog.expressionGoals) { goal in
                        let selected = options.expressionIDs.contains(goal.id)
                        choiceButton(goal.title, selected: selected, disabled: !selected && count >= 5,
                                     id: "learning.profile.goal.\(goal.id)") {
                            if selected { options.expressionIDs.removeAll { $0 == goal.id } }
                            else if count < 5 { options.expressionIDs.append(goal.id) }
                        }
                    }
                }
                if !existingExpressions.isEmpty {
                    Text("已有表达目标 · 保留勾选项")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WordShelfTheme.secondary)
                    ForEach(Array(existingExpressions.enumerated()), id: \.offset) { index, text in
                        let selected = options.legacyExpressions.contains(text)
                        choiceButton(text, selected: selected, disabled: !selected && count >= 5,
                                     id: "learning.profile.goal.legacy.\(index)") {
                            toggleLegacy(text, in: &options.legacyExpressions, selected: selected, limitReached: count >= 5)
                        }
                    }
                }
                if count >= 5 {
                    Text("已选满 5 个；取消一项后可以更换。")
                        .font(.system(size: 10))
                        .foregroundStyle(WordShelfTheme.secondary)
                }
            }
            .padding(.top, 10)
        } label: {
            sectionLabel("想丰富的表达", detail: "可选 · 已选 \(count)/5")
        }
        .accessibilityIdentifier("learning.profile.goals")
    }

    private func sectionLabel(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 10)).foregroundStyle(WordShelfTheme.secondary)
        }
    }

    private func choiceButton(_ title: String, selected: Bool, disabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, 1)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(disabled ? WordShelfTheme.secondary.opacity(0.45) : selected ? WordShelfTheme.accent : WordShelfTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
            .background(selected ? WordShelfTheme.subtle : WordShelfTheme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? WordShelfTheme.accent.opacity(0.45) : WordShelfTheme.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选" : "未选")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
        .help(title)
    }

    private func toggleLegacy(_ text: String, in values: inout [String], selected: Bool, limitReached: Bool) {
        if selected { values.removeAll { $0 == text } }
        else if !limitReached { values.append(text) }
    }
}

private struct ProfileScenarioConfigurationRow: View {
    @Binding var choice: LearningScenarioChoice
    let title: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("学习用途").font(.system(size: 10)).foregroundStyle(WordShelfTheme.secondary)
                    Picker("学习用途", selection: useSelection) {
                        ForEach(LearningScenarioUse.allCases, id: \.rawValue) { use in
                            Text(use.title).tag(use.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("\(title)的学习用途")
                    .accessibilityIdentifier("learning.profile.use.\(choice.presetID)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text("使用频率").font(.system(size: 10)).foregroundStyle(WordShelfTheme.secondary)
                    Picker("使用频率", selection: frequencySelection) {
                        ForEach(LearningScenarioFrequency.allCases, id: \.rawValue) { frequency in
                            Text(frequency.title).tag(frequency.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("\(title)的使用频率")
                    .accessibilityIdentifier("learning.profile.frequency.\(choice.presetID)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 9)
        } label: {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 3)
                Text("\(choice.use.title) · \(choice.frequency.title)")
                    .font(.system(size: 10))
                    .foregroundStyle(WordShelfTheme.secondary)
            }
        }
        .font(.system(size: 11))
        .padding(10)
        .background(WordShelfTheme.subtle.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("learning.profile.configuration.\(choice.presetID)")
    }

    private var useSelection: Binding<String> {
        Binding(get: { choice.use.rawValue }, set: {
            if let value = LearningScenarioUse(rawValue: $0) { choice.use = value }
        })
    }

    private var frequencySelection: Binding<String> {
        Binding(get: { choice.frequency.rawValue }, set: {
            if let value = LearningScenarioFrequency(rawValue: $0) { choice.frequency = value }
        })
    }
}

struct LearningReviewView: View {
    @ObservedObject var learning: LearningModel
    @ObservedObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("把表达想起来")
                        .font(.system(size: 21, weight: .semibold))
                    Text(learning.reviewFinished ? "本轮已完成" : "第 \(min(learning.reviewIndex + 1, learning.reviewWords.count)) / \(learning.reviewWords.count) 条 · 对照参考自评")
                        .font(.system(size: 11))
                        .foregroundStyle(WordShelfTheme.secondary)
                }
                Spacer()
                Button("结束本轮") { close() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("learning.review.close")
            }
            .padding(.bottom, 22)

            ScrollView {
                if learning.reviewFinished {
                    finishedContent
                } else if let word = learning.currentReviewWord {
                    reviewContent(word: word)
                } else {
                    Text("当前没有需要复习的内容。")
                        .font(.system(size: 15))
                        .padding(.vertical, 36)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let error = learning.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            if !learning.reviewFinished, learning.currentReviewWord != nil {
                reviewActions
                    .padding(.top, 18)
            }
        }
        .padding(26)
        .frame(width: 590, height: 570)
        .background(WordShelfTheme.canvas)
        .foregroundStyle(WordShelfTheme.ink)
        .tint(WordShelfTheme.accent)
        .environment(\.colorScheme, .light)
        .onExitCommand { close() }
    }

    @ViewBuilder private func reviewContent(word: String) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if let purpose = learning.currentReviewPurpose {
                Text(purpose.title)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WordShelfTheme.subtle, in: Capsule())
            }
            if learning.currentReviewPurpose == .understand {
                Text(word)
                    .font(.system(size: 23, weight: .semibold))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("learning.review.original")
            }
            if learning.reviewIsLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在准备回忆提示…").font(.system(size: 12))
                }
                .foregroundStyle(WordShelfTheme.secondary)
            } else {
                Text(learning.reviewPrompt)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("learning.review.prompt")
                if let error = learning.reviewLoadError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(WordShelfTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("learning.review.loadError")
                    Button("重新准备提示") { learning.retryReview() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("learning.review.retry")
                }
            }
            if !learning.reviewRevealed {
                Text(learning.currentReviewPurpose == .use ? "先不看原文。你可以说出来，或写下一句自己的表达。" : "先回想它在这里的含义，也可以写下你的理解。")
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $learning.reviewAnswer)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 110)
                    .background(WordShelfTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(WordShelfTheme.border, lineWidth: 1)
                    }
                    .accessibilityLabel("我的回答，可选")
                    .accessibilityIdentifier("learning.review.answer")
            } else {
                referenceContent(word: word)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 5)
    }

    private func referenceContent(word: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(WordShelfTheme.border).frame(height: 1)
            Text("参考原文与释义")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WordShelfTheme.secondary)
            if learning.currentReviewPurpose != .understand {
                Text(word)
                    .font(.system(size: 22, weight: .semibold))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("learning.review.original")
            }
            Text(referenceBody(word: word))
                .font(.system(size: 13))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("learning.review.reference")
            if !learning.reviewAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("我的回答").font(.system(size: 10, weight: .semibold)).foregroundStyle(WordShelfTheme.secondary)
                    Text(learning.reviewAnswer)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WordShelfTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                reviewPronunciation(.british, word: word)
                reviewPronunciation(.american, word: word)
            }
            if app.pronunciationSource == .notebook(word), let error = app.pronunciationError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("对照参考，检查意思、搭配和语气，再选择本次表现。参考句式可以有多种。")
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reviewActions: some View {
        HStack(spacing: 9) {
            Button("跳过本条") {
                app.stopNotebookPronunciation()
                learning.skipReview()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(WordShelfTheme.secondary)
            .help("本次略过，不记录学习表现")
            .accessibilityIdentifier("learning.review.skip")
            if learning.reviewRevealed {
                ratingButton(.again, title: "想不起来")
                ratingButton(.hard, title: "需要提示")
                ratingButton(.good, title: learning.currentReviewPurpose == .understand ? "能独立理解" : "能独立表达")
            } else {
                Spacer()
                Button("查看参考") { learning.revealReview() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(learning.reviewIsLoading || learning.reviewLoadError != nil)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("learning.review.reveal")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func referenceBody(word: String) -> String {
        let prefix = word + "\n\n"
        return learning.reviewReference.hasPrefix(prefix)
            ? String(learning.reviewReference.dropFirst(prefix.count))
            : learning.reviewReference
    }

    private func ratingButton(_ rating: ReviewRating, title: String) -> some View {
        Button(title) {
            app.stopNotebookPronunciation()
            learning.rateReview(rating)
        }
        .buttonStyle(QuietButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("learning.review.rate.\(rating.rawValue)")
    }

    private func reviewPronunciation(_ accent: PronunciationAccent, word: String) -> some View {
        let playing = app.isPronouncing && app.pronunciationSource == .notebook(word) && app.playingAccent == accent
        return Button {
            app.pronounceSavedWord(word, accent: accent)
        } label: {
            Label(playing ? "\(accent.title)·停止" : accent.title, systemImage: playing ? "stop.fill" : "speaker.wave.2")
                .frame(minWidth: 74)
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel("\(playing ? "停止" : "播放")\(accent.title)发音")
        .accessibilityIdentifier("learning.review.pronounce.\(accent.rawValue)")
    }

    private var finishedContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 35, weight: .light))
                .foregroundStyle(WordShelfTheme.accent)
                .accessibilityHidden(true)
            Text("本轮回想了 \(learning.reviewCompleted) 条")
                .font(.system(size: 22, weight: .semibold))
                .accessibilityIdentifier("learning.review.completed")
            Text("接下来让表达回到你的工作和生活里。系统会根据本次表现安排再次回想。")
                .font(.system(size: 13))
                .foregroundStyle(WordShelfTheme.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let date = learning.nextDueDate {
                Text("下次复习：\(date.formatted(.dateTime.locale(Locale(identifier: "zh_Hans_CN")).year().month().day()))")
                    .font(.system(size: 12, weight: .medium))
            }
            Button("回到生词本") { close() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 9)
                .accessibilityIdentifier("learning.review.done")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 28)
    }

    private func close() {
        learning.endReview()
        app.stopNotebookPronunciation()
        dismiss()
    }
}
