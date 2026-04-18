import Foundation

// MARK: - Public models

/// Snapshot of disk content when a save conflict is detected (user may reload or overwrite).
struct EditorDocumentSaveConflict: Equatable {
    let fileURL: URL
    let diskText: String
}

enum EditorDocumentOpenError: Equatable, LocalizedError {
    case notAFile(URL)
    case unreadableUTF8(URL)
    case fileNotFound(URL)

    var errorDescription: String? {
        switch self {
        case let .notAFile(url):
            return "Not a regular file: \(url.path)"
        case let .unreadableUTF8(url):
            return "File is not valid UTF-8 text: \(url.path)"
        case let .fileNotFound(url):
            return "File not found: \(url.path)"
        }
    }
}

enum EditorDocumentSaveError: Equatable, LocalizedError {
    case conflict(EditorDocumentSaveConflict)
    case unreadableUTF8(URL)
    case fileNotFound(URL)
    case writeFailed(URL, underlying: String)

    var errorDescription: String? {
        switch self {
        case let .conflict(c):
            return "The file changed on disk: \(c.fileURL.lastPathComponent)"
        case let .unreadableUTF8(url):
            return "Could not read UTF-8 from disk: \(url.path)"
        case let .fileNotFound(url):
            return "File disappeared before save: \(url.path)"
        case let .writeFailed(url, underlying):
            return "Could not write \(url.path): \(underlying)"
        }
    }
}

enum EditorDocumentSaveOutcome: Equatable {
    /// Wrote working copy to disk.
    case wrote
    /// Buffer matched disk; refreshed metadata only.
    case noChanges
    /// Disk changed while buffer was clean; working copy refreshed from disk.
    case reloadedCleanFromDisk
}

/// Pane-local UTF-8 text buffer with explicit-save conflict detection.
@MainActor
struct EditorDocumentBuffer: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    /// Tab / window title (usually `lastPathComponent`).
    var title: String
    /// In-memory editing buffer.
    var workingText: String
    /// Content last known to match the file on disk (after load or successful save).
    var lastSyncedText: String
    var diskModificationDate: Date?
    var diskFileSize: Int64

    var isDirty: Bool {
        workingText != lastSyncedText
    }

    var standardizedPath: String {
        fileURL.standardizedFileURL.path
    }
}

// MARK: - Store

/// Owns open buffers, load/save, and conflict-safe writes. UI layers stay thin.
@MainActor
final class EditorDocumentStore {
    private var buffersById: [UUID: EditorDocumentBuffer] = [:]
    private var orderedIds: [UUID] = []
    /// Chains saves per buffer so concurrent `saveDocument` / `saveDocumentForcedOverwrite` calls cannot overlap detached writes.
    private var saveSerializationTail: [UUID: Task<EditorDocumentSaveOutcome, Error>] = [:]

    var buffersInTabOrder: [EditorDocumentBuffer] {
        orderedIds.compactMap { buffersById[$0] }
    }

    func buffer(id: UUID) -> EditorDocumentBuffer? {
        buffersById[id]
    }

    /// Opens a new buffer or returns the existing tab id for the same standardized file URL.
    func openDocument(at fileURL: URL, fileManager: FileManager = .default) throws -> UUID {
        let url = fileURL.standardizedFileURL
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw EditorDocumentOpenError.fileNotFound(url)
        }
        guard !isDir.boolValue else {
            throw EditorDocumentOpenError.notAFile(url)
        }
        if let existing = orderedIds.compactMap({ buffersById[$0] }).first(where: {
            $0.fileURL.standardizedFileURL == url
        }) {
            return existing.id
        }

