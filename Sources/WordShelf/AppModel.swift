import AppKit
import Combine
import UniformTypeIdentifiers
import WordShelfCore

enum LookupState: Equatable {
    case idle
    case loading
    case found(DictionaryEntry)
    case failed(String)
}

enum PronunciationSource: Equatable {
    case lookup
    case notebook(String)
}

/// An in-memory confirmation of one completed insertion, never a lookup or
/// persisted learning signal. Its identity lets the view acknowledge it once.
struct SaveConfirmation: Equatable, Identifiable {
    let id = UUID()
    let original: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var query = "" {
        didSet {
            if query != oldValue {
                stopPronunciation()
                saveConfirmation = nil
            }
        }
    }
    @Published private(set) var lookupState: LookupState = .idle
    @Published private(set) var lookupWord: String?
    @Published var notice: String?
    @Published var captureMessage: String?
    @Published var permissionGranted = false
    @Published var shortcutMessage: String?
    @Published private(set) var isPreparingTranslation = false
    @Published private(set) var translationSetupRequired = false
    @Published var lookupHostVisible = false
    @Published var notebookHostVisible = false
    @Published private(set) var isPronouncing = false
    @Published private(set) var playingAccent: PronunciationAccent?
    @Published private(set) var pronunciationError: String?
    @Published private(set) var pronunciationSource: PronunciationSource?
    @Published private(set) var saveConfirmation: SaveConfirmation?

    let store: WordStore
    let learning: LearningModel
    private let dictionary: any DictionaryLookingUp
    private let translator: any TextTranslating
    private let pronunciation: any Pronouncing
    private var lookupTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var lookupID = UUID()
    private var storeSubscription: AnyCancellable?
    private var removedWord: String?

    var onShowNotebook: () -> Void = {}
    var onDismissPopup: () -> Void = {}
    var onRequestAccessibility: () -> Void = {}
    var onShowManualLookup: () -> Void = {}
    var onShowCurrentLookup: () -> Void = {}

