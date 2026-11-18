import SwiftUI
import WordShelfCore

/// A temporary menu-bar surface for finding and reusing saved originals.
/// It never changes the lookup popup's query or the user's learning purpose.
struct SavedExpressionsView: View {
    @ObservedObject var model: AppModel
    let onCopy: (String) -> Void
    let onClose: () -> Void
    let onMore: () -> Void
    var onSizeChange: (CGSize) -> Void = { _ in }

    @StateObject private var detail = SavedExpressionDetailModel()
    @State private var search = ""
    @State private var selected: String?
    @State private var accent: PronunciationAccent = .american
    @State private var retryID = UUID()
    @State private var resultHeight: CGFloat = 150
    @State private var allMeanings = false
    @FocusState private var searchFocused: Bool

    private var filteredWords: [String] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? model.words : model.words.filter { $0.localizedCaseInsensitiveContains(term) }
    }

    private var definitionRequest: FinderDefinitionRequest {
        FinderDefinitionRequest(word: selected, retryID: retryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            resultList
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("finder.notice")
            }
            footer
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(WordShelfTheme.surface)
        .foregroundStyle(WordShelfTheme.ink)
        .tint(WordShelfTheme.accent)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: FinderPanelSizeKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(FinderPanelSizeKey.self) { size in
            if size.width > 0, size.height > 0 { onSizeChange(size) }
        }
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onClose)
        .onChange(of: search) { _, _ in updateSearchSelection() }
        .onChange(of: model.words) { _, _ in
            model.stopNotebookPronunciation()
            detail.clear()
            let matches = filteredWords
            if let selected, !matches.contains(selected) { self.selected = nil }
            if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, matches.count == 1 {
                selected = matches.first
            }
            retryID = UUID()
        }
        .onChange(of: accent) { _, _ in model.stopNotebookPronunciation() }
        .task(id: definitionRequest) {
            await detail.load(selected) { word in
                try await model.savedDefinition(for: word)
            }
        }
        .onDisappear {
            detail.clear()
            model.stopNotebookPronunciation()
        }
    }

    private var header: some View {
        HStack {
            Text("找回收藏")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WordShelfTheme.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WordShelfTheme.secondary)
            .accessibilityLabel("关闭收藏，回到原应用")
            .accessibilityIdentifier("finder.close")
            .help("关闭（Esc）")
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(WordShelfTheme.secondary)
                .accessibilityHidden(true)
            TextField("搜索收藏的英文", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .accessibilityLabel("搜索收藏的英文")
                .accessibilityIdentifier("finder.search")
            if !search.isEmpty {
                Button {
                    search = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(WordShelfTheme.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
                .accessibilityIdentifier("finder.clearSearch")
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
        .padding(.horizontal, 16)
        .padding(.bottom, 9)
    }

    private var resultList: some View {
        ScrollView {
            VStack(spacing: 2) {
                if let error = model.store.loadError {
                    emptyState("收藏暂时无法读取", message: error)
                } else if model.words.isEmpty {
                    emptyState("还没有收藏", message: "划词后按 ⌃⌥D，留下想用的英文。")
                } else if filteredWords.isEmpty {
                    emptyState("没找到", message: "试试更短的英文片段。")
                } else {
                    ForEach(filteredWords, id: \.self) { word in
                        expressionRow(word)
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { updateResultHeight(geometry.size.height) }
                        .onChange(of: geometry.size.height) { _, height in updateResultHeight(height) }
                }
            }
        }
        .frame(height: min(max(resultHeight, 100), 340))
        .scrollIndicators(.automatic)
        .accessibilityIdentifier("finder.results")
    }

    private func emptyState(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(WordShelfTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expressionRow(_ word: String) -> some View {
        let isSelected = selected == word
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                model.stopNotebookPronunciation()
                detail.clear()
                allMeanings = false
                selected = isSelected ? nil : word
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(word)
                        .font(.system(size: 15))
                        .lineLimit(isSelected ? nil : 2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WordShelfTheme.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(word)
            .accessibilityValue(isSelected ? "已展开" : "未展开")
            .accessibilityHint("查看释义、发音或复制原文")
            .accessibilityIdentifier("finder.word.\(word)")

            if isSelected {
                VStack(alignment: .leading, spacing: 13) {
                    definitionContent
                    expressionActions(word)
                    if model.pronunciationSource == .notebook(word), let message = model.pronunciationError {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(WordShelfTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("finder.pronunciationError")
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 12)
            }
        }
        .background(isSelected ? WordShelfTheme.canvas : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder private var definitionContent: some View {
        switch detail.state {
        case .idle, .loading:
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text("正在查译…")
                    .font(.system(size: 12))
                    .foregroundStyle(WordShelfTheme.secondary)
            }
            .accessibilityIdentifier("finder.loading")
        case .found(let entry):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array((allMeanings ? entry.definitions : Array(entry.definitions.prefix(2))).enumerated()), id: \.offset) { _, definition in
                    Text([definition.partOfSpeech, definition.text].compactMap { $0 }.joined(separator: " "))
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(WordShelfTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if !allMeanings, entry.definitions.count > 2 {
                    Button("更多释义") { allMeanings = true }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(WordShelfTheme.accent)
                        .accessibilityIdentifier("finder.moreDefinitions")
                }
            }
            .accessibilityIdentifier("finder.definition")
        case .failed(let message, let needsLanguages):
            VStack(alignment: .leading, spacing: 7) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(WordShelfTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("重试") { retryID = UUID() }
                        .accessibilityIdentifier("finder.retry")
                    if needsLanguages {
                        Button("管理翻译语言…", action: onMore)
                            .accessibilityIdentifier("finder.translationSettings")
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(WordShelfTheme.accent)
            }
            .accessibilityIdentifier("finder.definitionError")
        }
    }

    private func expressionActions(_ word: String) -> some View {
        let isPlaying = model.isPronouncing && model.pronunciationSource == .notebook(word) && model.playingAccent == accent
        return HStack(spacing: 3) {
            Button { model.pronounceSavedWord(word, accent: accent) } label: {
                Label(isPlaying ? "停止" : "发音", systemImage: isPlaying ? "stop.fill" : "speaker.wave.2")
                    .font(.system(size: 12))
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isPlaying ? "停止" : "播放")\(accent.title)发音：\(word)")
            .accessibilityIdentifier("finder.pronounce")
            Picker("发音口音", selection: $accent) {
                ForEach(PronunciationAccent.allCases, id: \.self) { option in
                    Text(option == .american ? "美音" : "英音").tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.mini)
            .frame(width: 59)
            .accessibilityIdentifier("finder.accent")
            Spacer(minLength: 8)
            Button { onCopy(word) } label: {
                Label("复制原文", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(WordShelfTheme.onAccent)
                    .background(WordShelfTheme.accent, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("finder.copy")
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .frame(width: 25, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("管理收藏与设置")
            .accessibilityLabel("管理收藏与设置")
            .accessibilityIdentifier("finder.more")
            Spacer()
            Text("Esc 回到原应用")
                .font(.system(size: 11))
        }
        .foregroundStyle(WordShelfTheme.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
    }

    private func updateSearchSelection() {
        model.stopNotebookPronunciation()
        let matches = filteredWords
        let nextSelection = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && matches.count == 1 ? matches.first : nil
        guard selected != nextSelection else { return }
        detail.clear()
        allMeanings = false
        selected = nextSelection
    }

    private func updateResultHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        let fitted = ceil(height)
        if resultHeight != fitted { resultHeight = fitted }
    }
}

private struct FinderDefinitionRequest: Hashable {
    let word: String?
    let retryID: UUID
}

private struct FinderPanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
