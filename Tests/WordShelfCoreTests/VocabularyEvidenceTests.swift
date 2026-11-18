import Testing
@testable import WordShelfCore

@Suite("Bundled vocabulary evidence")
struct VocabularyEvidenceTests {
    @Test func knownEntryHasRealMeaningsAndPositiveRanks() async throws {
        let evidence = try #require(await VocabularyEvidenceService().evidence(for: "stick"))
        #expect(evidence.chineseMeaning.contains("棍"))
        #expect(!evidence.englishMeaning.isEmpty)
        #expect((evidence.bncRank ?? 0) > 0)
        #expect((evidence.contemporaryRank ?? 0) > 0)
    }

    @Test func unknownRanksAreNotZeroAndComponentRanksAreNotUsedForPhrases() async throws {
        let service = VocabularyEvidenceService()
        let phrase = try #require(await service.evidence(for: "stick with"))
        #expect(phrase.chineseMeaning.contains("继续做"))
        #expect(phrase.bncRank == nil)
        #expect(phrase.contemporaryRank == nil)
        let technical = try #require(await service.evidence(for: "idempotent"))
        #expect(technical.chineseMeaning.contains("幂等"))
        #expect(technical.bncRank == nil)
        #expect(technical.contemporaryRank == nil)
        #expect(await service.evidence(for: "The API is idempotent, so retry the request.") == nil)
    }

    @Test func lookupKeysAreNormalizedWithoutChangingEvidence() async {
        let service = VocabularyEvidenceService()
        #expect(await service.evidence(for: " Stick   with ") == service.evidence(for: "stick with"))
        #expect(await service.evidence(for: "") == nil)
    }
}
