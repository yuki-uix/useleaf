import CSQLite
import Foundation

public struct VocabularyEvidence: Equatable, Sendable {
    public let chineseMeaning: String
    public let englishMeaning: String
    public let bncRank: Int?
    public let contemporaryRank: Int?

    public init(chineseMeaning: String = "", englishMeaning: String = "", bncRank: Int? = nil, contemporaryRank: Int? = nil) {
        self.chineseMeaning = chineseMeaning
        self.englishMeaning = englishMeaning
        self.bncRank = bncRank
        self.contemporaryRank = contemporaryRank
    }
}

public protocol VocabularyEvidenceProviding: Sendable {
    func evidence(for input: String) async -> VocabularyEvidence?
}

/// Exact dictionary entries only: a component word's rank never becomes the
/// frequency of a phrase or sentence. Missing ranks remain unknown.
public actor VocabularyEvidenceService: VocabularyEvidenceProviding {
    public init() {}

    public func evidence(for input: String) async -> VocabularyEvidence? {
        guard !Task.isCancelled, let key = SelectionText.dictionaryKey(input) else { return nil }
        let packaged = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("WordShelf_WordShelfCore.bundle"))
        }
        guard let url = (packaged ?? Bundle.module).url(forResource: "ecdict", withExtension: "sqlite", subdirectory: "Resources") else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT translation, definition, bnc_rank, contemporary_rank FROM entries WHERE word = ? COLLATE NOCASE LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else { return nil }
        func text(_ column: Int32) -> String {
            (sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\r", with: "\n")
        }
        func rank(_ column: Int32) -> Int? {
            let number = sqlite3_column_int64(statement, column)
            return number > 0 ? Int(number) : nil
        }
        return VocabularyEvidence(chineseMeaning: text(0), englishMeaning: text(1),
                                  bncRank: rank(2), contemporaryRank: rank(3))
    }
}
