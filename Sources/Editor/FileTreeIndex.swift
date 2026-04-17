import Foundation

@MainActor
final class FileTreeIndex {
  struct Node: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let hasUnloadedChildren: Bool

    var id: String { path }
  }

  private let rootPath: String
  private let fileManager: FileManager
  private var childCache: [String: [Node]] = [:]
  private var watcher: DispatchSourceFileSystemObject?
  private var watcherFD: Int32 = -1
  private var pendingInvalidation = false
  private var invalidationWorkItem: DispatchWorkItem?
  private var isActive = true
  private var subscribers = 0
  var hasSubscribers: Bool { subscribers > 0 }

  var onTreeDidInvalidate: (() -> Void)?

  init(rootPath: String, fileManager: FileManager = .default) {
    self.rootPath = rootPath
    self.fileManager = fileManager
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

  func rootChildren() -> [Node] {
    children(for: rootPath)
  }

  func children(for path: String) -> [Node] {
    if let cached = childCache[path] {
      return cached
    }

    let loaded = loadChildrenFromDisk(path: path)
    childCache[path] = loaded
    return loaded
  }

  private func loadChildrenFromDisk(path: String) -> [Node] {
    let rootURL = URL(fileURLWithPath: path, isDirectory: true)
    guard
      let values = try? fileManager.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return values.compactMap { url in
      guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
        return nil
      }
      return Node(
        path: url.path,
        name: url.lastPathComponent,
        isDirectory: isDirectory == true,
        hasUnloadedChildren: isDirectory == true
      )
    }
    .sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory {
        return lhs.isDirectory && !rhs.isDirectory
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  private func invalidateAll() {
    childCache.removeAll()
    onTreeDidInvalidate?()
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
    watcherFD = open(rootPath, O_EVTONLY)
    guard watcherFD >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: watcherFD,
      eventMask: [.write, .rename, .delete],
      queue: DispatchQueue.global(qos: .utility)
    )
    source.setEventHandler { [weak self] in
      self?.queueInvalidation()
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
    if existing.hasSubscribers {
      indexes[rootPath] = existing
    } else {
      indexes.removeValue(forKey: rootPath)
    }
  }
}
