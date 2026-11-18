import Foundation
import WordShelfCore

struct LearningTermHint: Equatable, Sendable {
    let word: String
    let meaning: String
}

enum LearningTermHints {
    /// Dictionary-only supplements for translated passages. They are labelled
    /// separately so an imperfect machine translation is not treated as an
    /// authoritative definition of a specialist term.
    static func find(in original: String, using provider: any VocabularyEvidenceProviding) async -> [LearningTermHint] {
        var seen = Set<String>()
        let tokens = original.split { !$0.isLetter }.map(String.init).filter {
            $0.count >= 3 && $0.unicodeScalars.allSatisfy { $0.value < 128 }
                && seen.insert($0.lowercased()).inserted
        }
        var results: [(LearningTermHint, Bool)] = []
        for token in tokens.prefix(30) {
            guard !Task.isCancelled else { return [] }
            guard let evidence = await provider.evidence(for: token) else { continue }
            let senses = evidence.chineseMeaning.components(separatedBy: .newlines)
            guard let technical = senses.first(where: {
                $0.range(of: "\\[(?:计|计算机|医|医学|法|经|会计|化|化学|电|物|生理)\\]", options: .regularExpression) != nil
            }) else { continue }
            let text = technical.replacingOccurrences(of: "\\[[^\\]]+\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            results.append((LearningTermHint(word: token, meaning: String(text.prefix(180))),
                            evidence.bncRank == nil && evidence.contemporaryRank == nil))
        }
        // Unknown-frequency technical terms are often precisely the ones the
        // sentence model mistranslates. Keep this short and source-labelled.
        return results.sorted { $0.1 && !$1.1 }.prefix(4).map(\.0)
    }
}
