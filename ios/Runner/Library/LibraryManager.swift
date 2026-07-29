import Foundation

extension Notification.Name {
  static let libraryDidChange = Notification.Name("LibraryDidChange")
}

@MainActor
final class LibraryManager {
  static let shared = LibraryManager()

  private(set) var folders: [LibraryFolder] = []
  private(set) var files: [LibraryFile] = []

  private let repository: LibraryRepository
  private let fileManager: FileManager
  private let documentsDirectory: URL
  private let coversDirectory: URL

  init(
    repository: LibraryRepository = .shared,
    fileManager: FileManager = .default,
    documentsDirectory: URL? = nil,
    cacheDirectory: URL? = nil
  ) {
    self.repository = repository
    self.fileManager = fileManager
    self.documentsDirectory = documentsDirectory
      ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let cache = cacheDirectory
      ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    coversDirectory = cache.appendingPathComponent(
      "LibraryCovers",
      isDirectory: true
    )
    Task { await reloadAndRepair() }
  }

  func registerCompletedDownload(_ task: DownloadTaskModel) {
    guard let relativePath = task.localRelativePath else { return }
    let url = documentsDirectory.appendingPathComponent(relativePath)
    let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    let size = fileSize.map(Int64.init) ?? task.downloadedSize
    let file = LibraryFile(
      downloadTaskID: task.id,
      folderID: task.destinationFolderID,
      displayName: task.filename,
      relativePath: relativePath,
      mimeType: task.mimeType,
      size: size
    )
    Task {
      try? await repository.upsert(file: file)
      await reloadAndRepair()
    }
  }

  func addFolder(name: String) {
    Task {
      _ = try? await repository.addFolder(name: name)
      await reloadAndRepair()
    }
  }

  func renameFolder(_ folder: LibraryFolder, name: String) {
    var value = folder
    value.name = LibraryRepository.cleanFolderName(name)
    value.updatedAt = Date()
    Task {
      try? await repository.update(folder: value)
      await reloadAndRepair()
    }
  }

  func deleteFolder(_ folder: LibraryFolder) {
    Task {
      try? await repository.removeFolder(id: folder.id)
      await reloadAndRepair()
    }
  }

  func updateFile(_ file: LibraryFile) {
    Task {
      try? await repository.upsert(file: file)
      await reloadAndRepair()
    }
  }

  func moveFile(_ file: LibraryFile, to folderID: UUID?) {
    var value = file
    value.folderID = folderID
    value.updatedAt = Date()
    updateFile(value)
  }

  func renameFile(_ file: LibraryFile, name: String) throws {
    let cleanName = DownloadDestinationManager.sanitizedFilename(name)
    let oldURL = url(for: file)
    let newURL = oldURL.deletingLastPathComponent()
      .appendingPathComponent(cleanName)
    try fileManager.moveItem(at: oldURL, to: newURL)
    var value = file
    value.displayName = cleanName
    value.relativePath = relativePath(for: newURL) ?? file.relativePath
    value.updatedAt = Date()
    updateFile(value)
  }

  func deleteFile(_ file: LibraryFile) throws {
    let url = url(for: file)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    if let coverURL = coverURL(for: file),
       fileManager.fileExists(atPath: coverURL.path) {
      try? fileManager.removeItem(at: coverURL)
    }
    files.removeAll { $0.id == file.id }
    NotificationCenter.default.post(name: .libraryDidChange, object: self)
    Task { try? await repository.removeFile(id: file.id) }
  }

  func url(for file: LibraryFile) -> URL {
    documentsDirectory.appendingPathComponent(file.relativePath)
  }

  func copyFile(_ file: LibraryFile) throws {
    let source = url(for: file)
    let destinationManager = DownloadDestinationManager(
      fileManager: fileManager,
      documentsDirectory: documentsDirectory
    )
    let destination = try destinationManager.destination(
      filename: file.displayName,
      folderID: file.folderID
    )
    try fileManager.copyItem(at: source, to: destination)
    let copy = LibraryFile(
      folderID: file.folderID,
      displayName: destination.lastPathComponent,
      relativePath: relativePath(for: destination) ?? destination.lastPathComponent,
      mimeType: file.mimeType,
      size: file.size,
      isFavorite: false,
      duration: file.duration
    )
    updateFile(copy)
  }

  func setCustomCover(data: Data, for file: LibraryFile) throws {
    try fileManager.createDirectory(
      at: coversDirectory,
      withIntermediateDirectories: true
    )
    let coverURL = coversDirectory
      .appendingPathComponent("\(file.id.uuidString).jpg")
    try data.write(to: coverURL, options: .atomic)
    var value = file
    value.customCoverRelativePath = coverURL.lastPathComponent
    value.updatedAt = Date()
    updateFile(value)
  }

  func coverURL(for file: LibraryFile) -> URL? {
    guard let relativePath = file.customCoverRelativePath else { return nil }
    return coversDirectory.appendingPathComponent(relativePath)
  }

  func files(
    in folderID: UUID?,
    query: String = "",
    sort: LibrarySort = .date
  ) -> [LibraryFile] {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let scoped = files.filter {
      (folderID == nil || $0.folderID == folderID)
        && (cleanQuery.isEmpty
          || $0.displayName.localizedCaseInsensitiveContains(cleanQuery))
    }
    switch sort {
    case .name:
      return scoped.sorted {
        $0.displayName.localizedStandardCompare($1.displayName)
          == .orderedAscending
      }
    case .date:
      return scoped.sorted { $0.updatedAt > $1.updatedAt }
    case .size:
      return scoped.sorted { $0.size > $1.size }
    }
  }

  private func reloadAndRepair() async {
    guard let snapshot = try? await repository.snapshot() else { return }
    folders = snapshot.0
    files = snapshot.1.filter {
      fileManager.fileExists(atPath: url(for: $0).path)
    }
    let missingIDs = Set(snapshot.1.map(\.id))
      .subtracting(files.map(\.id))
    for id in missingIDs {
      try? await repository.removeFile(id: id)
    }
    NotificationCenter.default.post(name: .libraryDidChange, object: self)
  }

  private func relativePath(for url: URL) -> String? {
    let root = documentsDirectory.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(root + "/") else { return nil }
    return String(path.dropFirst(root.count + 1))
  }
}
