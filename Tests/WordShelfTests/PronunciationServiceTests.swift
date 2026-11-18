import AVFoundation
import Testing
@testable import WordShelf

@MainActor
private final class ControlledSpeechSynthesizer: SpeechSynthesizing {
    weak var delegate: (any AVSpeechSynthesizerDelegate)?
    private(set) var utterances: [AVSpeechUtterance] = []
    private(set) var boundaries: [AVSpeechBoundary] = []
    var cancelledUtteranceOnStop: AVSpeechUtterance?
    private let callbackSynthesizer = AVSpeechSynthesizer()

    func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        boundaries.append(boundary)
        if let utterance = cancelledUtteranceOnStop {
            cancelledUtteranceOnStop = nil
            delegate?.speechSynthesizer?(callbackSynthesizer, didCancel: utterance)
        }
        return true
    }

    func finish(_ utterance: AVSpeechUtterance) {
        delegate?.speechSynthesizer?(callbackSynthesizer, didFinish: utterance)
    }

    func cancel(_ utterance: AVSpeechUtterance) {
        delegate?.speechSynthesizer?(callbackSynthesizer, didCancel: utterance)
    }
}

@Suite("Local English pronunciation")
@MainActor
struct PronunciationServiceTests {
    private func makeService(_ engine: ControlledSpeechSynthesizer) -> PronunciationService {
        // No system voice or audio output is needed to test the playback state
        // machine. Production uses makeEnglishUtterance instead of this seam.
        PronunciationService(synthesizer: engine, makeUtterance: { text, _ in AVSpeechUtterance(string: text) })
    }

