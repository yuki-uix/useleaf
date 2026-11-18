import Combine
import CryptoKit
import Darwin
import Foundation

public enum LearningPurpose: String, Codable, CaseIterable, Sendable {
    case use
    case understand
    case reference

    public var title: String {
        switch self {
        case .use: return "希望会用"
        case .understand: return "看懂即可"
        case .reference: return "暂存参考"
        }
    }
}

public struct LearningProfile: Codable, Equatable, Sendable {
    public var workDomain: String
    public var workScenarios: [String]
    public var lifeScenarios: [String]
    public var expressionGoals: [String]
    public var options: LearningProfileOptions?

    public init(workDomain: String = "", workScenarios: [String] = [], lifeScenarios: [String] = [], expressionGoals: [String] = [], options: LearningProfileOptions? = nil) {
        self.workDomain = workDomain
        self.workScenarios = workScenarios
        self.lifeScenarios = lifeScenarios
        self.expressionGoals = expressionGoals
        self.options = options
    }

    public var isConfigured: Bool {
        (workScenarios + lifeScenarios).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A stable content fingerprint, rather than Swift's per-process randomized hash.
    /// Reordering scenarios or changing whitespace/case does not invalidate recommendations.
    public var fingerprint: String {
        func key(_ text: String) -> String {
            text.precomposedStringWithCanonicalMapping
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
        }
        let canonical = LearningProfile(
            workDomain: key(workDomain),
            workScenarios: Array(Set(workScenarios.map(key).filter { !$0.isEmpty })).sorted(),
            lifeScenarios: Array(Set(lifeScenarios.map(key).filter { !$0.isEmpty })).sorted(),
            expressionGoals: Array(Set(expressionGoals.map(key).filter { !$0.isEmpty })).sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(canonical)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public var validationMessage: String? {
        if let options, let message = options.validationMessage { return message }
        let value = cleaned
        if value.workDomain.count > 120 { return "工作领域最多填写 120 个字符。" }
        if value.workScenarios.count > 3 { return "工作场景最多填写 3 条。" }
        if value.lifeScenarios.count > 3 { return "生活场景最多填写 3 条。" }
        if value.expressionGoals.count > 5 { return "想表达的意思最多填写 5 条。" }
        if (value.workScenarios + value.lifeScenarios + value.expressionGoals).contains(where: { $0.count > 500 }) {
            return "每条场景或表达目标最多填写 500 个字符。"
        }
        let permitted: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        if ([value.workDomain] + value.workScenarios + value.lifeScenarios + value.expressionGoals).contains(where: { text in
            text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && !permitted.contains($0) }
        }) { return "场景中含有不支持的控制字符，请删除后重试。" }
        if !value.isConfigured { return "请至少填写一条工作或生活场景。" }
        return nil
    }

    fileprivate var cleaned: LearningProfile {
        func lines(_ values: [String]) -> [String] {
            values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return LearningProfile(workDomain: workDomain.trimmingCharacters(in: .whitespacesAndNewlines),
                               workScenarios: lines(workScenarios), lifeScenarios: lines(lifeScenarios),
                               expressionGoals: lines(expressionGoals), options: options)
    }
}

public enum ReviewRating: String, Codable, CaseIterable, Sendable {
    case again
    case hard
    case good

    public var title: String {
        switch self {
        case .again: return "想不起来"
        case .hard: return "需要提示"
        case .good: return "能独立表达"
        }
    }
}

public struct LearningProgress: Codable, Equatable, Sendable {
    public var dueAt: Date
    public var intervalDays: Double
    public var reviews: Int
    public var lastReviewedAt: Date?

    public init(dueAt: Date = Date(), intervalDays: Double = 0, reviews: Int = 0, lastReviewedAt: Date? = nil) {
        self.dueAt = dueAt
        self.intervalDays = intervalDays
        self.reviews = reviews
        self.lastReviewedAt = lastReviewedAt
    }
}

public struct LearningRecord: Codable, Equatable, Sendable {
    public var overridePurpose: LearningPurpose?
    public var encounterDates: [String]
    public var progress: LearningProgress?
    public var reviewedPurpose: LearningPurpose?

    public init(overridePurpose: LearningPurpose? = nil, encounterDates: [String] = [], progress: LearningProgress? = nil, reviewedPurpose: LearningPurpose? = nil) {
        self.overridePurpose = overridePurpose
        self.encounterDates = encounterDates
        self.progress = progress
        self.reviewedPurpose = reviewedPurpose
    }
}

/// A deliberately simple scheduling heuristic. These intervals are product
/// defaults, not a claim that a fixed sequence is scientifically optimal.
public enum LearningScheduler {
    public static func next(previous: LearningProgress?, rating: ReviewRating, at: Date) -> LearningProgress {
        let date = at.timeIntervalSinceReferenceDate.isFinite ? at : Date(timeIntervalSinceReferenceDate: 0)
        let oldInterval = previous?.intervalDays ?? 0
        let interval = oldInterval.isFinite && oldInterval >= 0 ? oldInterval : 0
        let days: Double
        switch rating {
        case .again:
            // Do not create an endless same-session loop for difficult items.
            days = 1
        case .hard:
            days = min(2, max(1, interval / 2))
        case .good:
            if interval == 0 { days = 1 }
            else if interval < 2 { days = 3 }
            else if interval < 5 { days = 7 }
            else if interval < 10 { days = 14 }
            else { days = min(180, ceil(interval * 1.8)) }
        }
        let previousReviews = max(0, previous?.reviews ?? 0)
        return LearningProgress(dueAt: date.addingTimeInterval(days * 86_400), intervalDays: days,
                                reviews: previousReviews == Int.max ? Int.max : previousReviews + 1,
                                lastReviewedAt: date)
    }
}

public enum LearningStoreError: LocalizedError {
    case invalidSelection
    case invalidProfile(String)
    case unreadableState(String)
    case invalidState

    public var errorDescription: String? {
        switch self {
        case .invalidSelection: return "这段原文不能作为学习条目。"
        case .invalidProfile(let detail): return detail
        case .unreadableState(let detail): return "学习资料未能读取，原文件已保留，暂时无法保存更改。\(detail)"
        case .invalidState: return "学习资料格式或版本不受支持，原文件已保留。"
        }
    }
}

@MainActor
public final class LearningStore: ObservableObject {
    @Published public private(set) var profile = LearningProfile()
    @Published public private(set) var records: [String: LearningRecord] = [:]
    public private(set) var loadError: String?
    public let fileURL: URL

    private struct Snapshot: Codable {
        var version = 1
        var profile: LearningProfile
        var records: [String: LearningRecord]
    }

    public init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.yuki.wordshelf", isDirectory: true)
        fileURL = directory.appendingPathComponent("learning.json")
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
            guard saved.version == 1,
                  saved.profile == saved.profile.cleaned,
                  (!saved.profile.isConfigured && saved.profile == LearningProfile()) || saved.profile.validationMessage == nil,
                  saved.records.allSatisfy({ Self.valid(key: $0.key, record: $0.value) }) else {
                throw LearningStoreError.invalidState
            }
            profile = saved.profile
            records = saved.records
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func saveProfile(_ profile: LearningProfile) throws {
        try ensureReadable()
        if let message = profile.validationMessage { throw LearningStoreError.invalidProfile(message) }
        let updated = profile.cleaned
        guard updated != self.profile else { return }
        try persist(profile: updated, records: records)
        self.profile = updated
    }

    public func recordEncounter(_ word: String, at: Date = Date()) throws {
        try ensureReadable()
        let key = try identity(word)
        guard at.timeIntervalSinceReferenceDate.isFinite else { throw LearningStoreError.invalidState }
        let day = Self.dayFormatter().string(from: at)
        var record = records[key] ?? LearningRecord()
        guard !record.encounterDates.contains(day) else { return }
        record.encounterDates.append(day)
        record.encounterDates.sort()
        try save(record, key: key)
    }

    public func setPurpose(_ purpose: LearningPurpose?, for word: String) throws {
        try ensureReadable()
        let key = try identity(word)
        var record = records[key] ?? LearningRecord()
        guard record.overridePurpose != purpose else { return }
        record.overridePurpose = purpose
        try save(record, key: key)
    }

    public func rate(_ word: String, rating: ReviewRating, purpose: LearningPurpose? = nil, at: Date = Date()) throws {
        try ensureReadable()
        let key = try identity(word)
        guard at.timeIntervalSinceReferenceDate.isFinite else { throw LearningStoreError.invalidState }
        var record = records[key] ?? LearningRecord()
        // Recognizing a meaning and independently producing an expression are
        // different targets. Mastery in one must not postpone practice in the other.
        let previous = purpose != nil && purpose != record.reviewedPurpose ? nil : record.progress
        record.progress = LearningScheduler.next(previous: previous, rating: rating, at: at)
        if let purpose { record.reviewedPurpose = purpose }
        try save(record, key: key)
    }

    public func record(for word: String) -> LearningRecord? {
        guard let key = SelectionText.identity(word) else { return nil }
        return records[key]
    }

    public func clearProgress(for word: String) throws {
        try ensureReadable()
        let key = try identity(word)
        guard var record = records[key], record.progress != nil || record.reviewedPurpose != nil else { return }
        record.progress = nil
        record.reviewedPurpose = nil
        try save(record, key: key)
    }

    private func identity(_ word: String) throws -> String {
        guard let key = SelectionText.identity(word) else { throw LearningStoreError.invalidSelection }
        return key
    }

    private func ensureReadable() throws {
        if let loadError { throw LearningStoreError.unreadableState(loadError) }
    }

    private func save(_ record: LearningRecord, key: String) throws {
        var updated = records
        updated[key] = record
        try persist(profile: profile, records: updated)
        records = updated
    }

    private func persist(profile: LearningProfile, records: [String: LearningRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Snapshot(profile: profile, records: records))
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".learning-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Rename is atomic on the same volume. The new file already has 0600
        // permissions before becoming visible under the persistent filename.
        guard rename(temporary.path, fileURL.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    private static func valid(key: String, record: LearningRecord) -> Bool {
        let original: String
        if key.hasPrefix("word:") { original = String(key.dropFirst(5)) }
        else if key.hasPrefix("text:") { original = String(key.dropFirst(5)) }
        else { return false }
        guard SelectionText.identity(original) == key,
              record.encounterDates == Array(Set(record.encounterDates)).sorted() else { return false }
        let formatter = dayFormatter()
        guard record.encounterDates.allSatisfy({ day in
            day.count == 10 && formatter.date(from: day).map { formatter.string(from: $0) == day } == true
        }) else { return false }
        guard let progress = record.progress else { return true }
        return progress.dueAt.timeIntervalSinceReferenceDate.isFinite
            && progress.intervalDays.isFinite && progress.intervalDays >= 0 && progress.intervalDays <= 180
            && progress.reviews >= 0
            && (progress.lastReviewedAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }
}
