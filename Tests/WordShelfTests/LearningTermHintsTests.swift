import Testing
@testable import WordShelf
import WordShelfCore

@Suite("Learning technical term references")
struct LearningTermHintsTests {
    @Test func specialistMeaningSurvivesAnImperfectSentenceTranslation() async {
        let hints = await LearningTermHints.find(in: "The API is idempotent, so retry the request.", using: VocabularyEvidenceService())
        #expect(hints.contains { $0.word == "idempotent" && $0.meaning.contains("幂等") })
        #expect(hints.count <= 4)
        #expect(hints.allSatisfy { !$0.meaning.isEmpty && !$0.meaning.contains("[计]") })
    }

    @Test func repeatedCaseVariantsDoNotCreateDuplicateTechnicalHints() async {
        let hints = await LearningTermHints.find(in: "Idempotent idempotent IDEMPOTENT", using: VocabularyEvidenceService())
        #expect(hints.count == 1)
        #expect(hints.first?.meaning.contains("幂等") == true)
        #expect(await LearningTermHints.find(in: "zzqxjvnotaword", using: VocabularyEvidenceService()).isEmpty)
    }
}
