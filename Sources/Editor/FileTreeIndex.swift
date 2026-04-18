import Foundation

/// Raw directory entries scanned off the main thread; mapped to `FileTreeIndex.Node` on the main actor.
private struct FileTreeScannedEntry {
    let path: String
    let name: String
    let isDirectory: Bool
}

private enum FileTreeDirectoryScanner {
    /// `nil` means the directory could not be read (IO/permission); do not cache as an empty listing.
    nonisolated static func scan(path: String, fileManager: FileManager) -> [FileTreeScannedEntry]? {
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        guard
            let values = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        return values.compactMap { url in
            guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                return nil
            }
            return FileTreeScannedEntry(
                path: url.path,
                name: url.lastPathComponent,
                isDirectory: isDirectory == true
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

@MainActor
final class FileTreeIndex {
    struct Node: Identifiable, Hashable {
        let path: String
        let name: String
        let isDirectory: Bool
        let hasUnloadedChildren: Bool

        var id: String {
            path
        }
    }

    private let rootPath: String
    private let fileManager: FileManager
    private var childCache: [String: [Node]] = [:]
    private var contentGeneration: UInt = 0
    private var loadingPaths: Set<String> = []
    private var childrenDidChangeHandler: (() -> Void)?
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherFD: Int32 = -1
    private var pendingInvalidation = false
    private var invalidationWorkItem: DispatchWorkItem?
    private var isActive = true
    private var subscribers = 0
    var hasSubscribers: Bool {
        subscribers > 0
    }

    private var invalidationObservers: [UUID: () -> Void] = [:]

    func addInvalidationObserver(id: UUID, handler: @escaping () -> Void) {
        invalidationObservers[id] = handler
    }

    func removeInvalidationObserver(id: UUID) {
        invalidationObservers.removeValue(forKey: id)
    }

    init(rootPath: String, fileManager: FileManager = .default) {
        self.rootPath = rootPath
        self.fileManager = fileManager
    }

    func setChildrenDidChangeHandler(_ handler: (() -> Void)?) {
        childrenDidChangeHandler = handler
    }

    func retain() {
        subscribers += 1
        if subscribers == 1 {
            startWatcher()
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 {
            stopWatcher()
        }
    }

    func setActive(_ active: Bool) {
        let wasActive = isActive
        isActive = active
        if active, !wasActive, pendingInvalidation {
            pendingInvalidation = false
            invalidateAll()
        }
    }

    /// Snapshot of cached children for `path`, if a load has completed at least once for this key since the last invalidation.
    func cachedChildren(for path: String) -> [Node]? {
        childCache[path]
    }

    /// Enqueues an off-main directory scan; results merge on the main actor. Safe to call from SwiftUI actions / `onChange`.
    func scheduleLoadChildren(for path: String) {
        if childCache[path] != nil { return }
        if loadingPaths.contains(path) { return }
        loadingPaths.insert(path)
        let generation = contentGeneration
        let capturedPath = path
        let fm = fileManager
        Task.detached(priority: .utility) {
            let scanned = FileTreeDirectoryScanner.scan(path: capturedPath, fileManager: fm)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard generation == contentGeneration else {
                    loadingPaths.remove(capturedPath)
                    return
                }
                guard let scanned else {
                    loadingPaths.remove(capturedPath)
                    return
                }
                let nodes = scanned.map { entry in
                    Node(
                        path: entry.path,
                        name: entry.name,
                        isDirectory: entry.isDirectory,
                        hasUnloadedChildren: entry.isDirectory
                    )
                }
                childCache[capturedPath] = nodes
                loadingPaths.remove(capturedPath)
                childrenDidChangeHandler?()
            }
        }
    }

    private func invalidateAll() {
        contentGeneration += 1
        childCache.removeAll()
        loadingPaths.removeAll()
        let handlers = Array(invalidationObservers.values)
        for handler in handlers {
            handler()
        }
    }

    /// Invokes the same invalidation path used after the debounced filesystem watcher fires (for unit tests).
    func test_invalidateTreeCache() {
        invalidateAll()
    }

    private func queueInvalidation() {
        invalidationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.isActive {
                    self.invalidateAll()
                } else {
                    self.pendingInvalidation = true
                }
            }
        }
        invalidationWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func startWatcher() {
        stopWatcher()
        let rootPathNSString = rootPath as NSString
        watcherFD = open(rootPathNSString.fileSystemRepresentation, O_EVTONLY)
        guard watcherFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watcherFD,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.queueInvalidation()
            }
        }
        source.setCancelHandler { [fd = watcherFD] in
            if fd >= 0 {
                close(fd)
            }
        }
        watcher = source
        source.resume()
    }

    private func stopWatcher() {
        invalidationWorkItem?.cancel()
        invalidationWorkItem = nil
        watcher?.cancel()
        watcher = nil
        watcherFD = -1
    }
}

@MainActor
enum FileTreeIndexPool {
    private static var indexes: [String: FileTreeIndex] = [:]

    static func retainIndex(for rootPath: String) -> FileTreeIndex {
        if let existing = indexes[rootPath] {
            existing.retain()
            return existing
        }
        let created = FileTreeIndex(rootPath: rootPath)
        created.retain()
        indexes[rootPath] = created
        return created
    }

    static func releaseIndex(for rootPath: String) {
        guard let existing = indexes[rootPath] else { return }
        existing.release()
        if !existing.hasSubscribers {
            indexes.removeValue(forKey: rootPath)
        }
    }
}
