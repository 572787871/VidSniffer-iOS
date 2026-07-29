import Foundation

actor LibraryRepository {
  private struct Envelope: Codable {
    var schemaVersion = 1
    var folders: [LibraryFolder] = []
    var files: [LibraryFile] = []
  }

  static let shared = LibraryRepository()

  private let fileManager: FileManager
  private let fileURL: URL
  private var cachedEnvelope: Envelope?

  init(
    fileManager: FileManager = .default,
    fileURL: URL? = nil
  ) {
    self.fileManager = fileManager
    let support = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    self.fileURL = fileURL
      ?? support.appendingPathComponent("library/library.json")
  }

  func snapshot() throws -> ([LibraryFolder], [LibraryFile]) {
    let value = try load()
    return (
      value.folders.sorted { $0.order < $1.order },
      value.files
    )
  }

  func upsert(file: LibraryFile) throws {
    var value = try load()
    if let index = value.files.firstIndex(where: { $0.id == file.id }) {
      value.files[index] = file
    } else if let taskID = file.downloadTaskID,
              let index = value.files.firstIndex(where: {
                $0.downloadTaskID == taskID
              }) {
      value.files[index] = file
    } else {
      value.files.append(file)
    }
    try save(value)
  }

  func removeFile(id: UUID) throws {
    var value = try load()
    value.files.removeAll { $0.id == id }
    try save(value)
  }

  func addFolder(name: String) throws -> LibraryFolder {
    var value = try load()
    let folder = LibraryFolder(
      name: Self.cleanFolderName(name),
      order: value.folders.count
    )
    value.folders.append(folder)
    try save(value)
    return folder
  }

  func update(folder: LibraryFolder) throws {
    var value = try load()
    guard let index = value.folders.firstIndex(where: {
      $0.id == folder.id
    }) else {
      return
    }
    value.folders[index] = folder
    try save(value)
  }

  func removeFolder(id: UUID) throws {
    var value = try load()
    value.folders.removeAll { $0.id == id }
    for index in value.files.indices where value.files[index].folderID == id {
      value.files[index].folderID = nil
    }
    try save(value)
  }

  static func cleanFolderName(_ name: String) -> String {
    let clean = DownloadDestinationManager.sanitizedFilename(name)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? "新建文件夹" : String(clean.prefix(80))
  }

  private func load() throws -> Envelope {
    if let cachedEnvelope { return cachedEnvelope }
    guard fileManager.fileExists(atPath: fileURL.path) else {
      let value = Envelope()
      cachedEnvelope = value
      return value
    }
    let value = try JSONDecoder().decode(
      Envelope.self,
      from: Data(contentsOf: fileURL)
    )
    cachedEnvelope = value
    return value
  }

  private func save(_ value: Envelope) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(value).write(
      to: fileURL,
      options: [.atomic, .completeFileProtection]
    )
    cachedEnvelope = value
  }
}
