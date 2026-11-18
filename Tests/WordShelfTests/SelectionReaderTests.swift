import AppKit
import Testing
@testable import WordShelf

@Suite("Selection clipboard protection")
@MainActor
struct SelectionReaderTests {
    private func namedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("WordShelf-tests-\(UUID().uuidString)"))
    }

    private func replace(_ pasteboard: NSPasteboard, with text: String) {
        pasteboard.clearContents()
        #expect(pasteboard.setString(text, forType: .string))
    }

    @Test func snapshotRestoresMultipleItemsAndEveryDataType() throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let binaryType = NSPasteboard.PasteboardType("com.wordshelf.tests.binary")
        let binary = Data([0, 255, 1, 128, 34])
        let first = NSPasteboardItem()
        first.setString("original clipboard text", forType: .string)
        first.setData(binary, forType: binaryType)
        let second = NSPasteboardItem()
        second.setString("another item", forType: .string)
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([first, second]))
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)

        replace(pasteboard, with: "temporary selected word")
        #expect(snapshot.restore(to: pasteboard, ifUnchangedSince: pasteboard.changeCount))
        #expect(pasteboard.pasteboardItems?.count == 2)
        #expect(pasteboard.pasteboardItems?[0].string(forType: .string) == "original clipboard text")
        #expect(pasteboard.pasteboardItems?[0].data(forType: binaryType) == binary)
        #expect(pasteboard.pasteboardItems?[1].string(forType: .string) == "another item")
    }

    @Test func snapshotRestoresAnInitiallyEmptyClipboard() throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        replace(pasteboard, with: "temporary word")

        #expect(snapshot.restore(to: pasteboard, ifUnchangedSince: pasteboard.changeCount))
        #expect(pasteboard.pasteboardItems?.isEmpty != false)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func snapshotDoesNotOverwriteANewerClipboardVersion() throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "original")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        replace(pasteboard, with: "temporary word")
        let copiedVersion = pasteboard.changeCount
        replace(pasteboard, with: "new user copy")

        #expect(!snapshot.restore(to: pasteboard, ifUnchangedSince: copiedVersion))
        #expect(pasteboard.string(forType: .string) == "new user copy")
    }

    @Test func successfulCopyReturnsSelectionAndRestoresOriginal() async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "original")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        replace(pasteboard, with: "  ephemeral\n")
        let transaction = ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)

        let result = try await transaction.readCopiedText(isSourceFrontmost: { true }, pause: { _ in })
        #expect(result == "ephemeral")
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test("Phrase and sentence copy preserves the complete original", arguments: [
        "stick with",
        "The API is idempotent, so retry the request.",
        "Stick with the plan.\nRetry the request tomorrow."
    ])
    func completeSelectionCopy(source: String) async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "unrelated original clipboard")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        replace(pasteboard, with: source)
        let copied = try await ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)
            .readCopiedText(isSourceFrontmost: { true }, pause: { _ in })
        #expect(copied == source)
        #expect(pasteboard.string(forType: .string) == "unrelated original clipboard")
    }

    @Test func unchangedClipboardIsNeverUsedAsSelectedText() async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "unrelated previous copy")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        let transaction = ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)

        await #expect(throws: SelectionError.noSelection) {
            try await transaction.readCopiedText(isSourceFrontmost: { true }, timeoutMilliseconds: 0)
        }
        #expect(pasteboard.changeCount == snapshot.changeCount)
        #expect(pasteboard.string(forType: .string) == "unrelated previous copy")
    }

    @Test func focusChangeAfterCopyStillRestoresClipboard() async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "original")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        replace(pasteboard, with: "selection copied before focus changed")
        let transaction = ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)

        await #expect(throws: SelectionError.applicationChanged) {
            try await transaction.readCopiedText(isSourceFrontmost: { false }, pause: { _ in })
        }
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test func focusChangeBeforePendingCopyArrivesWaitsForCleanup() async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "original")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        let transaction = ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)
        var pendingCopyDelivered = false

        await #expect(throws: SelectionError.applicationChanged) {
            try await transaction.readCopiedText(isSourceFrontmost: { false }, pause: { milliseconds in
                if milliseconds == 20 && !pendingCopyDelivered {
                    pendingCopyDelivered = true
                    replace(pasteboard, with: "delayed selection")
                }
            })
        }
        #expect(pendingCopyDelivered)
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test func focusChangeWhileCopySettlesRejectsResultAndRestores() async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "original")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        replace(pasteboard, with: "selection")
        let transaction = ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)
        var frontmost = true

        await #expect(throws: SelectionError.applicationChanged) {
            try await transaction.readCopiedText(isSourceFrontmost: { frontmost }, pause: { _ in
                frontmost = false
            })
        }
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test func cancellationAfterPostingWaitsForPendingWriteAndRestores() async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "original")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        let transaction = ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)
        var pendingCopyDelivered = false
        let operation = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transaction.readCopiedText(isSourceFrontmost: { true }, pause: { milliseconds in
                if milliseconds == 20 && !pendingCopyDelivered {
                    pendingCopyDelivered = true
                    replace(pasteboard, with: "delayed selection")
                }
            })
        }

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(pendingCopyDelivered)
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test func secondClipboardWriteDuringCleanupIsPreserved() async throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        replace(pasteboard, with: "original")
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)
        replace(pasteboard, with: "selection")
        let transaction = ClipboardCopyTransaction(pasteboard: pasteboard, snapshot: snapshot)

        await #expect(throws: SelectionError.clipboardChanged) {
            try await transaction.readCopiedText(isSourceFrontmost: { false }, pause: { _ in
                replace(pasteboard, with: "new user copy")
            })
        }
        #expect(pasteboard.string(forType: .string) == "new user copy")
    }
}
