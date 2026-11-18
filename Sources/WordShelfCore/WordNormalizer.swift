import Foundation

public enum WordNormalizer {
    /// A collection entry is one English word, never a selected paragraph or URL.
    public static func normalize(_ input: String) -> String? {
        var selection = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceEndings = Set<Character>(".,!?;:，。！？；：")
        let wrappers: [Character: Character] = [
            "\"": "\"", "'": "'", "“": "”", "‘": "’", "`": "`",
            "(": ")", "[": "]", "{": "}", "<": ">", "«": "»", "‹": "›",
            "（": "）", "【": "】", "《": "》"
        ]
        // Strip sentence punctuation only at the end, and wrappers only as pairs.
        // Blanket punctuation trimming changes technical tokens (.NET, C#, _foo)
        // into unrelated words, which must never be silently collected instead.
        while true {
            let previous = selection
            while let last = selection.last, sentenceEndings.contains(last) {
                selection.removeLast()
            }
            if selection.count >= 2, let first = selection.first,
               let closing = wrappers[first], selection.last == closing {
                selection.removeFirst()
                selection.removeLast()
                selection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if selection == previous { break }
        }
        let trimmed = selection
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
        guard !trimmed.isEmpty, trimmed.count <= 80,
              trimmed.range(of: "^[\\p{Latin}][\\p{Latin}0-9]*(?:[-'][\\p{Latin}0-9]+)*$", options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }
}
