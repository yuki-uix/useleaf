import Testing
@testable import WordShelfCore

@Suite("Real bundled English-Chinese dictionary")
struct DictionaryServiceTests {
    @Test("Technical words, short words and phrases have real Chinese definitions", arguments: ["hello", "concurrency", "idempotent", "ephemeral", "serialization", "cache", "a", "as", "in", "to", "go", "stick with"])
    func definitions(word: String) async throws {
        let entry = try await DictionaryService().lookup(word)
        #expect(entry.word == word)
        #expect(!entry.definitions.isEmpty)
        #expect(entry.definitions.contains { definition in
            definition.text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
        })
    }

    @Test("Missing words produce a useful explicit result")
    func missing() async {
        do {
            _ = try await DictionaryService().lookup("zzqxjvnotaword")
            Issue.record("An unknown word unexpectedly had a definition")
        } catch let error as DictionaryError {
            #expect(error == .notFound("zzqxjvnotaword"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Invalid selections are rejected before querying")
    func invalid() async {
        do {
            _ = try await DictionaryService().lookup("")
            Issue.record("Empty input was accepted")
        } catch let error as DictionaryError {
            #expect(error == .invalidWord)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("The reported phrase is looked up without changing its original casing")
    func reportedPhrase() async throws {
        let entry = try await DictionaryService().lookup("Stick with")
        #expect(entry.word == "Stick with")
        #expect(entry.definitions.contains { $0.text.contains("继续做") })
    }

    @Test("Unknown full sentences are eligible for translation instead of invalid-word rejection")
    func sentenceMissing() async {
        let sentence = "The API is idempotent, so retry the request."
        await #expect(throws: DictionaryError.notFound(sentence)) {
            try await DictionaryService().lookup(sentence)
        }
    }
}