        let (text, mtime, size) = try Self.readUTF8ForOpen(at: url, fileManager: fileManager)
        let id = UUID()
        let buffer = EditorDocumentBuffer(
            id: id,
            fileURL: url,
            title: url.lastPathComponent,
            workingText: text,
            lastSyncedText: text,
            diskModificationDate: mtime,
            diskFileSize: size
        )
        buffersById[id] = buffer
        orderedIds.append(id)
        return id
    }

    func updateWorkingText(id: UUID, text: String) {
        guard var b = buffersById[id] else { return }
        b.workingText = text
        buffersById[id] = b
    }

    /// Removes the buffer from the pane. Caller should confirm when `isDirty`.
    func closeBuffer(id: UUID) {
        buffersById[id] = nil
        orderedIds.removeAll { $0 == id }
        saveSerializationTail[id] = nil
    }

    /// Re-reads disk into the working buffer, discarding unsaved edits.
    func reloadFromDisk(id: UUID, fileManager: FileManager = .default) throws {
        guard var b = buffersById[id] else { return }
        let (text, mtime, size) = try Self.readUTF8ForOpen(at: b.fileURL, fileManager: fileManager)
        b.workingText = text
        b.lastSyncedText = text
        b.diskModificationDate = mtime
        b.diskFileSize = size
        buffersById[id] = b
    }

    /// Persists `workingText` when safe. Throws `EditorDocumentSaveError.conflict` when disk diverged while dirty.
    func saveDocument(id: UUID, fileManager: FileManager = .default) async throws -> EditorDocumentSaveOutcome {
        try await runSaveSerially(for: id) {
            try await self.saveDocumentUnsynchronized(id: id, fileManager: fileManager)
        }
    }

    private func saveDocumentUnsynchronized(id: UUID, fileManager: FileManager) async throws -> EditorDocumentSaveOutcome {
        guard var b = buffersById[id] else { return .noChanges }

        let attrs = try? fileManager.attributesOfItem(atPath: b.fileURL.path)
        let currentMtime = attrs?[.modificationDate] as? Date
        let currentSize = (attrs?[.size] as? NSNumber)?.int64Value ?? -1

        let diskChanged =
            currentMtime != b.diskModificationDate || currentSize != b.diskFileSize

        if diskChanged {
            let (diskText, newMtime, newSize) = try Self.readUTF8ForSave(at: b.fileURL, fileManager: fileManager)
            if diskText != b.lastSyncedText {
                if b.isDirty {
                    throw EditorDocumentSaveError.conflict(
                        EditorDocumentSaveConflict(fileURL: b.fileURL, diskText: diskText)
                    )
                }
                // Clean buffer but metadata or touched file: adopt disk.
                b.workingText = diskText
                b.lastSyncedText = diskText
                b.diskModificationDate = newMtime
                b.diskFileSize = newSize
                buffersById[id] = b
                return .reloadedCleanFromDisk
            }
            // mtime/size noise only; refresh token.
            b.diskModificationDate = newMtime
            b.diskFileSize = newSize
            buffersById[id] = b
        }

        if !b.isDirty {
            return .noChanges
        }

        let textToWrite = b.workingText
        let url = b.fileURL
        do {
            try await Self.writeUTF8AtomicallyOffMainThread(textToWrite, to: url)
        } catch {
            throw EditorDocumentSaveError.writeFailed(url, underlying: error.localizedDescription)
        }

        let afterAttrs = try? fileManager.attributesOfItem(atPath: url.path)
        guard var updated = buffersById[id] else { return .noChanges }
        let fallbackSize = Self.utf8DiskByteCount(for: textToWrite)
        updated.lastSyncedText = textToWrite
        updated.diskModificationDate = afterAttrs?[.modificationDate] as? Date
        updated.diskFileSize = (afterAttrs?[.size] as? NSNumber)?.int64Value ?? fallbackSize
        buffersById[id] = updated
        return .wrote
    }

    /// Writes the working copy even when disk content diverged from `lastSyncedText`. Use only after explicit user opt-in.
    func saveDocumentForcedOverwrite(id: UUID, fileManager: FileManager = .default) async throws
        -> EditorDocumentSaveOutcome
    {
        try await runSaveSerially(for: id) {
            try await self.saveDocumentForcedOverwriteUnsynchronized(id: id, fileManager: fileManager)
        }
    }

    private func saveDocumentForcedOverwriteUnsynchronized(id: UUID, fileManager: FileManager) async throws
        -> EditorDocumentSaveOutcome
    {
        guard let b = buffersById[id] else { return .noChanges }
        let textToWrite = b.workingText
        let url = b.fileURL
        do {
            try await Self.writeUTF8AtomicallyOffMainThread(textToWrite, to: url)
        } catch {
            throw EditorDocumentSaveError.writeFailed(url, underlying: error.localizedDescription)
        }
        let afterAttrs = try? fileManager.attributesOfItem(atPath: url.path)
        guard var updated = buffersById[id] else { return .noChanges }
        let fallbackSize = Self.utf8DiskByteCount(for: textToWrite)
        updated.lastSyncedText = textToWrite
        updated.diskModificationDate = afterAttrs?[.modificationDate] as? Date
        updated.diskFileSize = (afterAttrs?[.size] as? NSNumber)?.int64Value ?? fallbackSize
        buffersById[id] = updated
        return .wrote
    }

    private func runSaveSerially(
        for bufferId: UUID,
        _ body: @escaping @MainActor () async throws -> EditorDocumentSaveOutcome
    ) async throws -> EditorDocumentSaveOutcome {
        let predecessor = saveSerializationTail[bufferId]
        let next = Task { @MainActor in
            if let predecessor {
                _ = try? await predecessor.value
            }
            return try await body()
        }
        saveSerializationTail[bufferId] = next
        return try await next.value
    }

    /// Byte length of `text` as UTF-8 on disk (matches what `String.write(..., encoding: .utf8)` writes).
    private static func utf8DiskByteCount(for text: String) -> Int64 {
        Int64(text.utf8.count)
    }

    private static func writeUTF8AtomicallyOffMainThread(_ text: String, to url: URL) async throws {
        try await Task.detached {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }

    private static func readUTF8ForOpen(
        at url: URL,
        fileManager: FileManager
    ) throws -> (text: String, mtime: Date?, size: Int64) {
        guard fileManager.fileExists(atPath: url.path) else {
            throw EditorDocumentOpenError.fileNotFound(url)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let text = String(data: data, encoding: .utf8) else {
            throw EditorDocumentOpenError.unreadableUTF8(url)
        }
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let mtime = attrs?[.modificationDate] as? Date
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? Int64(data.count)
        return (text, mtime, size)
    }

    private static func readUTF8ForSave(
        at url: URL,
        fileManager: FileManager
    ) throws -> (text: String, mtime: Date?, size: Int64) {
        do {
            return try readUTF8ForOpen(at: url, fileManager: fileManager)
        } catch let open as EditorDocumentOpenError {
            switch open {
            case let .fileNotFound(u):
                throw EditorDocumentSaveError.fileNotFound(u)
            case let .unreadableUTF8(u):
                throw EditorDocumentSaveError.unreadableUTF8(u)
            case let .notAFile(u):
                throw EditorDocumentSaveError.writeFailed(u, underlying: "not a regular file")
            }
        }
    }
}
