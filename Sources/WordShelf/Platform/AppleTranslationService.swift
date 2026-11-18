import Combine
import Foundation
import SwiftUI
@preconcurrency import Translation

@MainActor
protocol TextTranslating {
    func translate(_ text: String) async throws -> String
    func prepareLanguages() async throws
}

enum TranslationServiceError: LocalizedError, Equatable {
    case needsLanguages
    case unsupportedSystem
    case unsupportedPair
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .needsLanguages:
            return "首次使用句子翻译，需要启用 Apple 英语和简体中文语言包。"
        case .unsupportedSystem:
            return "句子翻译需要 macOS 15 或更新版本；当前仍可查询词典和管理生词本。"
        case .unsupportedPair:
            return "当前系统暂不支持英语到简体中文翻译。"
        case .failed(let message):
            return message
        }
    }
}

/// Uses Apple's local Translation framework. Normal queries never request a
/// language download; only the explicit prepare action may show system consent.
@MainActor
final class AppleTranslationService: ObservableObject, TextTranslating {
    fileprivate enum Operation {
        case translate(String)
        case prepare
    }

    fileprivate struct HostRequest: Identifiable {
        let id: UUID
        let hostID: UUID
        let operation: Operation
    }

    private struct Host {
        let order: UInt64
        var allowsPreparation: Bool
    }

    @MainActor
    private final class PendingRequest {
        let id: UUID
        let operation: Operation
        var continuation: CheckedContinuation<String, Error>?
        var claimed = false

        init(id: UUID, operation: Operation, continuation: CheckedContinuation<String, Error>) {
            self.id = id
            self.operation = operation
            self.continuation = continuation
        }
    }

    @Published fileprivate var hostRequest: HostRequest?
    private var pending: [UUID: PendingRequest] = [:]
    private var requestOrder: [UUID] = []
    private var hosts: [UUID: Host] = [:]
    private var hostOrder: UInt64 = 0
    private var hostWaitTask: Task<Void, Never>?
    private var hostWaitRequestID: UUID?
    private static let source = Locale.Language(identifier: "en")
    private static let target = Locale.Language(identifier: "zh-Hans")

    init() {}

    func translate(_ text: String) async throws -> String {
        guard #available(macOS 15.0, *) else { throw TranslationServiceError.unsupportedSystem }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationServiceError.failed("请输入需要翻译的英文。") }
        try Task.checkCancellation()
        let status = await Self.availability().status(from: Self.source, to: Self.target)
        try Task.checkCancellation()
        switch status {
        case .installed: break
        case .supported: throw TranslationServiceError.needsLanguages
        case .unsupported: throw TranslationServiceError.unsupportedPair
        @unknown default: throw TranslationServiceError.unsupportedPair
        }

        do {
            if #available(macOS 26.0, *) {
                // This initializer cannot download languages or show UI. Keep
                // the installed-language session scoped to this one operation.
                let operation = InstalledTranslationOperation(source: Self.source, target: Self.target)
                return try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    let translated = try await operation.translate(text)
                    try Task.checkCancellation()
                    return translated
                } onCancel: {
                    Task { @MainActor in operation.cancel() }
                }
            }
            return try await enqueue(.translate(text))
        } catch {
            throw Self.userFacingError(error)
        }
    }

    func prepareLanguages() async throws {
        guard #available(macOS 15.0, *) else { throw TranslationServiceError.unsupportedSystem }
        try Task.checkCancellation()
        let status = await Self.availability().status(from: Self.source, to: Self.target)
        try Task.checkCancellation()
        switch status {
        case .installed: return
        case .supported: break
        case .unsupported: throw TranslationServiceError.unsupportedPair
        @unknown default: throw TranslationServiceError.unsupportedPair
        }

        _ = try await enqueue(.prepare)
        try Task.checkCancellation()
        let installedStatus = await Self.availability().status(from: Self.source, to: Self.target)
        try Task.checkCancellation()
        guard installedStatus == .installed else { throw TranslationServiceError.needsLanguages }
    }

    @available(macOS 15.0, *)
    private static func availability() -> LanguageAvailability {
        if #available(macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .lowLatency)
        }
        return LanguageAvailability()
    }

    private func enqueue(_ operation: Operation) async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let request = PendingRequest(id: id, operation: operation, continuation: continuation)
                pending[id] = request
                requestOrder.append(id)
                scheduleNextRequest()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelRequest(id) }
        }
    }

    fileprivate func updateHost(_ id: UUID, isActive: Bool, allowsPreparation: Bool = false) {
        if isActive {
            if var host = hosts[id] {
                host.allowsPreparation = allowsPreparation
                hosts[id] = host
            } else {
                hostOrder &+= 1
                hosts[id] = Host(order: hostOrder, allowsPreparation: allowsPreparation)
            }
            if let request = hostRequest, request.hostID == id,
               let host = hosts[id], !isEligible(host, for: request.operation) {
                cancelRequest(request.id)
            }
        } else {
            hosts.removeValue(forKey: id)
            if hostRequest?.hostID == id, let requestID = hostRequest?.id {
                cancelRequest(requestID)
            }
        }
        scheduleNextRequest()
    }

    private func isEligible(_ host: Host, for operation: Operation) -> Bool {
        switch operation {
        case .prepare: return host.allowsPreparation
        case .translate: return true
        }
    }

    private func eligibleHost(for operation: Operation) -> UUID? {
        hosts.filter { isEligible($0.value, for: operation) }
            .max(by: { $0.value.order < $1.value.order })?.key
    }

    private func cancelHostWait() {
        hostWaitTask?.cancel()
        hostWaitTask = nil
        hostWaitRequestID = nil
    }

    private func scheduleNextRequest() {
        guard hostRequest == nil else { return }
        requestOrder.removeAll { pending[$0] == nil }
        guard let id = requestOrder.first, let request = pending[id] else {
            cancelHostWait()
            return
        }
        guard let hostID = eligibleHost(for: request.operation) else {
            // Window creation and SwiftUI attachment happen on subsequent
            // run-loop turns. Allow that handoff, but never leak a waiting
            // continuation if no eligible host appears. Queued work behind an
            // active translation/download is not subject to this host timeout.
            if hostWaitRequestID != id {
                cancelHostWait()
                hostWaitRequestID = id
                hostWaitTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                    guard let self, self.hostWaitRequestID == id else { return }
                    self.hostWaitTask = nil
                    self.hostWaitRequestID = nil
                    guard self.hostRequest == nil, let waiting = self.pending[id],
                          self.eligibleHost(for: waiting.operation) == nil else {
                        self.scheduleNextRequest()
                        return
                    }
                    let message: String
                    switch waiting.operation {
                    case .prepare: message = "请打开生词本后重试启用句子翻译。"
                    case .translate: message = "请保持生词本或查词窗口打开后重试翻译。"
                    }
                    self.complete(id, result: .failure(TranslationServiceError.failed(message)))
                }
            }
            return
        }
        cancelHostWait()
        hostRequest = HostRequest(id: id, hostID: hostID, operation: request.operation)
    }

    fileprivate func cancelRequest(_ id: UUID) {
        complete(id, result: .failure(CancellationError()))
    }

    private func complete(_ id: UUID, result: Result<String, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        requestOrder.removeAll { $0 == id }
        if hostRequest?.id == id { hostRequest = nil }
        let continuation = request.continuation
        request.continuation = nil
        continuation?.resume(with: result)
        scheduleNextRequest()
    }

    @available(macOS 15.0, *)
    fileprivate func execute(_ request: HostRequest, using session: TranslationSession) async {
        guard hostRequest?.id == request.id,
              hostRequest?.hostID == request.hostID,
              let host = hosts[request.hostID], isEligible(host, for: request.operation),
              let pendingRequest = pending[request.id], !pendingRequest.claimed else { return }
        pendingRequest.claimed = true
        do {
            try Task.checkCancellation()
            let result: String
            switch request.operation {
            case .prepare:
                try await session.prepareTranslation()
                result = ""
            case .translate(let text):
                result = try await session.translate(text).targetText
            }
            try Task.checkCancellation()
            complete(request.id, result: .success(result))
        } catch {
            complete(request.id, result: .failure(Self.userFacingError(error)))
        }
    }

    @available(macOS 15.0, *)
    private static func userFacingError(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        if let error = error as? TranslationServiceError { return error }
        if TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error
            || TranslationError.unsupportedLanguagePairing ~= error {
            return TranslationServiceError.unsupportedPair
        }
        if #available(macOS 26.0, *) {
            if TranslationError.notInstalled ~= error { return TranslationServiceError.needsLanguages }
            if TranslationError.alreadyCancelled ~= error { return CancellationError() }
        }
        return TranslationServiceError.failed("Apple 翻译暂时未能完成：\(error.localizedDescription)")
    }
}