    init(store: WordStore, dictionary: any DictionaryLookingUp = DictionaryService(), translator: (any TextTranslating)? = nil, pronunciation: (any Pronouncing)? = nil, learning: LearningModel? = nil) {
        self.store = store
        self.dictionary = dictionary
        let translation = translator ?? AppleTranslationService()
        self.translator = translation
        self.pronunciation = pronunciation ?? PronunciationService()
        self.learning = learning ?? LearningModel(store: LearningStore(directoryURL: store.fileURL.deletingLastPathComponent()),
                                      dictionary: dictionary, translator: translation)
        self.notice = store.loadError
        storeSubscription = store.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.learning.syncCollection(self.words)
            }
        }
        self.pronunciation.onSpeakingChanged = { [weak self] speaking in
            self?.isPronouncing = speaking
            if !speaking { self?.playingAccent = nil }
        }
        self.learning.syncCollection(store.words)
    }

    var words: [String] { store.words }
    var currentWordIsSaved: Bool {
        guard let word = lookupWord, SelectionText.normalize(query) == word else { return false }
        return store.contains(word)
    }
    var canSaveCurrentWord: Bool {
        guard let word = lookupWord, SelectionText.normalize(query) == word else { return false }
        return !store.contains(word)
    }
    var canUndoRemoval: Bool { removedWord != nil }
    var canPronounce: Bool { SelectionText.normalize(query) != nil }
    var currentSaveConfirmation: SaveConfirmation? {
        guard let confirmation = saveConfirmation,
              confirmation.original == lookupWord,
              SelectionText.normalize(query) == confirmation.original,
              store.contains(confirmation.original) else { return nil }
        return confirmation
    }

    func pronounce(_ accent: PronunciationAccent) {
        guard let original = SelectionText.normalize(query) else { return }
        pronounce(original, accent: accent, source: .lookup)
    }

    func pronounceSavedWord(_ word: String, accent: PronunciationAccent) {
        guard words.contains(word), let original = SelectionText.normalize(word) else { return }
        pronounce(original, accent: accent, source: .notebook(word))
    }

    private func pronounce(_ original: String, accent: PronunciationAccent, source: PronunciationSource) {
        if isPronouncing && playingAccent == accent && pronunciationSource == source {
            stopPronunciation()
            return
        }
        pronunciationError = nil
        pronunciationSource = source
        do {
            try pronunciation.speak(original, accent: accent)
            isPronouncing = pronunciation.isSpeaking
            playingAccent = isPronouncing ? accent : nil
        } catch {
            isPronouncing = false
            playingAccent = nil
            pronunciationError = error.localizedDescription
        }
    }

    func stopPronunciation() {
        pronunciation.stop()
        isPronouncing = false
        playingAccent = nil
        pronunciationError = nil
        pronunciationSource = nil
    }

    func stopNotebookPronunciation() {
        guard case .notebook = pronunciationSource else { return }
        stopPronunciation()
    }

    func lookup(_ raw: String? = nil) {
        stopPronunciation()
        saveConfirmation = nil
        if let raw { query = raw }
        lookupTask?.cancel()
        lookupID = UUID()
        notice = nil
        captureMessage = nil
        translationSetupRequired = false
        guard let word = SelectionText.normalize(query) else {
            lookupWord = nil
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            lookupState = .failed(trimmed.count > SelectionText.maximumLength
                ? "每次最多支持 \(SelectionText.maximumLength) 个字符。请缩小选择范围；原文不会被截断。"
                : "请输入英文单词、短语或句子；也可以在原文中选中文字后按 ⌃⌥D。")
            return
        }
        query = word
        lookupWord = word
        learning.noteEncounter(word)
        lookupState = .loading
        let id = lookupID
        lookupTask = Task { [weak self, dictionary, translator] in
            do {
                let entry: DictionaryEntry
                do {
                    entry = try await dictionary.lookup(word)
                } catch {
                    try Task.checkCancellation()
                    let translated = try await translator.translate(word)
                    try Task.checkCancellation()
                    guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw TranslationServiceError.failed("暂未得到翻译结果，仍可收藏原文。")
                    }
                    entry = DictionaryEntry(word: word,
                                            definitions: [DictionaryDefinition(text: translated)],
                                            sourceName: "Apple · 本机翻译")
                }
                guard !Task.isCancelled, let self, self.lookupID == id else { return }
                self.lookupState = .found(entry)
            } catch {
                guard !Task.isCancelled, let self, self.lookupID == id else { return }
                self.translationSetupRequired = (error as? TranslationServiceError) == .needsLanguages
                self.lookupState = .failed(error is CancellationError
                    ? "已取消翻译，可以重试或先收藏原文。"
                    : error.localizedDescription)
            }
        }
    }

    func prepareManualLookup() {
        cancelLookup()
        query = ""
        lookupWord = nil
        lookupState = .idle
        notice = nil
        captureMessage = nil
        translationSetupRequired = false
    }

    func cancelLookup() {
        stopPronunciation()
        saveConfirmation = nil
        lookupTask?.cancel()
        lookupID = UUID()
    }

    func prepareTranslation() {
        guard !isPreparingTranslation else { return }
        let pending = lookupWord
        isPreparingTranslation = true
        notice = "正在准备中英离线翻译，首次使用需要下载语言。"
        // A regular window hosts the system's language-download sheet.
        onShowNotebook()
        preparationTask = Task { [weak self, translator] in
            do {
                try await translator.prepareLanguages()
                guard !Task.isCancelled, let self else { return }
                self.isPreparingTranslation = false
                self.translationSetupRequired = false
                self.notice = "中英离线翻译已准备好"
                if let pending, SelectionText.normalize(self.query) == pending {
                    self.lookup(pending)
                    self.onShowCurrentLookup()
                }
            } catch {
                guard let self else { return }
                self.isPreparingTranslation = false
                self.notice = error is CancellationError
                    ? "已取消翻译准备，仍可收藏原文。"
                    : error.localizedDescription
            }
        }
    }

    func saveCurrentWord() {
        saveConfirmation = nil
        guard let word = lookupWord, SelectionText.normalize(query) == word else { return }
        do {
            let inserted = try store.add(word)
            learning.syncCollection(words)
            learning.noteEncounter(word)
            if inserted {
                notice = nil
                saveConfirmation = SaveConfirmation(original: word)
            } else {
                notice = "这条原文已在生词本中"
            }
        } catch { notice = "收藏失败：\(error.localizedDescription)" }
    }

    func removeWord(_ word: String) {
        do {
            try store.remove(word)
            if saveConfirmation?.original == word { saveConfirmation = nil }
            learning.syncCollection(words)
            if pronunciationSource == .notebook(word) { stopPronunciation() }
            removedWord = word
            notice = "已移除这条收藏"
        } catch { notice = "删除失败：\(error.localizedDescription)" }
    }

    func undoRemoval() {
        guard let word = removedWord else { return }
        do {
            try store.add(word)
            learning.syncCollection(words)
            removedWord = nil
            notice = "已恢复这条收藏"
        } catch { notice = "恢复失败：\(error.localizedDescription)" }
    }

    func showNotebook() { onShowNotebook() }
    func dismissPopup() {
        saveConfirmation = nil
        onDismissPopup()
    }
    func requestAccessibility() { onRequestAccessibility() }
    func showManualLookup() { onShowManualLookup() }

    func exportWords() {
        let panel = NSSavePanel()
        panel.title = "导出生词本"
        panel.message = "只导出收藏原文。TXT 用空行分隔长文本，CSV 每条收藏占一个单元格。"
        panel.nameFieldStringValue = "拾用-生词本.txt"
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let contents = url.pathExtension.lowercased() == "csv" ? store.exportCSV() : store.exportText()
            try contents.write(to: url, atomically: true, encoding: .utf8)
            notice = "已导出 \(words.count) 条收藏"
        } catch { notice = "导出失败：\(error.localizedDescription)" }
    }
}
