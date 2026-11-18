import AppKit
import SwiftUI
import WordShelfCore

struct LookupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 19)

            queryField

            HStack(spacing: 8) {
                Text("Enter 查译 · Shift Enter 换行")
                    .lineLimit(1)
                Spacer(minLength: 0)
                if model.query.count > 3000 {
                    Text("\(model.query.count) / 4000")
                        .foregroundStyle(model.query.count > 4000 ? WordShelfTheme.warning : WordShelfTheme.secondary)
                        .fixedSize()
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(WordShelfTheme.secondary)
            .padding(.top, 6)

            if let message = model.captureMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }

            definitionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 17)

            footer
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 460)
        .background(WordShelfTheme.canvas)
        .foregroundStyle(WordShelfTheme.ink)
        .tint(WordShelfTheme.accent)
        .environment(\.colorScheme, .light)
        .onExitCommand { model.dismissPopup() }
    }

    private var pronunciationControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                pronunciationButton(.british)
                pronunciationButton(.american)
            }
            if model.pronunciationSource == .lookup, let message = model.pronunciationError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lookup.pronunciationError")
            }
        }
    }

    private func pronunciationButton(_ accent: PronunciationAccent) -> some View {
        let isPlaying = model.isPronouncing && model.pronunciationSource == .lookup && model.playingAccent == accent
        let isEnabled = model.canPronounce || isPlaying
        return Button { model.pronounce(accent) } label: {
            Label(isPlaying ? "\(accent.title)·停止" : accent.title, systemImage: isPlaying ? "stop.fill" : "speaker.wave.2")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 106, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .background(isPlaying ? WordShelfTheme.accent : WordShelfTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isPlaying ? WordShelfTheme.accent : WordShelfTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPlaying ? Color.white : isEnabled ? WordShelfTheme.accent : WordShelfTheme.secondary.opacity(0.55))
        .disabled(!isEnabled)
        .help(isPlaying ? "停止\(accent.title)朗读当前英文原文" : "使用\(accent.title)系统语音朗读当前英文原文")
        .accessibilityLabel("\(isPlaying ? "停止" : "播放")\(accent.title)发音")
        .accessibilityIdentifier(accent == .british ? "lookup.pronounce.british" : "lookup.pronounce.american")
    }

    private var hasCurrentQuery: Bool {
        !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentOriginalPronunciation: some View {
        let original = SelectionText.normalize(model.query) ?? model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Text("当前英文原文")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WordShelfTheme.secondary)
            if isSingleWord(original) {
                Text(original)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                ScrollView {
                    Text(original)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.trailing, 3)
                }
                .frame(maxHeight: 72)
            }
            pronunciationControls
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            WordShelfMark(size: 27)
            Text("拾用")
                .font(.system(size: 16, weight: .semibold))
            Text("英 → 中")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WordShelfTheme.secondary)
            Spacer()
            Button { model.showNotebook() } label: {
                Label("生词本", systemImage: "books.vertical")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WordShelfTheme.secondary)
            .accessibilityIdentifier("lookup.notebook")

            Button { model.dismissPopup() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 25, height: 25)
                    .background(WordShelfTheme.border.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WordShelfTheme.secondary)
            .help("关闭（Esc）")
            .accessibilityLabel("关闭查译浮窗")
            .accessibilityIdentifier("lookup.close")
        }
    }

    private var queryField: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(WordShelfTheme.secondary)
                .padding(.top, 6)
            ZStack(alignment: .topLeading) {
                if model.query.isEmpty {
                    Text("输入英文单词、短语或句子")
                        .font(.system(size: 14))
                        .foregroundStyle(WordShelfTheme.secondary.opacity(0.7))
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
                LookupQueryEditor(text: $model.query, onSubmit: { model.lookup() }, onCancel: { model.dismissPopup() })
                    .frame(height: 62)
            }
            Button { model.lookup() } label: {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 25, height: 25)
                    .background(WordShelfTheme.subtle, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WordShelfTheme.accent)
            .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("英译中（Enter 或 ⌘Return）")
            .accessibilityLabel("查译")
            .accessibilityIdentifier("lookup.submit")
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WordShelfTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(WordShelfTheme.border, lineWidth: 1)
        }
    }

    @ViewBuilder private var definitionContent: some View {
        switch model.lookupState {
        case .idle:
            VStack(alignment: .leading, spacing: 12) {
                if hasCurrentQuery {
                    currentOriginalPronunciation
                    Text("按 Enter 查译当前原文")
                        .font(.system(size: 12))
                        .foregroundStyle(WordShelfTheme.secondary)
                } else {
                    Text("随手查，轻轻收。")
                        .font(.system(size: 23, weight: .medium))
                    Text("单词、短语或整句，都能英译中。\n想留下的，就收藏原文。")
                        .font(.system(size: 13))
                        .foregroundStyle(WordShelfTheme.secondary)
                        .lineSpacing(5)
                }
                if !model.permissionGranted {
                    permissionHint
                        .padding(.top, 8)
                }
            }
        case .loading:
            VStack(alignment: .leading, spacing: 14) {
                if hasCurrentQuery {
                    currentOriginalPronunciation
                }
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.isPreparingTranslation ? "正在准备英汉翻译…" : "正在查译…")
                        .font(.system(size: 13))
                        .foregroundStyle(WordShelfTheme.secondary)
                }
            }
        case .found(let entry):
            if SelectionText.normalize(model.query) == entry.word {
                entryContent(entry)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if hasCurrentQuery {
                        currentOriginalPronunciation
                    }
                    Text("按 Enter 查译当前原文")
                        .font(.system(size: 12))
                        .foregroundStyle(WordShelfTheme.secondary)
                }
            }
        case .failed(let message):
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    if hasCurrentQuery {
                        currentOriginalPronunciation
                    }
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(WordShelfTheme.secondary)
                        .accessibilityHidden(true)
                    Text("暂未完成查译")
                        .font(.system(size: 17, weight: .medium))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(WordShelfTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.translationSetupRequired {
                        translationSetup
                    }
                    if model.canSaveCurrentWord {
                        Text("也可以先收藏原文，稍后再查译。")
                            .font(.system(size: 12))
                            .foregroundStyle(WordShelfTheme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func entryContent(_ entry: DictionaryEntry) -> some View {
        let singleWord = isSingleWord(entry.word)
        return VStack(alignment: .leading, spacing: 10) {
            if singleWord {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.word)
                        .font(.system(size: 26, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let phonetic = entry.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.system(size: 12))
                            .foregroundStyle(WordShelfTheme.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                Text("英文原文")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WordShelfTheme.secondary)
                ScrollView {
                    Text(entry.word)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.trailing, 3)
                }
                .frame(maxHeight: 92)
                .accessibilityIdentifier("lookup.original")
            }

            pronunciationControls

            Rectangle()
                .fill(WordShelfTheme.border.opacity(0.7))
                .frame(height: 1)
            Text(singleWord ? "中文释义" : "中文译文")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WordShelfTheme.accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(entry.definitions.enumerated()), id: \.offset) { _, definition in
                        VStack(alignment: .leading, spacing: 4) {
                            if let partOfSpeech = definition.partOfSpeech, !partOfSpeech.isEmpty {
                                Text(partOfSpeech)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(WordShelfTheme.accent)
                            }
                            Text(definition.text)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .accessibilityIdentifier("lookup.translation")

            Text(entry.sourceName)
                .font(.system(size: 10))
                .foregroundStyle(WordShelfTheme.secondary.opacity(0.8))
        }
    }

    @ViewBuilder private var translationSetup: some View {
        if #available(macOS 15.0, *) {
            VStack(alignment: .leading, spacing: 8) {
                Button { model.prepareTranslation() } label: {
                    HStack(spacing: 7) {
                        if model.isPreparingTranslation {
                            ProgressView().controlSize(.mini)
                        }
                        Text(model.isPreparingTranslation ? "正在准备翻译…" : "启用句子翻译")
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.isPreparingTranslation)
                .accessibilityIdentifier("lookup.prepareTranslation")
                Text("首次使用可能需要下载英语和中文语言包，请按系统提示完成。")
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("句子翻译需要 macOS 15 或更新版本。当前仍可查询词典和收藏原文。")
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isSingleWord(_ text: String) -> Bool {
        text.count <= 36 && text.range(
            of: "^[\\p{Latin}][\\p{Latin}0-9]*(?:[-'’][\\p{Latin}0-9]+)*$",
            options: .regularExpression
        ) != nil
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开启辅助功能权限，即可读取选中的英文内容。现在也可以直接输入查译。")
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("开启划词查译") { model.requestAccessibility() }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("lookup.permission")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.accent)
                    .lineLimit(2)
                    .accessibilityIdentifier("lookup.notice")
            }
            if let shortcutMessage = model.shortcutMessage {
                Text(shortcutMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .lineLimit(2)
            }
            Rectangle()
                .fill(WordShelfTheme.border.opacity(0.7))
                .frame(height: 1)
            HStack(spacing: 7) {
                ShortcutKey(text: "esc")
                Text("回到阅读")
                    .font(.system(size: 10))
                    .foregroundStyle(WordShelfTheme.secondary)
                Spacer()
                Button { model.saveCurrentWord() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: model.currentWordIsSaved ? "checkmark" : "bookmark")
                        Text(model.currentWordIsSaved ? "已收藏" : "收藏原文")
                        Text("⌘S")
                            .font(.system(size: 10))
                            .opacity(0.7)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canSaveCurrentWord || model.currentWordIsSaved)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("lookup.save")
            }
        }
        .padding(.top, 15)
    }
}

/// Native text input keeps pasted paragraphs intact and makes the return-key
/// behavior explicit: Return submits, Shift-Return inserts a line break.
private struct LookupQueryEditor: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let editor = QueryTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 62))
        editor.delegate = context.coordinator
        editor.string = text
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = NSColor(red: 0.17, green: 0.23, blue: 0.20, alpha: 1)
        editor.insertionPointColor = NSColor(red: 0.20, green: 0.37, blue: 0.29, alpha: 1)
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 62)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 0, height: 3)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.onSubmit = onSubmit
        editor.onCancel = onCancel
        editor.setAccessibilityLabel("输入英文单词、短语或句子")
        editor.setAccessibilityIdentifier("lookup.query")
        scrollView.documentView = editor

        DispatchQueue.main.async {
            guard let window = editor.window else { return }
            window.makeFirstResponder(editor)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scrollView.documentView as? QueryTextView else { return }
        editor.onSubmit = onSubmit
        editor.onCancel = onCancel
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
            editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LookupQueryEditor

        init(_ parent: LookupQueryEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private final class QueryTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Leave Return/Esc to the input method while it is composing text.
        if !hasMarkedText() {
            if event.keyCode == 36 || event.keyCode == 76 {
                if event.modifierFlags.contains(.shift) {
                    insertNewline(nil)
                } else {
                    onSubmit?()
                }
                return
            }
            if event.keyCode == 53 {
                onCancel?()
                return
            }
        }
        super.keyDown(with: event)
    }
}
