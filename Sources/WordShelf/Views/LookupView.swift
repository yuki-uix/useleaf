import AppKit
import SwiftUI
import WordShelfCore

/// A momentary reading aid. Input and full dictionary detail stay available,
/// while the first view only contains the selected original and useful meaning.
struct LookupView: View {
    @ObservedObject var model: AppModel
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var isEditing = false
    @State private var showsMore = false
    @State private var selectedAccent: PronunciationAccent = .american

    private var original: String {
        SelectionText.normalize(model.query) ?? model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsEditor: Bool { isEditing || model.lookupWord == nil }

    private var currentEntry: DictionaryEntry? {
        guard case .found(let entry) = model.lookupState, original == entry.word else { return nil }
        return entry
    }

    private var isPlaying: Bool {
        model.isPronouncing && model.pronunciationSource == .lookup && model.playingAccent == selectedAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsEditor {
                editingHeader
                queryField.padding(.top, 12)
                Text("Enter 查译 · Shift Enter 换行")
                    .font(.system(size: 10))
                    .foregroundStyle(WordShelfTheme.secondary)
                    .padding(.top, 6)
            } else {
                originalHeader
            }

            if let message = model.captureMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            definitionContent.padding(.top, showsEditor ? 14 : 8)
            actions.padding(.top, 18)
            messages
            Button { model.dismissPopup() } label: {
                Text("Esc 继续阅读")
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WordShelfTheme.secondary)
            .padding(.top, 10)
            .accessibilityIdentifier("lookup.returnToReading")
        }
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .padding(.bottom, 12)
        .frame(width: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(WordShelfTheme.surface)
        .foregroundStyle(WordShelfTheme.ink)
        .tint(WordShelfTheme.accent)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: LookupSizePreferenceKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(LookupSizePreferenceKey.self) { size in
            guard size.width > 0, size.height > 0 else { return }
            onSizeChange(size)
        }
        .onChange(of: model.lookupWord) { _, _ in
            isEditing = false
            showsMore = false
        }
        .onChange(of: model.lookupState) { _, state in
            if case .loading = state {
                isEditing = false
                showsMore = false
            }
        }
        .onChange(of: selectedAccent) { _, _ in
            if model.pronunciationSource == .lookup { model.stopPronunciation() }
        }
        .onExitCommand { model.dismissPopup() }
    }

    private var closeButton: some View {
        Button { model.dismissPopup() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WordShelfTheme.secondary)
        .help("关闭，继续阅读（Esc）")
        .accessibilityLabel("关闭查译浮窗")
        .accessibilityIdentifier("lookup.close")
    }

    private var editingHeader: some View {
        HStack {
            Text("查译").font(.system(size: 15, weight: .medium))
            Spacer()
            if let lookupWord = model.lookupWord {
                Button("取消编辑") {
                    model.query = lookupWord
                    isEditing = false
                }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(WordShelfTheme.secondary)
            }
            closeButton
        }
    }

    private var originalHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                LookupCappedContent(maximumHeight: 110) {
                    Text(original)
                        .font(.system(size: original.count <= 55 && !original.contains("\n") ? 23 : 15, weight: .medium))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("lookup.original")
                Button { isEditing = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WordShelfTheme.secondary)
                .help("编辑原文")
                .accessibilityLabel("编辑原文")
                .accessibilityIdentifier("lookup.edit")
                closeButton
            }
            if let phonetic = currentEntry?.phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(.system(size: 11))
                    .foregroundStyle(WordShelfTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var queryField: some View {
        HStack(alignment: .top, spacing: 7) {
            ZStack(alignment: .topLeading) {
                if model.query.isEmpty {
                    Text("输入英文单词、短语或句子")
                        .font(.system(size: 13))
                        .foregroundStyle(WordShelfTheme.secondary)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
                LookupQueryEditor(text: $model.query, onSubmit: { model.lookup() }, onCancel: { model.dismissPopup() })
                    .frame(height: 65)
            }
            Button { model.lookup() } label: {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 25, height: 25)
                    .background(WordShelfTheme.subtle, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("查译（Enter 或 ⌘Return）")
            .accessibilityLabel("查译")
            .accessibilityIdentifier("lookup.submit")
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(10)
        .background(WordShelfTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(WordShelfTheme.border, lineWidth: 0.5) }
    }

    @ViewBuilder private var definitionContent: some View {
        switch model.lookupState {
        case .idle:
            if !model.permissionGranted { permissionHint }
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在查译…")
                    .font(.system(size: 12))
                    .foregroundStyle(WordShelfTheme.secondary)
            }
        case .found(let entry):
            if original == entry.word {
                definition(entry)
            } else {
                pendingQueryHint
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 9) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(WordShelfTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.translationSetupRequired { translationSetup }
                if model.canSaveCurrentWord {
                    Text("仍可收藏原文。")
                        .font(.system(size: 11))
                        .foregroundStyle(WordShelfTheme.secondary)
                }
            }
        }
    }

    private var pendingQueryHint: some View {
        Text("按 Enter 查译修改后的原文")
            .font(.system(size: 12))
            .foregroundStyle(WordShelfTheme.secondary)
    }

    private func definition(_ entry: DictionaryEntry) -> some View {
        let hasMore = entry.definitions.count > 1 || (entry.definitions.first?.text.count ?? 0) > 60 || entry.definitions.first?.text.contains("\n") == true
        return VStack(alignment: .leading, spacing: 7) {
            if showsMore {
                LookupCappedContent(maximumHeight: 210) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(entry.definitions.enumerated()), id: \.offset) { _, item in
                            definitionText(item)
                        }
                        Text(entry.sourceName)
                            .font(.system(size: 10))
                            .foregroundStyle(WordShelfTheme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                }
                .accessibilityIdentifier("lookup.translation")
            } else if let first = entry.definitions.first {
                definitionText(first, compact: true)
                    .accessibilityIdentifier("lookup.translation")
            } else {
                Text("暂未找到释义，仍可收藏原文。")
                    .font(.system(size: 12))
                    .foregroundStyle(WordShelfTheme.secondary)
            }
            if hasMore {
                Button { showsMore.toggle() } label: {
                    HStack(spacing: 4) {
                        Text(showsMore ? "收起释义" : "更多释义")
                        Image(systemName: showsMore ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WordShelfTheme.secondary)
                .accessibilityIdentifier("lookup.moreDefinitions")
            }
        }
    }

    private func definitionText(_ definition: DictionaryDefinition, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let part = definition.partOfSpeech, !part.isEmpty {
                Text(part)
                    .font(.system(size: 10))
                    .foregroundStyle(WordShelfTheme.secondary)
            }
            Text(definition.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .lineLimit(compact ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 3) {
                Button { model.pronounce(selectedAccent) } label: {
                    Label(isPlaying ? "停止" : "发音", systemImage: isPlaying ? "stop.fill" : "speaker.wave.2")
                        .font(.system(size: 12))
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canPronounce && !isPlaying)
                .help("朗读当前英文原文")
                .accessibilityLabel("\(isPlaying ? "停止" : "播放")\(selectedAccent.title)发音")
                .accessibilityIdentifier("lookup.pronounce")
                Picker("发音口音", selection: $selectedAccent) {
                    Text("美音").tag(PronunciationAccent.american)
                    Text("英音").tag(PronunciationAccent.british)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 58)
                .accessibilityIdentifier("lookup.accent")
            }
            Spacer(minLength: 0)
            Button { model.saveCurrentWord() } label: {
                HStack(spacing: 5) {
                    if let confirmation = model.currentSaveConfirmation {
                        CompactSaveMascot(confirmation: confirmation).id(confirmation.id)
                    } else {
                        Image(systemName: model.currentWordIsSaved ? "checkmark" : "bookmark")
                    }
                    Text(model.currentWordIsSaved ? "已收藏" : "收藏原文")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(model.currentWordIsSaved ? WordShelfTheme.subtle : WordShelfTheme.accent, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(model.currentWordIsSaved ? WordShelfTheme.accent : WordShelfTheme.onAccent)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(LookupSaveButtonStyle())
            .disabled(!model.canSaveCurrentWord || model.currentWordIsSaved)
            .keyboardShortcut("s", modifiers: .command)
            .help("收藏原文（⌘S）")
            .accessibilityIdentifier("lookup.save")
        }
    }

    @ViewBuilder private var messages: some View {
        if model.pronunciationSource == .lookup, let error = model.pronunciationError {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .accessibilityIdentifier("lookup.pronunciationError")
        }
        if let notice = model.notice {
            Text(notice)
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .accessibilityIdentifier("lookup.notice")
        }
        if let message = model.shortcutMessage {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
        }
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选中英文后按 ⌃⌥D，随时查译。首次需要开启辅助功能权限。")
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("开启划词查译") { model.requestAccessibility() }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("lookup.permission")
        }
    }

    @ViewBuilder private var translationSetup: some View {
        if #available(macOS 15.0, *) {
            Button { model.prepareTranslation() } label: {
                HStack(spacing: 6) {
                    if model.isPreparingTranslation { ProgressView().controlSize(.mini) }
                    Text(model.isPreparingTranslation ? "正在准备翻译…" : "启用句子翻译")
                }
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.isPreparingTranslation)
            .accessibilityIdentifier("lookup.prepareTranslation")
        } else {
            Text("句子翻译需要 macOS 15 或更新版本。")
                .font(.system(size: 11))
                .foregroundStyle(WordShelfTheme.secondary)
        }
    }
}

private struct LookupSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Keep the saved confirmation legible after the action becomes disabled.
private struct LookupSaveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The content is measured at its natural height before the scroll viewport is
/// capped. Long originals and definitions remain selectable and fully readable.
private struct LookupCappedContent<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var naturalHeight: CGFloat = 24

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { updateHeight(geometry.size.height) }
                            .onChange(of: geometry.size.height) { _, height in updateHeight(height) }
                    }
                }
        }
        .scrollIndicators(.automatic)
        .frame(height: min(max(naturalHeight, 20), maximumHeight))
    }

    private func updateHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        let fitted = ceil(height)
        if naturalHeight != fitted { naturalHeight = fitted }
    }
}

private struct CompactSaveMascot: View {
    let confirmation: SaveConfirmation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nodding = false

    var body: some View {
        UseleafMascotView(size: 20)
            .rotationEffect(.degrees(nodding ? 9 : 0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: nodding)
            .accessibilityIdentifier("lookup.saveConfirmation")
            .task(id: confirmation.id) {
                guard !reduceMotion else { return }
                nodding = true
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled else { return }
                nodding = false
            }
            .onChange(of: reduceMotion) { _, enabled in if enabled { nodding = false } }
            .onDisappear { nodding = false }
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
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
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
