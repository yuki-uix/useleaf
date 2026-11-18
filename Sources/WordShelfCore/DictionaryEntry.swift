import Foundation

public struct DictionaryDefinition: Equatable, Sendable {
    public let partOfSpeech: String?
    public let text: String

    public init(partOfSpeech: String? = nil, text: String) {
        self.partOfSpeech = partOfSpeech
        self.text = text
    }
}

public struct DictionaryEntry: Equatable, Sendable {
    public let word: String
    public let phonetic: String?
    public let definitions: [DictionaryDefinition]
    public let sourceName: String
    public let sourceURL: URL?

    public init(word: String, phonetic: String? = nil, definitions: [DictionaryDefinition], sourceName: String, sourceURL: URL? = nil) {
        self.word = word
        self.phonetic = phonetic
        self.definitions = definitions
        self.sourceName = sourceName
        self.sourceURL = sourceURL
    }
}

public protocol DictionaryLookingUp: Sendable {
    func lookup(_ word: String) async throws -> DictionaryEntry
}

public enum DictionaryError: LocalizedError, Equatable {
    case invalidWord
    case notFound(String)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidWord: return "请选择或输入英文单词、短语或句子。"
        case .notFound: return "离线词典暂未收录这段文本，可以翻译或先收藏原文。"
        case .unavailable: return "离线词典未能打开，请重新安装应用。你仍然可以翻译或收藏原文。"
        }
    }
}