    private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }

    @Test func newSpeechStopsThePreviousUtteranceAndIgnoresItsLateCallbacks() async throws {
        let engine = ControlledSpeechSynthesizer()
        let service = makeService(engine)
        var states: [Bool] = []
        service.onSpeakingChanged = { states.append($0) }
        try service.speak("first", accent: .american)
        let first = try #require(engine.utterances.first)
        // Exercise a cancellation callback emitted inside the replacement's
        // stop call as well as callbacks arriving after the new speech starts.
        engine.cancelledUtteranceOnStop = first
        try service.speak("second", accent: .british)
        let second = try #require(engine.utterances.last)
        #expect(first !== second)
        #expect(engine.utterances.map(\.speechString) == ["first", "second"])
        #expect(engine.boundaries == [.immediate, .immediate])
        engine.finish(first)
        engine.cancel(first)
        for _ in 0..<20 { await Task.yield() }
        #expect(service.isSpeaking)
        #expect(states == [true, false, true])

        engine.finish(second)
        #expect(await waitFor { !service.isSpeaking })
        #expect(states == [true, false, true, false])
    }

    @Test func explicitStopIsImmediateAndLateCallbacksCannotRestartIt() async throws {
        let engine = ControlledSpeechSynthesizer()
        let service = makeService(engine)
        var states: [Bool] = []
        service.onSpeakingChanged = { states.append($0) }
        try service.speak("Keep reading.\nTry another sentence!", accent: .american)
        let utterance = try #require(engine.utterances.first)
        service.stop()
        #expect(!service.isSpeaking)
        #expect(engine.boundaries.last == .immediate)
        engine.finish(utterance)
        engine.cancel(utterance)
        service.stop()
        for _ in 0..<20 { await Task.yield() }
        #expect(!service.isSpeaking)
        #expect(states == [true, false])
    }

    @Test func cancellationOfCurrentUtteranceClearsSpeakingState() async throws {
        let engine = ControlledSpeechSynthesizer()
        let service = makeService(engine)
        try service.speak("cache", accent: .american)
        engine.cancel(try #require(engine.utterances.first))
        #expect(await waitFor { !service.isSpeaking })
    }

    @Test func blankTextStopsOldSpeechAndDoesNotSubmitAnotherUtterance() throws {
        let engine = ControlledSpeechSynthesizer()
        let service = makeService(engine)
        try service.speak("word", accent: .american)
        #expect(throws: PronunciationError.emptyText) { try service.speak(" \n\t ", accent: .british) }
        #expect(!service.isSpeaking)
        #expect(engine.utterances.count == 1)
    }

    @Test(arguments: PronunciationAccent.allCases)
    func missingVoiceReportsSystemSettingsWithoutStartingSpeech(accent: PronunciationAccent) {
        let engine = ControlledSpeechSynthesizer()
        let service = PronunciationService(synthesizer: engine, makeUtterance: { text, accent in
            try PronunciationService.makeEnglishUtterance(text, accent: accent, voices: [])
        })
        #expect(throws: PronunciationError.noVoice(accent)) { try service.speak("word", accent: accent) }
        #expect(!service.isSpeaking)
        #expect(engine.utterances.isEmpty)
        #expect(PronunciationError.noVoice(accent).localizedDescription.contains("系统设置"))
        #expect(PronunciationError.noVoice(accent).localizedDescription.contains(accent.title))
        #expect(PronunciationError.noVoice(accent).localizedDescription.contains(accent.languageCode))
    }

    @Test(arguments: PronunciationAccent.allCases)
    func nonEnglishAndNoveltyVoicesNeverBecomeAFallback(accent: PronunciationAccent) {
        let ineligibleVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.language.lowercased().hasPrefix("en-")
                || $0.voiceTraits.contains(.isNoveltyVoice)
                || $0.voiceTraits.contains(.isPersonalVoice)
        }
        #expect(throws: PronunciationError.noVoice(accent)) {
            try PronunciationService.makeEnglishUtterance("cache", accent: accent, voices: ineligibleVoices)
        }
    }

    @Test func serviceRoutesTheRequestedAccentWhenReplacingSpeech() throws {
        let engine = ControlledSpeechSynthesizer()
        var requestedAccents: [PronunciationAccent] = []
        let service = PronunciationService(synthesizer: engine, makeUtterance: { text, accent in
            requestedAccents.append(accent)
            return AVSpeechUtterance(string: text)
        })
        let sentence = "The API is idempotent.\nKeep its original punctuation!"
        try service.speak(sentence, accent: .british)
        try service.speak(sentence, accent: .american)
        #expect(requestedAccents == [.british, .american])
        #expect(engine.utterances.map(\.speechString) == [sentence, sentence])
        #expect(engine.boundaries == [.immediate, .immediate])
        #expect(service.isSpeaking)
    }

    @Test(arguments: PronunciationAccent.allCases)
    func factoryNeverSubstitutesAnotherRegion(accent: PronunciationAccent) {
        let otherVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.replacingOccurrences(of: "_", with: "-").lowercased() != accent.languageCode.lowercased()
        }
        #expect(throws: PronunciationError.noVoice(accent)) {
            try PronunciationService.makeEnglishUtterance("cache", accent: accent, voices: otherVoices)
        }
    }

    @Test(arguments: PronunciationAccent.allCases)
    func productionFactoryKeepsSentenceAndUsesOnlyTheExactInstalledAccent(accent: PronunciationAccent) throws {
        let installedVoices = AVSpeechSynthesisVoice.speechVoices()
        let matching = installedVoices.filter {
            $0.language.lowercased() == accent.languageCode.lowercased()
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice)
                && AVSpeechSynthesisVoice(identifier: $0.identifier) != nil
        }
        let sentence = "The API is idempotent, so retry it.\nKeep the original!"
        guard !matching.isEmpty else {
            #expect(throws: PronunciationError.noVoice(accent)) {
                try PronunciationService.makeEnglishUtterance(sentence, accent: accent, voices: installedVoices)
            }
            return
        }
        let utterance = try PronunciationService.makeEnglishUtterance(sentence, accent: accent, voices: installedVoices)
        let voice = try #require(utterance.voice)
        #expect(utterance.speechString == sentence)
        #expect(voice.language.lowercased() == accent.languageCode.lowercased())
        #expect(matching.contains { $0.identifier == voice.identifier })
        #expect(!voice.voiceTraits.contains(.isNoveltyVoice))
        #expect(!voice.voiceTraits.contains(.isPersonalVoice))
    }

    @Test(arguments: PronunciationAccent.allCases)
    func speechKeepsInternalPunctuationAndNewlines(accent: PronunciationAccent) throws {
        let engine = ControlledSpeechSynthesizer()
        let service = makeService(engine)
        let original = "The API is idempotent, so retry it.\nKeep the original!"
        try service.speak(" \n\(original)\n ", accent: accent)
        #expect(engine.utterances.first?.speechString == original)
    }

    @Test func serviceStopsItsEngineWhenReleased() throws {
        let engine = ControlledSpeechSynthesizer()
        var service: PronunciationService? = makeService(engine)
        try service?.speak("word", accent: .american)
        let stopsBeforeRelease = engine.boundaries.count
        service = nil
        #expect(engine.delegate == nil)
        #expect(engine.boundaries.count == stopsBeforeRelease + 1)
        #expect(engine.boundaries.last == .immediate)
    }

    @Test func serviceStronglyRetainsItsEngine() throws {
        weak var retainedEngine: ControlledSpeechSynthesizer?
        var service: PronunciationService?
        do {
            let engine = ControlledSpeechSynthesizer()
            retainedEngine = engine
            service = makeService(engine)
        }
        #expect(retainedEngine != nil)
        try service?.speak("word", accent: .american)
        #expect(retainedEngine?.utterances.count == 1)
        service = nil
        #expect(retainedEngine == nil)
    }
}
