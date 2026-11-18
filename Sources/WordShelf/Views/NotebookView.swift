import SwiftUI
import WordShelfCore

struct NotebookView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var learning: LearningModel
    @State private var search = ""
    @State private var isProfilePresented = false
    @State private var isReviewPresented = false

    init(model: AppModel) {
        self.model = model
        self.learning = model.learning
    }

    private var filteredWords: [String] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? model.words : model.words.filter { $0.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 22)

            HStack(alignment: .firstTextBaseline) {
                Text("生词本")
                    .font(.system(size: 29, weight: .semibold))
                Text("\(model.words.count) 条收藏")
                    .font(.system(size: 12))
                    .foregroundStyle(WordShelfTheme.secondary)
                Spacer()
                searchField
                    .frame(width: 230)
            }
            .padding(.bottom, 18)

            LearningNotebookSummary(learning: learning, onProfile: {
                isProfilePresented = true
            }, onReview: {
                model.stopNotebookPronunciation()
                learning.startReview()
                isReviewPresented = true
            })
            .padding(.bottom, 14)

            if model.words.isEmpty {
                emptyNotebook
            } else if filteredWords.isEmpty {
                emptySearch
            } else {
                wordList
            }

            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(minWidth: 660, minHeight: 450)
        .background(WordShelfTheme.canvas)
        .foregroundStyle(WordShelfTheme.ink)
        .tint(WordShelfTheme.accent)
        .environment(\.colorScheme, .light)
        .onChange(of: search) { _, _ in
            model.stopNotebookPronunciation()
        }
        .sheet(isPresented: $isProfilePresented) {
            LearningProfileSheet(learning: learning)
        }
        .sheet(isPresented: $isReviewPresented, onDismiss: {
            learning.endReview()
            model.stopNotebookPronunciation()
        }) {
            LearningReviewView(learning: learning, app: model)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            WordShelfMark(size: 35)
            VStack(alignment: .leading, spacing: 2) {
                Text("拾用")
                    .font(.system(size: 17, weight: .semibold))
                Text("USELEAF")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(WordShelfTheme.secondary)
            }
            Spacer()
            Button { model.exportWords() } label: {
                Label("导出原文", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.words.isEmpty)
            .opacity(model.words.isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("notebook.export")
            Button { model.showManualLookup() } label: {
                Label("查译", systemImage: "magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("notebook.newLookup")
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(WordShelfTheme.secondary)
            TextField("搜索单词、短语或句子", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel("搜索生词本")
                .accessibilityIdentifier("notebook.search")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WordShelfTheme.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(WordShelfTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(WordShelfTheme.border, lineWidth: 1)
        }
    }

    private var wordList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredWords, id: \.self) { word in
                    SavedWordRow(
                        word: word,
                        playingAccent: model.isPronouncing && model.pronunciationSource == .notebook(word) ? model.playingAccent : nil,
                        pronunciationError: model.pronunciationSource == .notebook(word) ? model.pronunciationError : nil,
                        recommendation: learning.recommendations[word],
                        onPurpose: { purpose in
                            learning.setPurpose(purpose, for: word)
                        },
                        onPronounce: { accent in
                            model.pronounceSavedWord(word, accent: accent)
                        },
                        onLookup: {
                            model.showManualLookup()
                            model.lookup(word)
                        },
                        onRemove: {
                            model.removeWord(word)
                        }
                    )
                }
            }
            .padding(.top, 1)
            .padding(.bottom, 14)
            .padding(.trailing, 2)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("notebook.words")
    }

    private var emptyNotebook: some View {
        VStack(spacing: 13) {
            Image(systemName: "bookmark")
                .font(.system(size: 37, weight: .ultraLight))
                .foregroundStyle(WordShelfTheme.accent)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text("从遇见的英文开始")
                .font(.system(size: 19, weight: .medium))
            Text("选中单词、短语或句子，按 ⌃⌥D 查译。\n收藏时只留下原文。")
                .font(.system(size: 12))
                .foregroundStyle(WordShelfTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
            Button("开始查译") { model.showManualLookup() }
                .buttonStyle(QuietButtonStyle())
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearch: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(WordShelfTheme.secondary)
                .accessibilityHidden(true)
            Text("没有匹配的收藏")
                .font(.system(size: 17, weight: .medium))
            Button("查看全部收藏") { search = "" }
                .buttonStyle(QuietButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            Rectangle()
                .fill(WordShelfTheme.border.opacity(0.7))
                .frame(height: 1)

            if let shortcutMessage = model.shortcutMessage {
                Text(shortcutMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let notice = model.notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(WordShelfTheme.accent)
                        .lineLimit(2)
                        .accessibilityIdentifier("notebook.notice")
                } else {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                    Text("划词后按 ⌃⌥D，随时英译中")
                        .font(.system(size: 11))
                }

                if model.canUndoRemoval {
                    Button("撤销删除") { model.undoRemoval() }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(WordShelfTheme.accent)
                        .accessibilityIdentifier("notebook.undo")
                }

                Spacer(minLength: 10)
                if !model.permissionGranted {
                    Button("开启划词查译") { model.requestAccessibility() }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(WordShelfTheme.accent)
                        .accessibilityIdentifier("notebook.permission")
                }
            }
            .foregroundStyle(WordShelfTheme.secondary)
        }
        .padding(.top, 16)
    }
}

private struct SavedWordRow: View {
    let word: String
    let playingAccent: PronunciationAccent?
    let pronunciationError: String?
    let recommendation: LearningRecommendation?
    let onPurpose: (LearningPurpose?) -> Void
    let onPronounce: (PronunciationAccent) -> Void
    let onLookup: () -> Void
    let onRemove: () -> Void
    @State private var hovered = false

    private var isLongEntry: Bool { word.count > 70 || word.contains("\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button(action: onLookup) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(word)
                                .font(.system(size: 15, weight: .medium))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(4)
                                .lineLimit(isLongEntry ? 3 : 2)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if isLongEntry {
                                Text("点击查看完整原文并查译")
                                    .font(.system(size: 10))
                                    .foregroundStyle(WordShelfTheme.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WordShelfTheme.secondary)
                            .opacity(hovered ? 1 : 0.45)
                    }
                    .padding(.leading, 17)
                    .padding(.trailing, 11)
                    .padding(.top, 15)
                    .padding(.bottom, 11)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("查看完整原文并查译")
                .accessibilityLabel("查译 \(word)")
                .accessibilityIdentifier("word.\(word)")

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(WordShelfTheme.secondary)
                        .frame(width: 30, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help("删除这条收藏")
                .accessibilityLabel("删除 \(word)")
                .accessibilityIdentifier("delete.\(word)")
            }

            if let recommendation {
                LearningRecommendationView(word: word, recommendation: recommendation, onPurpose: onPurpose)
                    .padding(.horizontal, 17)
                    .padding(.bottom, 11)
            }

            HStack(spacing: 8) {
                pronunciationButton(.british)
                pronunciationButton(.american)
            }
            .padding(.horizontal, 17)
            .padding(.bottom, pronunciationError == nil ? 13 : 7)

            if let pronunciationError {
                Text(pronunciationError)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 17)
                    .padding(.bottom, 13)
                    .accessibilityIdentifier("notebook.pronunciationError.\(word)")
            }
        }
        .background(hovered ? WordShelfTheme.subtle.opacity(0.6) : WordShelfTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(hovered ? WordShelfTheme.accent.opacity(0.3) : WordShelfTheme.border.opacity(0.85), lineWidth: 1)
        }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("查看原文并查译", action: onLookup)
            Divider()
            Button("删除收藏", action: onRemove)
        }
    }

    private func pronunciationButton(_ accent: PronunciationAccent) -> some View {
        let isPlaying = playingAccent == accent
        return Button { onPronounce(accent) } label: {
            Label(isPlaying ? "\(accent.title)·停止" : accent.title, systemImage: isPlaying ? "stop.fill" : "speaker.wave.2")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 106, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .background(isPlaying ? WordShelfTheme.accent : WordShelfTheme.subtle.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isPlaying ? WordShelfTheme.accent : WordShelfTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPlaying ? Color.white : WordShelfTheme.accent)
        .help(isPlaying ? "停止\(accent.title)朗读这条收藏原文" : "使用\(accent.title)系统语音朗读这条收藏原文")
        .accessibilityLabel("\(isPlaying ? "停止" : "播放")\(accent.title)发音：\(word)")
        .accessibilityIdentifier("notebook.pronounce.\(accent == .british ? "british" : "american").\(word)")
    }
}