@available(macOS 26.0, *)
@MainActor
private final class InstalledTranslationOperation {
    private let session: TranslationSession

    init(source: Locale.Language, target: Locale.Language) {
        if #available(macOS 26.4, *) {
            session = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
    }

    func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }

    func cancel() { session.cancel() }
}

extension View {
    /// `isActive` must follow the owning window's visibility. Only one host is
    /// assigned a given request, even if both app windows are visible. Only a
    /// normal app window should opt into preparation and its system sheets.
    @MainActor
    @ViewBuilder
    func wordShelfTranslationHost(
        _ service: AppleTranslationService,
        isActive: Bool,
        allowsPreparation: Bool = false
    ) -> some View {
        if #available(macOS 15.0, *) {
            modifier(WordShelfTranslationHost(
                service: service, isActive: isActive, allowsPreparation: allowsPreparation
            ))
        } else {
            self
        }
    }
}

@available(macOS 15.0, *)
@MainActor
private struct WordShelfTranslationHost: ViewModifier {
    @ObservedObject var service: AppleTranslationService
    let isActive: Bool
    let allowsPreparation: Bool
    @State private var hostID = UUID()

    func body(content: Content) -> some View {
        content
            .background {
                if isActive, let request = service.hostRequest, request.hostID == hostID {
                    WordShelfTranslationRequestView(service: service, request: request)
                        .id(request.id)
                        .frame(width: 0, height: 0)
                }
            }
            .onAppear {
                service.updateHost(hostID, isActive: isActive, allowsPreparation: allowsPreparation)
            }
            .onChange(of: isActive) { _, value in
                service.updateHost(hostID, isActive: value, allowsPreparation: allowsPreparation)
            }
            .onChange(of: allowsPreparation) { _, value in
                service.updateHost(hostID, isActive: isActive, allowsPreparation: value)
            }
            .onDisappear { service.updateHost(hostID, isActive: false) }
    }
}

@available(macOS 15.0, *)
@MainActor
private struct WordShelfTranslationRequestView: View {
    let service: AppleTranslationService
    let request: AppleTranslationService.HostRequest

    private var configuration: TranslationSession.Configuration {
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        if #available(macOS 26.4, *) {
            return TranslationSession.Configuration(source: source, target: target, preferredStrategy: .lowLatency)
        }
        return TranslationSession.Configuration(source: source, target: target)
    }

    var body: some View {
        Color.clear
            .translationTask(configuration) { session in
                await service.execute(request, using: session)
            }
            .onDisappear { service.cancelRequest(request.id) }
    }
}
