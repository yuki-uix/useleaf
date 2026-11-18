import Foundation
import Testing
@testable import WordShelfCore

@Suite("Selection text fidelity")
struct SelectionTextTests {
    @Test("Normalization trims only outer whitespace")
    func preserveOriginals() {
        #expect(SelectionText.normalize("  Stick with  ") == "Stick with")
        #expect(SelectionText.normalize("The API is idempotent, so retry it.") == "The API is idempotent, so retry it.")
        #expect(SelectionText.normalize(" \nKeep the Cache.\nRetry\tthe request.\r\n ") == "Keep the Cache.\nRetry\tthe request.")
        #expect(SelectionText.normalize("‘Concurrency,’") == "‘Concurrency,’")
        #expect(SelectionText.normalize(".NET") == ".NET")
        #expect(SelectionText.normalize("C#") == "C#")
        #expect(SelectionText.normalize("Café 是一个英文借词。") == "Café 是一个英文借词。")
    }

    @Test("Empty, oversized, non-English and unsafe control selections are rejected")
    func validation() {
        #expect(SelectionText.normalize(String(repeating: "a", count: SelectionText.maximumLength)) != nil)
        for input in ["", " \t\n ", "中文", "12345", String(repeating: "a", count: SelectionText.maximumLength + 1), "Cache\u{0000}", "Cache\u{0007}", "Cache\u{001B}", "Cache\u{007F}", "\u{000B}Cache", "Cache\u{202E}"] {
            #expect(SelectionText.normalize(input) == nil)
        }
    }

    @Test("Kinds distinguish words, phrases and sentence-like selections")
    func classify() {
        for text in ["Cache", "event-driven", "DON’T", "OAuth2", "naïve"] {
            #expect(SelectionText.kind(of: text) == .word)
        }
        for text in ["stick with", "C#", ".NET", "a,b", "The API"] {
            #expect(SelectionText.kind(of: text) == .phrase)
        }
        for text in ["Retry it.", "Is it idempotent?", "Retry it!", "She said, \"Retry it.\"", "line one\nline two", "line one\r\nline two"] {
            #expect(SelectionText.kind(of: text) == .sentence)
        }
    }

    @Test("Identity folds word case without changing phrase or sentence identity")
    func identity() {
        #expect(SelectionText.identity("Cache") == SelectionText.identity("CACHE"))
        #expect(SelectionText.identity("  Cache  ") == SelectionText.identity("cache"))
        #expect(SelectionText.identity("Stick with") != SelectionText.identity("stick with"))
        #expect(SelectionText.identity("stick  with") != SelectionText.identity("stick with"))
        #expect(SelectionText.identity("Retry it.") != SelectionText.identity("retry it."))
        #expect(SelectionText.identity("Retry it.") != SelectionText.identity("Retry it!"))
        #expect(SelectionText.identity("中文") == nil)
    }

    @Test("Dictionary keys merge whitespace and case independently from saved text")
    func lookupKey() {
        let original = "Stick  \twith\nIt."
        #expect(SelectionText.dictionaryKey(original) == "stick with it.")
        #expect(SelectionText.normalize(original) == original)
        #expect(SelectionText.dictionaryKey(" ‘Concurrency,’ ") == "‘concurrency,’")
        #expect(SelectionText.dictionaryKey("中文") == nil)
    }
}
