import Foundation
import Testing
@testable import WordShelfCore

@Suite("Original selection collection")
@MainActor
struct WordStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wordshelf-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Selections are normalized without accepting sentences or URLs")
    func normalize() {
        #expect(WordNormalizer.normalize("  ‘Concurrency,’ \n") == "concurrency")
        #expect(WordNormalizer.normalize("DON’T") == "don't")
        #expect(WordNormalizer.normalize("event-driven") == "event-driven")
        #expect(WordNormalizer.normalize("OAuth2") == "oauth2")
        #expect(WordNormalizer.normalize("NAÏVE") == "naïve")
        for input in ["", "read the docs", "https://example.com", "123", "中文", "word\nsecond", String(repeating: "a", count: 81)] {
            #expect(WordNormalizer.normalize(input) == nil)
        }
    }

    @Test("Wrappers and sentence endings are removed without changing technical tokens")
    func technicalTokenBoundaries() {
        for input in ["‘Concurrency,’", "(cache.)", "[\"ephemeral\"],", "`serialization`", "hello!?;:"] {
            #expect(WordNormalizer.normalize(input) != nil)
        }
        #expect(WordNormalizer.normalize("(cache.)") == "cache")
        #expect(WordNormalizer.normalize("[\"ephemeral\"],") == "ephemeral")
        for input in [".NET", "C#", "C++", "_private", "private_", "word/", "‘C#’", "(.NET)", "(word", "word'"] {
            #expect(WordNormalizer.normalize(input) == nil)
        }
    }

    @Test("Add, duplicate, delete and relaunch persist only words")
    func roundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        #expect(store.loadError == nil)
        #expect(try store.add("Cache"))
        #expect(try !store.add("cache"))
        #expect(try store.add("ephemeral"))
        #expect(store.words == ["ephemeral", "Cache"])
        #expect(store.contains("CACHE"))
        let data = try Data(contentsOf: store.fileURL)
        #expect(try JSONDecoder().decode([String].self, from: data) == ["ephemeral", "Cache"])
        #expect(store.exportText() == "ephemeral\nCache\n")
        let reloaded = WordStore(directoryURL: directory)
        #expect(reloaded.words == store.words)
        try reloaded.remove("EPHEMERAL")
        #expect(reloaded.words == ["Cache"])
        #expect(WordStore(directoryURL: directory).words == ["Cache"])
        try reloaded.remove("missing")
        #expect(reloaded.words == ["Cache"])
    }

    @Test("Invalid input never enters the collection")
    func invalidInput() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        for invalid in ["", "中文", "1234", "Cache\u{0000}", String(repeating: "a", count: SelectionText.maximumLength + 1)] {
            #expect(throws: WordStoreError.self) { try store.add(invalid) }
        }
        #expect(store.words.isEmpty)
        #expect(store.exportText().isEmpty)
        #expect(store.exportCSV().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("Corrupt files are preserved and writes are blocked")
    func corruption() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("words.json")
        let corrupt = Data("{not a collection}".utf8)
        try corrupt.write(to: file)
        let store = WordStore(directoryURL: directory)
        #expect(store.loadError != nil)
        #expect(throws: WordStoreError.self) { try store.add("cache") }
        #expect(throws: WordStoreError.self) { try store.remove("cache") }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test("Failed disk writes do not publish successful saves")
    func writeFailure() throws {
        let blocked = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: blocked) }
        try Data("not a directory".utf8).write(to: blocked)
        let store = WordStore(directoryURL: blocked)
        #expect(throws: (any Error).self) { try store.add("cache") }
        #expect(store.words.isEmpty)
    }

    @Test("Loaded duplicate words collapse without losing valid entries")
    func loadedDuplicates() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(["Cache", "cache", "ephemeral"]).write(to: directory.appendingPathComponent("words.json"))
        let store = WordStore(directoryURL: directory)
        #expect(store.loadError == nil)
        #expect(store.words == ["Cache", "ephemeral"])
    }

    @Test("Legacy word files upgrade without losing entries or original selections")
    func upgradeAndPreserveOriginals() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("words.json")
        try JSONEncoder().encode(["stick", "idempotent"]).write(to: file)
        let store = WordStore(directoryURL: directory)
        #expect(store.words == ["stick", "idempotent"])
        #expect(try !store.add("STICK"))
        #expect(try store.add("stick with"))
        let sentence = "The API is idempotent, so retry it."
        #expect(try store.add(sentence))
        let multiline = "Keep the Cache.\nRetry\tthe request."
        #expect(try store.add(multiline))
        #expect(try !store.add(" \n" + multiline + "\n "))
        let expected = [multiline, sentence, "stick with", "stick", "idempotent"]
        #expect(store.words == expected)
        #expect(try JSONDecoder().decode([String].self, from: Data(contentsOf: file)) == expected)
        let reloaded = WordStore(directoryURL: directory)
        #expect(reloaded.loadError == nil)
        #expect(reloaded.words == expected)
        #expect(reloaded.contains("STICK"))
        #expect(reloaded.contains(sentence))
        #expect(!reloaded.contains(sentence.lowercased()))
        try reloaded.remove("IDEMPOTENT")
        #expect(reloaded.words == [multiline, sentence, "stick with", "stick"])
        #expect(WordStore(directoryURL: directory).words == reloaded.words)
    }

    @Test("Phrase and sentence identity preserves case, punctuation and internal whitespace")
    func selectionDuplicates() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        let selections = ["stick with", "Stick with", "stick  with", "Retry it.", "retry it.", "Retry it!", "C#", ".NET"]
        for text in selections {
            #expect(try store.add(text))
            #expect(try !store.add(text))
        }
        #expect(store.words == Array(selections.reversed()))
        try store.remove("Stick with")
        #expect(store.contains("stick with"))
        #expect(!store.contains("Stick with"))
    }

    @Test("Text export retains complete selections with blank lines between records")
    func textExport() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        try store.add("stick")
        try store.add("stick with")
        try store.add("The API is idempotent, so retry it.")
        try store.add("Keep the Cache.\nRetry the request.")
        #expect(store.exportText() == "Keep the Cache.\nRetry the request.\n\nThe API is idempotent, so retry it.\n\nstick with\n\nstick\n")
    }

    @Test("An independent CSV parser round-trips commas, quotes and multiline selections")
    func csvExportRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordStore(directoryURL: directory)
        let selections = ["stick", "stick with", "The API is idempotent, so retry it.", "She said, \"Keep the Cache.\"", "First line.\nSecond line.", "CRLF first.\r\nCRLF second."]
        for text in selections { try store.add(text) }
        #expect(WordStore(directoryURL: directory).words == store.words)
        let csv = store.exportCSV()
        #expect(csv.hasSuffix("\r\n"))

        // Use Python's standard CSV reader, rather than a second copy of our encoder.
        // newline="" preserves embedded CRLF and LF inside quoted fields.
        let parser = Process()
        parser.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        parser.arguments = ["-c", "import csv,io,json,sys; raw=sys.stdin.buffer.read().decode('utf-8'); print(json.dumps(list(csv.reader(io.StringIO(raw,newline=''))),ensure_ascii=False))"]
        let input = Pipe()
        let output = Pipe()
        parser.standardInput = input
        parser.standardOutput = output
        try parser.run()
        input.fileHandleForWriting.write(Data(csv.utf8))
        try input.fileHandleForWriting.close()
        let parsed = output.fileHandleForReading.readDataToEndOfFile()
        parser.waitUntilExit()
        #expect(parser.terminationStatus == 0)
        let records = try JSONDecoder().decode([[String]].self, from: parsed)
        #expect(records == store.words.map { [$0] })
    }
}
