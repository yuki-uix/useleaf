import Foundation
import Testing
@testable import WordShelfCore

@Suite("Personal learning state")
@MainActor
struct LearningStateTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wordshelf-learning-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func profile(_ text: String = "每周向同事解释接口问题，清楚提出解决方案") -> LearningProfile {
        LearningProfile(workDomain: "软件", workScenarios: [text], lifeScenarios: ["和朋友聊兴趣和生活经历"],
                        expressionGoals: ["这个方案先继续试试"])
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test("Legacy collections load without creating or modifying learning state")
    func oldWordsRemainIndependentAndNoFileIsWrittenOnRead() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let words = WordStore(directoryURL: root)
        try words.add("Cache")
        try words.add("Please stick with the current plan.")
        let before = try Data(contentsOf: words.fileURL)
        let learning = LearningStore(directoryURL: root)
        #expect(learning.loadError == nil)
        #expect(!learning.profile.isConfigured)
        #expect(learning.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: learning.fileURL.path))
        try learning.saveProfile(profile())
        try learning.recordEncounter("Cache")
        try learning.setPurpose(.use, for: "Cache")
        #expect(try Data(contentsOf: words.fileURL) == before)
        #expect(WordStore(directoryURL: root).words == words.words)
    }

    @Test("Profile validation limits input and requires a real scenario")
    func profileValidation() throws {
        #expect(!LearningProfile(workDomain: "软件", expressionGoals: ["表达意见"]).isConfigured)
        #expect(LearningProfile(workDomain: "软件").validationMessage != nil)
        #expect(LearningProfile(workScenarios: [" ", "\n"]).validationMessage != nil)
        #expect(LearningProfile(lifeScenarios: ["每月旅行"]).validationMessage == nil)
        #expect(LearningProfile(workDomain: String(repeating: "a", count: 121), workScenarios: ["meeting"]).validationMessage != nil)
        #expect(LearningProfile(workScenarios: ["a", "b", "c", "d"]).validationMessage != nil)
        #expect(LearningProfile(lifeScenarios: ["a", "b", "c", "d"]).validationMessage != nil)
        #expect(LearningProfile(workScenarios: ["meeting"], expressionGoals: Array(repeating: "goal", count: 6)).validationMessage != nil)
        #expect(LearningProfile(workScenarios: [String(repeating: "a", count: 501)]).validationMessage != nil)
        #expect(LearningProfile(workScenarios: ["meeting\u{0000}"]).validationMessage != nil)

        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LearningStore(directoryURL: root)
        #expect(throws: LearningStoreError.self) { try store.saveProfile(LearningProfile()) }
        #expect(!store.profile.isConfigured)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("Profile fingerprints are deterministic across harmless formatting and ordering changes")
    func stableFingerprint() {
        let first = LearningProfile(workDomain: " Software ", workScenarios: [" Explain   API issues ", "Write weekly updates"],
                                    lifeScenarios: ["Discuss hobbies"], expressionGoals: ["Talk about trade-offs"])
        let reordered = LearningProfile(workDomain: "software", workScenarios: ["write weekly updates", "explain api issues", ""],
                                        lifeScenarios: [" discuss hobbies "], expressionGoals: ["TALK ABOUT TRADE-OFFS"])
        #expect(first.fingerprint == reordered.fingerprint)
        #expect(first.fingerprint.count == 64)
        var changed = reordered
        changed.workScenarios = ["Interview customers"]
        #expect(first.fingerprint != changed.fingerprint)
    }

    @Test("Profiles and explicit feedback survive restart and returning to automatic classification")
    func profileAndFeedbackRoundTrip() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LearningStore(directoryURL: root)
        let input = LearningProfile(workDomain: " 软件 ", workScenarios: ["", " 解释接口问题 "], lifeScenarios: [" 分享兴趣 "])
        try store.saveProfile(input)
        try store.setPurpose(.use, for: "Cache")
        try store.setPurpose(.reference, for: "stick with")
        let before = try Data(contentsOf: store.fileURL)
        let reloaded = LearningStore(directoryURL: root)
        #expect(reloaded.loadError == nil)
        #expect(reloaded.profile.workDomain == "软件")
        #expect(reloaded.profile.workScenarios == ["解释接口问题"])
        #expect(reloaded.profile.lifeScenarios == ["分享兴趣"])
        #expect(reloaded.record(for: "CACHE")?.overridePurpose == .use)
        #expect(reloaded.record(for: "stick with")?.overridePurpose == .reference)
        #expect(reloaded.record(for: "Stick with") == nil)
        #expect(try Data(contentsOf: store.fileURL) == before)
        try reloaded.setPurpose(nil, for: "cache")
        #expect(reloaded.record(for: "Cache")?.overridePurpose == nil)
        #expect(LearningStore(directoryURL: root).record(for: "Cache")?.overridePurpose == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("Only distinct UTC dates count as encounters, preserving phrase identity")
    func encounterDatesCountDaysInsteadOfClicks() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LearningStore(directoryURL: root)
        try store.recordEncounter("Cache", at: date("2026-11-18T00:00:00Z"))
        try store.recordEncounter("cache", at: date("2026-11-18T23:59:59Z"))
        try store.recordEncounter("CACHE", at: date("2026-11-19T00:00:00Z"))
        try store.recordEncounter("cache", at: date("2026-11-17T23:59:59Z"))
        try store.recordEncounter("stick with", at: date("2026-11-18T00:00:00Z"))
        try store.recordEncounter("Stick with", at: date("2026-11-19T00:00:00Z"))
        #expect(store.record(for: "cache")?.encounterDates == ["2026-11-17", "2026-11-18", "2026-11-19"])
        #expect(store.record(for: "stick with")?.encounterDates == ["2026-11-18"])
        #expect(store.record(for: "Stick with")?.encounterDates == ["2026-11-19"])
        let restarted = LearningStore(directoryURL: root)
        #expect(restarted.records == store.records)
    }

    @Test("Progress changes independently of explicit intent and encounters")
    func reviewAndClearProgressRoundTrip() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LearningStore(directoryURL: root)
        let now = date("2026-11-18T12:00:00Z")
        try store.setPurpose(.use, for: "Cache")
        try store.recordEncounter("cache", at: now)
        try store.rate("CACHE", rating: .good, purpose: .use, at: now)
        let first = try #require(store.record(for: "cache")?.progress)
        #expect(first.reviews == 1)
        #expect(first.lastReviewedAt == now)
        #expect(first.dueAt == now.addingTimeInterval(86_400))
        #expect(LearningStore(directoryURL: root).record(for: "cache")?.progress == first)
        #expect(LearningStore(directoryURL: root).record(for: "cache")?.reviewedPurpose == .use)
        try store.clearProgress(for: "cache")
        let cleared = try #require(store.record(for: "cache"))
        #expect(cleared.progress == nil)
        #expect(cleared.reviewedPurpose == nil)
        #expect(cleared.overridePurpose == .use)
        #expect(cleared.encounterDates == ["2026-11-18"])
        #expect(LearningStore(directoryURL: root).record(for: "cache") == cleared)
    }

    @Test("Old progress without a reviewed-purpose key loads and becomes a fresh target on its next explicit review")
    func legacyProgressWithoutPurposeRemainsReadable() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let raw = """
        {"version":1,"profile":{"workDomain":"","workScenarios":[],"lifeScenarios":[],"expressionGoals":[]},
         "records":{"word:cache":{"encounterDates":["2026-11-18"],"overridePurpose":"use", "progress":{"dueAt":0,"intervalDays":90,"reviews":8}}}}
        """
        let file = root.appendingPathComponent("learning.json")
        try Data(raw.utf8).write(to: file)
        let store = LearningStore(directoryURL: root)
        #expect(store.loadError == nil)
        #expect(store.record(for: "cache")?.reviewedPurpose == nil)
        #expect(store.record(for: "cache")?.progress?.intervalDays == 90)
        let now = date("2026-11-18T12:00:00Z")
        try store.rate("cache", rating: .good, purpose: .use, at: now)
        let changed = try #require(store.record(for: "cache"))
        #expect(changed.progress?.intervalDays == 1)
        #expect(changed.progress?.reviews == 1)
        #expect(changed.progress?.dueAt == now.addingTimeInterval(86_400))
        #expect(changed.reviewedPurpose == .use)
        #expect(changed.overridePurpose == .use)
        #expect(changed.encounterDates == ["2026-11-18"])
    }

    @Test("Switching either learning target restarts spacing without changing intent or encounter evidence",
          arguments: [LearningPurpose.use, .understand])
    func changingLearningTargetRestartsProgress(first: LearningPurpose) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LearningStore(directoryURL: root)
        let now = date("2026-11-18T12:00:00Z")
        let second: LearningPurpose = first == .use ? .understand : .use
        try store.setPurpose(.use, for: "Cache")
        try store.recordEncounter("cache", at: now)
        for _ in 0..<5 { try store.rate("cache", rating: .good, purpose: first, at: now) }
        let mature = try #require(store.record(for: "Cache"))
        #expect(mature.progress?.intervalDays == 26)
        #expect(mature.reviewedPurpose == first)
        let reloaded = LearningStore(directoryURL: root)
        #expect(reloaded.record(for: "cache") == mature)
        let changedAt = now.addingTimeInterval(86_400 * 30)
        try reloaded.rate("cache", rating: .good, purpose: second, at: changedAt)
        let changed = try #require(reloaded.record(for: "Cache"))
        #expect(changed.reviewedPurpose == second)
        #expect(changed.progress?.intervalDays == 1)
        #expect(changed.progress?.reviews == 1)
        #expect(changed.progress?.dueAt == changedAt.addingTimeInterval(86_400))
        #expect(changed.overridePurpose == mature.overridePurpose)
        #expect(changed.encounterDates == mature.encounterDates)
        #expect(LearningStore(directoryURL: root).record(for: "Cache") == changed)
    }

    @Test("Removing and undoing a collection entry preserves associated learning state")
    func deletionDoesNotEraseLearningState() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let words = WordStore(directoryURL: root)
        let store = LearningStore(directoryURL: root)
        try words.add("Cache")
        try store.setPurpose(.understand, for: "Cache")
        try store.rate("Cache", rating: .hard)
        let before = store.record(for: "Cache")
        try words.remove("Cache")
        #expect(words.words.isEmpty)
        #expect(store.record(for: "Cache") == before)
        try words.add("Cache")
        #expect(LearningStore(directoryURL: root).record(for: words.words[0]) == before)
    }

    @Test("Corrupt or unsupported learning files are preserved and all writes are blocked", arguments: ["{not json}", "{\"version\":2,\"profile\":{\"workDomain\":\"\",\"workScenarios\":[],\"lifeScenarios\":[],\"expressionGoals\":[]},\"records\":{}}"])
    func corruptFileProtection(raw: String) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("learning.json")
        let original = Data(raw.utf8)
        try original.write(to: file)
        let store = LearningStore(directoryURL: root)
        #expect(store.loadError != nil)
        #expect(throws: LearningStoreError.self) { try store.saveProfile(profile()) }
        #expect(throws: LearningStoreError.self) { try store.recordEncounter("cache") }
        #expect(throws: LearningStoreError.self) { try store.setPurpose(.use, for: "cache") }
        #expect(throws: LearningStoreError.self) { try store.rate("cache", rating: .good) }
        #expect(throws: LearningStoreError.self) { try store.clearProgress(for: "cache") }
        #expect(store.records.isEmpty)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test("Semantically invalid persisted records cannot be silently used or overwritten")
    func invalidPersistedRecordsAreProtected() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let raw = """
        {"version":1,"profile":{"workDomain":"","workScenarios":[],"lifeScenarios":[],"expressionGoals":[]},
         "records":{"word:cache":{"encounterDates":["2026-02-31"],"progress":{"dueAt":0,"intervalDays":3,"reviews":1}}}}
        """
        let file = root.appendingPathComponent("learning.json")
        try Data(raw.utf8).write(to: file)
        let store = LearningStore(directoryURL: root)
        #expect(store.loadError != nil)
        #expect(throws: LearningStoreError.self) { try store.setPurpose(.use, for: "cache") }
        #expect(try String(contentsOf: file, encoding: .utf8) == raw)
    }

    @Test("Disk failures never publish a new profile or successful learning action")
    func diskFailureDoesNotPublishSuccess() throws {
        let blocked = directory()
        defer { try? FileManager.default.removeItem(at: blocked) }
        try Data("not a directory".utf8).write(to: blocked)
        let store = LearningStore(directoryURL: blocked)
        #expect(throws: (any Error).self) { try store.saveProfile(profile()) }
        #expect(throws: (any Error).self) { try store.recordEncounter("cache") }
        #expect(throws: (any Error).self) { try store.setPurpose(.use, for: "cache") }
        #expect(throws: (any Error).self) { try store.rate("cache", rating: .good) }
        #expect(store.profile == LearningProfile())
        #expect(store.records.isEmpty)
    }

    @Test("A failed replacement leaves prior disk bytes and published state unchanged")
    func failedReplacementPreservesState() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LearningStore(directoryURL: root)
        try store.setPurpose(.use, for: "cache")
        let before = store.records
        // A directory at the destination causes the atomic rename to fail,
        // even when the account running the test has broad filesystem access.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        let marker = store.fileURL.appendingPathComponent("preserve")
        let bytes = Data("existing target".utf8)
        try bytes.write(to: marker)
        #expect(throws: (any Error).self) { try store.setPurpose(.reference, for: "cache") }
        #expect(store.records == before)
        #expect(try Data(contentsOf: marker) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["learning.json"])
    }

    @Test("Invalid selections cannot create learning records")
    func invalidInputIsRejected() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LearningStore(directoryURL: root)
        for text in ["", "中文", "123", "cache\u{0000}", String(repeating: "a", count: 4_001)] {
            #expect(throws: LearningStoreError.self) { try store.recordEncounter(text) }
            #expect(throws: LearningStoreError.self) { try store.setPurpose(.use, for: text) }
            #expect(throws: LearningStoreError.self) { try store.rate(text, rating: .good) }
        }
        #expect(store.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("Recall performance changes future spacing, with no same-session due loop")
    func schedulerRespondsToPerformance() {
        let now = date("2026-11-18T12:00:00Z")
        var previous: LearningProgress?
        for expected in [1.0, 3, 7, 14, 26] {
            let next = LearningScheduler.next(previous: previous, rating: .good, at: now)
            #expect(next.intervalDays == expected)
            #expect(next.dueAt == now.addingTimeInterval(expected * 86_400))
            #expect(next.lastReviewedAt == now)
            #expect(next.reviews == (previous?.reviews ?? 0) + 1)
            previous = next
        }
        let hard = LearningScheduler.next(previous: previous, rating: .hard, at: now)
        let again = LearningScheduler.next(previous: previous, rating: .again, at: now)
        #expect(hard.intervalDays == 2)
        #expect(again.intervalDays == 1)
        #expect(hard.dueAt > now)
        #expect(again.dueAt > now)
        #expect(again.reviews == (previous?.reviews ?? 0) + 1)
        let later = now.addingTimeInterval(86_400 * 7)
        #expect(LearningScheduler.next(previous: previous, rating: .again, at: later).dueAt == later.addingTimeInterval(86_400))
    }
}
