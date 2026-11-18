import CSQLite
import Foundation

/// All queries stay on this actor's executor; no network request or lookup history is stored.
public actor DictionaryService: DictionaryLookingUp {
    public init() {}

    public func lookup(_ input: String) async throws -> DictionaryEntry {
        try Task.checkCancellation()
        guard let original = SelectionText.normalize(input),
              let word = SelectionText.dictionaryKey(original) else { throw DictionaryError.invalidWord }
        // SwiftPM's generated accessor searches next to the executable product.
        // A distributable .app keeps its resource bundles in Contents/Resources.
        let packagedBundle = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("WordShelf_WordShelfCore.bundle"))
        }
        let resources = packagedBundle ?? Bundle.module
        guard let url = resources.url(forResource: "ecdict", withExtension: "sqlite", subdirectory: "Resources") else {
            throw DictionaryError.unavailable
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw DictionaryError.unavailable
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT word, phonetic, translation, definition FROM entries WHERE word = ? COLLATE NOCASE LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DictionaryError.unavailable }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, word, -1, transient) == SQLITE_OK else { throw DictionaryError.unavailable }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            if step == SQLITE_DONE { throw DictionaryError.notFound(original) }
            throw DictionaryError.unavailable
        }
        func column(_ index: Int32) -> String {
            sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        }
        let phonetic = column(1)
        let chinese = column(2)
        let english = column(3)
        let text = chinese.isEmpty ? english : chinese
        let definitions = text.replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { DictionaryDefinition(text: $0) }
        guard !definitions.isEmpty else { throw DictionaryError.notFound(original) }
        try Task.checkCancellation()
        return DictionaryEntry(word: original, phonetic: phonetic.isEmpty ? nil : phonetic,
                               definitions: definitions, sourceName: "ECDICT · 离线英汉词典",
                               sourceURL: URL(string: "https://github.com/skywind3000/ECDICT"))
    }
}
