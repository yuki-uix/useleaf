import AVFoundation
import Foundation

enum PronunciationAccent: String, CaseIterable, Sendable {
    case british
    case american

    var languageCode: String {
        switch self {
        case .british: return "en-GB"
        case .american: return "en-US"
        }
    }

    var title: String {
        switch self {
        case .british: return "英式"
        case .american: return "美式"
        }
    }
}

@MainActor
protocol Pronouncing: AnyObject {
    var isSpeaking: Bool { get }
    var onSpeakingChanged: ((Bool) -> Void)? { get set }
    func speak(_ text: String, accent: PronunciationAccent) throws
    func stop()
}

enum PronunciationError: LocalizedError, Equatable {
    case emptyText
    case noVoice(PronunciationAccent)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "请输入需要朗读的英文。"
        case .noVoice(let accent):
            return "本机没有可用的\(accent.title)英语朗读语音。请在系统设置 → 辅助功能 → 朗读内容（或朗读与语音）中管理语音，添加\(accent.title)英语（\(accent.languageCode)）语音后重试。"
        }
    }
}

/// A small seam for exercising cancellation without playing audio in tests.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var delegate: (any AVSpeechSynthesizerDelegate)? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    @discardableResult func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

/// Uses only voices already installed on the Mac. It never requests a voice
/// download or microphone, speech-recognition, or Personal Voice authorization.
@MainActor
final class PronunciationService: NSObject, Pronouncing, AVSpeechSynthesizerDelegate {
    private let synthesizer: any SpeechSynthesizing
    private let makeUtterance: @MainActor (String, PronunciationAccent) throws -> AVSpeechUtterance
    private var activeUtteranceID: ObjectIdentifier?

    private(set) var isSpeaking = false
    var onSpeakingChanged: ((Bool) -> Void)?

    override convenience init() {
        self.init(synthesizer: AVSpeechSynthesizer())
    }

    init(
        synthesizer: any SpeechSynthesizing,
        makeUtterance: @escaping @MainActor (String, PronunciationAccent) throws -> AVSpeechUtterance = {
            try PronunciationService.makeEnglishUtterance($0, accent: $1)
        }
    ) {
        self.synthesizer = synthesizer
        self.makeUtterance = makeUtterance
        super.init()
        synthesizer.delegate = self
    }

    isolated deinit {
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speak(_ text: String, accent: PronunciationAccent) throws {
        // Invalidate the old identity before stopping: cancellation may arrive
        // immediately or after the next utterance has already started.
        stop()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PronunciationError.emptyText }

        let utterance = try makeUtterance(text, accent)
        activeUtteranceID = ObjectIdentifier(utterance)
        setSpeaking(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        activeUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        setSpeaking(false)
    }

    static func makeEnglishUtterance(
        _ text: String,
        accent: PronunciationAccent,
        voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) throws -> AVSpeechUtterance {
        // Resolving an identifier returns nil for a voice that is not installed.
        // Never leave utterance.voice nil, which could read English using the
        // system's Chinese default voice.
        let matchingVoices = voices.filter {
            $0.language.replacingOccurrences(of: "_", with: "-")
                .lowercased() == accent.languageCode.lowercased()
                && !$0.voiceTraits.contains(.isPersonalVoice)
                && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        let preferredID = AVSpeechSynthesisVoice(language: accent.languageCode)?.identifier
        let ordered = matchingVoices.sorted { lhs, rhs in
            if (lhs.identifier == preferredID) != (rhs.identifier == preferredID) {
                return lhs.identifier == preferredID
            }
            if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
            return lhs.identifier < rhs.identifier
        }
        guard let voice = ordered.lazy.compactMap({ AVSpeechSynthesisVoice(identifier: $0.identifier) }).first else {
            throw PronunciationError.noVoice(accent)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }

    private func setSpeaking(_ value: Bool) {
        guard isSpeaking != value else { return }
        isSpeaking = value
        onSpeakingChanged?(value)
    }

    private func completed(_ id: ObjectIdentifier) {
        guard activeUtteranceID == id else { return }
        activeUtteranceID = nil
        setSpeaking(false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let completion = UtteranceCompletion(utterance)
        // AVFoundation delegate callbacks are not MainActor-isolated. Transfer
        // an immutable identity and keep its object alive until delivery so an
        // allocator cannot reuse the address for a newer utterance.
        Task { @MainActor [weak self] in self?.completed(completion.id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let completion = UtteranceCompletion(utterance)
        Task { @MainActor [weak self] in self?.completed(completion.id) }
    }
}

/// Only the immutable identity is read across actors. The private reference
/// extends lifetime; neither actor reads or mutates the utterance through it.
private final class UtteranceCompletion: @unchecked Sendable {
    let id: ObjectIdentifier
    private let retainedUtterance: AVSpeechUtterance

    init(_ utterance: AVSpeechUtterance) {
        id = ObjectIdentifier(utterance)
        retainedUtterance = utterance
    }
}
