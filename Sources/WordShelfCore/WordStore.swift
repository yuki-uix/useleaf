import Combine
import Foundation

public enum WordStoreError: LocalizedError {
    case invalidWord
    case unreadableCollection(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWord:
            return "请选择或输入包含英文的单词、短语或句子（最多 4000 个字符）。"
        case .unreadableCollection(let detail):
            return "生词本未能读取，原文件已保留。\(detail)"
        }
    }
}

@MainActor
public final class WordStore: ObservableObject {
    @Published public private(set) var words: [String] = []
    public private(set) var loadError: String?
    public let fileURL: URL

    public init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.yuki.wordshelf", isDirectory: true)
        fileURL = directory.appendingPathComponent("words.json")
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let saved = try JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL))
            var seen = Set<String>()
            var loaded: [String] = []
            for raw in saved {
                guard let word = SelectionText.normalize(raw), let identity = SelectionText.identity(word) else {
                    throw WordStoreError.invalidWord
                }
                if seen.insert(identity).inserted { loaded.append(word) }
            }
            words = loaded
        } catch {
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    public func add(_ input: String) throws -> Bool {
        try ensureReadable()
        guard let word = SelectionText.normalize(input), let identity = SelectionText.identity(word) else { throw WordStoreError.invalidWord }
        guard !words.contains(where: { SelectionText.identity($0) == identity }) else { return false }
        let updated = [word] + words
        try persist(updated)
        words = updated
        return true
    }

    public func remove(_ input: String) throws {
        try ensureReadable()
        guard let identity = SelectionText.identity(input) else { throw WordStoreError.invalidWord }
        let updated = words.filter { SelectionText.identity($0) != identity }
        guard updated.count != words.count else { return }
        try persist(updated)
        words = updated
    }

    public func contains(_ input: String) -> Bool {
        guard let identity = SelectionText.identity(input) else { return false }
        return words.contains { SelectionText.identity($0) == identity }
    }

    public func exportText() -> String {
        guard !words.isEmpty else { return "" }
        let separator = words.allSatisfy { SelectionText.kind(of: $0) == .word } ? "\n" : "\n\n"
        return words.joined(separator: separator) + "\n"
    }

    /// A single-column RFC 4180 CSV, with one complete selection in each record.
    public func exportCSV() -> String {
        guard !words.isEmpty else { return "" }
        return words.map { selection in
            // Scan scalars: Swift treats CRLF as one Character, so checking for
            // a standalone "\r" or "\n" Character would miss that line ending.
            if selection.rangeOfCharacter(from: CharacterSet(charactersIn: ",\"\r\n")) != nil {
                return "\"" + selection.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return selection
        }.joined(separator: "\r\n") + "\r\n"
    }

    private func ensureReadable() throws {
        if let loadError { throw WordStoreError.unreadableCollection(loadError) }
    }

    private func persist(_ updated: [String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(updated).write(to: fileURL, options: .atomic)
        // Collection contents belong to this macOS account.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
