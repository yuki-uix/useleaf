import Foundation

public enum SelectionKind: String, Sendable {
    case word
    case phrase
    case sentence
}

/// Collection text and dictionary query keys have deliberately separate rules.
/// The collection always retains the selected spelling, punctuation and line breaks.
public enum SelectionText {
    public static let maximumLength = 4_000

    public static func normalize(_ input: String) -> String? {
        let permittedControls: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        guard input.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0) || permittedControls.contains($0)
        }) else { return nil }
        let selection = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty, selection.count <= maximumLength,
              selection.range(of: "\\p{Latin}", options: .regularExpression) != nil else { return nil }
        return selection
    }

    /// Single words are case-insensitive; longer selections retain their exact identity.
    public static func identity(_ input: String) -> String? {
        guard let selection = normalize(input) else { return nil }
        if kind(of: selection) == .word {
            return "word:" + selection.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }
        return "text:" + selection
    }

    public static func kind(of input: String) -> SelectionKind {
        let selection = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection.range(of: "^[\\p{Latin}][\\p{Latin}0-9]*(?:[-'’][\\p{Latin}0-9]+)*$", options: .regularExpression) != nil {
            return .word
        }
        if selection.rangeOfCharacter(from: .newlines) != nil { return .sentence }
        // Closing quotation marks do not conceal a sentence's terminal punctuation.
        let ending = selection.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]}»›）】》"))
        if let last = ending.last, ".!?。！？".contains(last) { return .sentence }
        return .phrase
    }

    /// Used only by dictionary lookup; never use this key as the saved content.
    public static func dictionaryKey(_ input: String) -> String? {
        guard let selection = normalize(input) else { return nil }
        return selection.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
