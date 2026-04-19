import Foundation

/// Raw directory entries scanned off the main thread; mapped to `FileTreeIndex.Node` on the main actor.
private struct FileTreeScannedEntry {
    let path: String
    let name: String
    let isDirectory: Bool
}

private struct FileTreeSearchCatalogEntry {
    let path: String
    let name: String
    let normalizedName: String
    let isDirectory: Bool
    let relativePath: String
    let relativeParentPath: String
    let hasHiddenPathSegment: Bool
}

private enum FileTreeDirectoryScanner {
    /// `nil` means the directory could not be read (IO/permission); do not cache as an empty listing.
    nonisolated static func scan(
        path: String,
        fileManager: FileManager,
        includeHiddenEntries: Bool = false
    ) -> [FileTreeScannedEntry]? {
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHiddenEntries {
            options.insert(.skipsHiddenFiles)
        }
        guard
            let values = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: options
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

private enum FileTreeSearchScanner {
    private static let gitIgnoreChunkSize = 4096

    nonisolated static func buildCatalog(
        rootPath: String,
        fileManager: FileManager
    ) -> [FileTreeSearchCatalogEntry] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        guard
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: enumerationOptions
            )
        else {
            return []
        }

        var entries: [FileTreeSearchCatalogEntry] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }

            let name = url.lastPathComponent
            guard !name.isEmpty else { continue }

            guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                continue
            }

            let path = url.standardizedFileURL.path
            let relativeEntryPath = relativePath(fromRoot: rootPath, absolutePath: path)
            let parentPath = (path as NSString).deletingLastPathComponent
            let relativeParentPath = relativePath(fromRoot: rootPath, absolutePath: parentPath)

            entries.append(
                FileTreeSearchCatalogEntry(
                    path: path,
                    name: name,
                    normalizedName: normalizeForSearch(name),
                    isDirectory: isDirectory == true,
                    relativePath: relativeEntryPath,
                    relativeParentPath: relativeParentPath,
                    hasHiddenPathSegment: hasHiddenPathSegment(in: relativeEntryPath)
                )
            )
        }
        return entries
    }

    nonisolated static func normalizeForSearch(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    nonisolated static func relativePath(fromRoot root: String, absolutePath: String) -> String {
        guard absolutePath == root || absolutePath.hasPrefix(root + "/") else {
            return absolutePath
        }
        var rel = String(absolutePath.dropFirst(root.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }

    private nonisolated static func hasHiddenPathSegment(in relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        for component in relativePath.split(separator: "/", omittingEmptySubsequences: true) {
            if component.hasPrefix("."), component != ".", component != ".." {
                return true
            }
        }
        return false
    }

    nonisolated static func gitIgnoredRelativePaths(
        rootPath: String,
        relativePaths: [String]
    ) async -> Set<String> {
        guard !relativePaths.isEmpty else { return [] }

        let uniqueRelativePaths = Array(Set(relativePaths))
        if uniqueRelativePaths.count <= gitIgnoreChunkSize {
            return await gitIgnoredRelativePathsChunk(rootPath: rootPath, relativePaths: uniqueRelativePaths)
        }

        var ignored: Set<String> = []
        ignored.reserveCapacity(uniqueRelativePaths.count / 4)

        var start = 0
        while start < uniqueRelativePaths.count {
            if Task.isCancelled { break }
            let end = min(start + gitIgnoreChunkSize, uniqueRelativePaths.count)
            let chunk = Array(uniqueRelativePaths[start ..< end])
            await ignored.formUnion(
                gitIgnoredRelativePathsChunk(rootPath: rootPath, relativePaths: chunk)
            )
            start = end
        }
        return ignored
    }

    private nonisolated static func gitIgnoredRelativePathsChunk(
        rootPath: String,
        relativePaths: [String]
    ) async -> Set<String> {
        guard !relativePaths.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", rootPath, "check-ignore", "--stdin", "-z"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let payload = relativePaths.joined(separator: "\u{0}") + "\u{0}"
        let stdinWrite = stdinPipe.fileHandleForWriting
        let stdoutRead = stdoutPipe.fileHandleForReading

        let data = await withTaskCancellationHandler {
            await Task.detached {
                if let data = payload.data(using: .utf8) {
                    try? stdinWrite.write(contentsOf: data)
                }
                try? stdinWrite.close()
                return (try? stdoutRead.readToEnd()) ?? Data()
            }.value
        } onCancel: {
            process.terminate()
            try? stdinWrite.close()
            try? stdoutRead.close()
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return []
        }
        return parseNullDelimitedUTF8(data)
    }

    private nonisolated static func parseNullDelimitedUTF8(_ data: Data) -> Set<String> {
        guard !data.isEmpty else { return [] }
        var values: Set<String> = []
        var current: [UInt8] = []
        current.reserveCapacity(64)

        for byte in data {
            if byte == 0 {
                if !current.isEmpty, let value = String(bytes: current, encoding: .utf8) {
                    values.insert(value)
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }

        if !current.isEmpty, let value = String(bytes: current, encoding: .utf8) {
            values.insert(value)
        }
        return values
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

    struct SearchResult: Identifiable, Hashable {
        let path: String
        let name: String
        let isDirectory: Bool
        /// Parent path relative to the index root. Empty string means root-level entry.
        let relativeParentPath: String

        var id: String {
            path
        }
    }

    struct SearchOptions: Hashable {
        /// Default: filename search includes dotfiles; gitignored paths still filtered unless opted in.
        var includeHiddenEntries: Bool = true
        var includeGitIgnoredEntries: Bool = false
    }

    private struct SearchCatalog {
        let generation: UInt
        let entries: [FileTreeSearchCatalogEntry]
    }

    private struct SearchComputation {
        let matches: [FileTreeSearchCatalogEntry]
        let newlyIgnoredRelativePaths: Set<String>
        let newlyVisibleRelativePaths: Set<String>
    }

    private let rootPath: String
    private let fileManager: FileManager
    private var childCache: [String: [Node]] = [:]
    /// Must match how `childCache[path]` was produced (`FileTreeDirectoryScanner` hidden flag).
    private var childCacheListingIncludesHidden: [String: Bool] = [:]
    private var contentGeneration: UInt = 0
    private var loadingPaths: Set<String> = []
    private var childrenDidChangeHandler: (() -> Void)?
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherFD: Int32 = -1
    private var pendingInvalidation = false
    private var invalidationWorkItem: DispatchWorkItem?
    private var isActive = true
    private var subscribers = 0
    private var searchCatalog: SearchCatalog?
    private var searchCatalogBuildTask: Task<SearchCatalog, Never>?
    private var searchCatalogBuildGeneration: UInt?
    private var searchCatalogBuildPriority: TaskPriority?
    private var gitIgnoreCacheByRelativePath: [String: Bool] = [:]
    /// Cap prefetch breadth so we do not recursively fan out into massive trees.
    private let prefetchChildDirectoryLimit = 6
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
    func scheduleLoadChildren(
        for path: String,
        priority: TaskPriority = .utility,
        shouldPrefetchChildren: Bool = true,
        includeHiddenEntries: Bool = false
    ) {
        if let cached = childCache[path] {
            let modeMatches = childCacheListingIncludesHidden[path] == includeHiddenEntries
            if modeMatches {
                if shouldPrefetchChildren {
                    prefetchLikelyChildDirectories(from: cached, includeHiddenEntries: includeHiddenEntries)
                }
                return
            }
            childCache.removeValue(forKey: path)
            childCacheListingIncludesHidden.removeValue(forKey: path)
        }
        if loadingPaths.contains(path) { return }
        loadingPaths.insert(path)
        let generation = contentGeneration
        let capturedPath = path
        let fm = fileManager
        Task.detached(priority: priority) {
            let scanned = FileTreeDirectoryScanner.scan(
                path: capturedPath,
                fileManager: fm,
                includeHiddenEntries: includeHiddenEntries
            )
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
                childCacheListingIncludesHidden[capturedPath] = includeHiddenEntries
                loadingPaths.remove(capturedPath)
                if shouldPrefetchChildren {
                    prefetchLikelyChildDirectories(from: nodes, includeHiddenEntries: includeHiddenEntries)
                }
                childrenDidChangeHandler?()
            }
        }
    }

    private func prefetchLikelyChildDirectories(from nodes: [Node], includeHiddenEntries: Bool) {
        var scheduledCount = 0
        for node in nodes where node.isDirectory {
            if scheduledCount >= prefetchChildDirectoryLimit { break }
            if childCache[node.path] != nil || loadingPaths.contains(node.path) { continue }
            scheduledCount += 1
            scheduleLoadChildren(
                for: node.path,
                priority: .utility,
                shouldPrefetchChildren: false,
                includeHiddenEntries: includeHiddenEntries
            )
        }
    }

    /// Warms the full filename search catalog so first keystrokes can respond quickly.
    func prewarmSearchCatalog(priority: TaskPriority = .utility) {
        _ = ensureSearchCatalogTask(priority: priority)
    }

    /// Bounded filename search across the current root. Returns at most `limit` hits.
    func search(
        matching query: String,
        limit: Int = 200,
        options: SearchOptions = SearchOptions()
    ) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard limit > 0 else { return [] }

        let boundedLimit = min(limit, 500)
        let generation = contentGeneration
        let catalog: SearchCatalog
        if let cachedCatalog = searchCatalog, cachedCatalog.generation == generation {
            catalog = cachedCatalog
        } else {
            let task = ensureSearchCatalogTask(priority: .userInitiated)
            let loadedCatalog = await task.value
            guard generation == contentGeneration else { return [] }
            searchCatalog = loadedCatalog
            if searchCatalogBuildGeneration == generation {
                searchCatalogBuildTask = nil
                searchCatalogBuildGeneration = nil
                searchCatalogBuildPriority = nil
            }
            catalog = loadedCatalog
        }

        let normalizedNeedle = FileTreeSearchScanner.normalizeForSearch(trimmed)
        let ignoreCacheSnapshot = gitIgnoreCacheByRelativePath
        let capturedRootPath = rootPath
        let computationTask = Task(priority: .userInitiated) {
            await Self.computeSearchMatches(
                from: catalog.entries,
                needle: normalizedNeedle,
                limit: boundedLimit,
                options: options,
                rootPath: capturedRootPath,
                gitIgnoreCache: ignoreCacheSnapshot
            )
        }
        let computation = await computationTask.value

        guard generation == contentGeneration else { return [] }
        for relativePath in computation.newlyIgnoredRelativePaths {
            gitIgnoreCacheByRelativePath[relativePath] = true
        }
        for relativePath in computation.newlyVisibleRelativePaths {
            gitIgnoreCacheByRelativePath[relativePath] = false
        }

        return computation.matches.map { entry in
            SearchResult(
                path: entry.path,
                name: entry.name,
                isDirectory: entry.isDirectory,
                relativeParentPath: entry.relativeParentPath
            )
        }
    }

    private func ensureSearchCatalogTask(priority: TaskPriority) -> Task<SearchCatalog, Never> {
        let generation = contentGeneration
        if let cachedCatalog = searchCatalog, cachedCatalog.generation == generation {
            return Task { cachedCatalog }
        }
        if let existingTask = searchCatalogBuildTask,
           searchCatalogBuildGeneration == generation
        {
            let currentPriority = searchCatalogBuildPriority ?? .utility
            if priorityRank(currentPriority) >= priorityRank(priority) {
                return existingTask
            }
            existingTask.cancel()
            searchCatalogBuildTask = nil
            searchCatalogBuildGeneration = nil
            searchCatalogBuildPriority = nil
        }

        let capturedRootPath = rootPath
        let fm = fileManager
        let task = Task.detached(priority: priority) {
            SearchCatalog(
                generation: generation,
                entries: FileTreeSearchScanner.buildCatalog(rootPath: capturedRootPath, fileManager: fm)
            )
        }
        searchCatalogBuildTask = task
        searchCatalogBuildGeneration = generation
        searchCatalogBuildPriority = priority
        return task
    }

    private nonisolated static func computeSearchMatches(
        from entries: [FileTreeSearchCatalogEntry],
        needle: String,
        limit: Int,
        options: SearchOptions,
        rootPath: String,
        gitIgnoreCache: [String: Bool]
    ) async -> SearchComputation {
        guard !entries.isEmpty else {
            return SearchComputation(
                matches: [], newlyIgnoredRelativePaths: [], newlyVisibleRelativePaths: []
            )
        }

        var matches: [FileTreeSearchCatalogEntry] = []
        matches.reserveCapacity(min(max(limit * 4, 256), 4096))
        for entry in entries {
            if Task.isCancelled { break }
            if !options.includeHiddenEntries, entry.hasHiddenPathSegment { continue }
            if !entry.normalizedName.contains(needle) { continue }
            matches.append(entry)
        }

        guard !matches.isEmpty else {
            return SearchComputation(
                matches: [], newlyIgnoredRelativePaths: [], newlyVisibleRelativePaths: []
            )
        }

        var cachedIgnored: Set<String> = []
        var unknownRelativePaths: Set<String> = []
        cachedIgnored.reserveCapacity(matches.count / 3)
        unknownRelativePaths.reserveCapacity(matches.count / 3)

        for entry in matches {
            if let cached = gitIgnoreCache[entry.relativePath] {
                if cached { cachedIgnored.insert(entry.relativePath) }
            } else {
                unknownRelativePaths.insert(entry.relativePath)
            }
        }

        let ignoredFromGit: Set<String> =
            unknownRelativePaths.isEmpty
                ? []
                : await FileTreeSearchScanner.gitIgnoredRelativePaths(
                    rootPath: rootPath,
                    relativePaths: Array(unknownRelativePaths)
                )

        let ignoredPaths = cachedIgnored.union(ignoredFromGit)
        let filtered: [FileTreeSearchCatalogEntry] =
            options.includeGitIgnoredEntries
                ? matches
                : matches.filter { !ignoredPaths.contains($0.relativePath) }

        var newlyVisible: Set<String> = []
        if !unknownRelativePaths.isEmpty {
            newlyVisible.reserveCapacity(unknownRelativePaths.count)
            for relativePath in unknownRelativePaths where !ignoredFromGit.contains(relativePath) {
                newlyVisible.insert(relativePath)
            }
        }

        guard !filtered.isEmpty else {
            return SearchComputation(
                matches: [],
                newlyIgnoredRelativePaths: ignoredFromGit,
                newlyVisibleRelativePaths: newlyVisible
            )
        }

        var ranked = filtered
        ranked.sort { lhs, rhs in
            let lhsPrefix = lhs.normalizedName.hasPrefix(needle)
            let rhsPrefix = rhs.normalizedName.hasPrefix(needle)
            if lhsPrefix != rhsPrefix { return lhsPrefix && !rhsPrefix }

            let lhsDemoted =
                (options.includeHiddenEntries && lhs.hasHiddenPathSegment)
                    || (options.includeGitIgnoredEntries && ignoredPaths.contains(lhs.relativePath))
            let rhsDemoted =
                (options.includeHiddenEntries && rhs.hasHiddenPathSegment)
                    || (options.includeGitIgnoredEntries && ignoredPaths.contains(rhs.relativePath))
            if lhsDemoted != rhsDemoted { return !lhsDemoted && rhsDemoted }

            let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.path < rhs.path
        }

        return SearchComputation(
            matches: Array(ranked.prefix(limit)),
            newlyIgnoredRelativePaths: ignoredFromGit,
            newlyVisibleRelativePaths: newlyVisible
        )
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high, .userInitiated:
            5
        case .medium:
            4
        case .utility:
            3
        case .low:
            2
        case .background:
            1
        default:
            3
        }
    }

    private func invalidateAll() {
        contentGeneration += 1
        childCache.removeAll()
        childCacheListingIncludesHidden.removeAll()
        loadingPaths.removeAll()
        searchCatalogBuildTask?.cancel()
        searchCatalogBuildTask = nil
        searchCatalogBuildGeneration = nil
        searchCatalogBuildPriority = nil
        searchCatalog = nil
        gitIgnoreCacheByRelativePath.removeAll()
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
