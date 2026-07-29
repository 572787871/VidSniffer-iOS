import Foundation

struct DownloadDestinationManager {
  private let fileManager: FileManager
  private let documentsDirectory: URL

  init(
    fileManager: FileManager = .default,
    documentsDirectory: URL? = nil
  ) {
    self.fileManager = fileManager
    self.documentsDirectory = documentsDirectory
      ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
  }

  func destination(
    filename: String,
    folderID: UUID?
  ) throws -> URL {
    let folder = folderID.map {
      documentsDirectory
        .appendingPathComponent("Downloads", isDirectory: true)
        .appendingPathComponent($0.uuidString, isDirectory: true)
    } ?? documentsDirectory.appendingPathComponent(
      "Downloads",
      isDirectory: true
    )
    try fileManager.createDirectory(
      at: folder,
      withIntermediateDirectories: true
    )
    return availableURL(
      in: folder,
      filename: Self.sanitizedFilename(filename)
    )
  }

  func relativePath(for url: URL) -> String? {
    let root = documentsDirectory.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(root + "/") else { return nil }
    return String(path.dropFirst(root.count + 1))
  }

  static func sanitizedFilename(_ filename: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
      .union(.controlCharacters)
    let components = filename.components(separatedBy: invalid)
    let clean = components.joined(separator: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let value = clean.isEmpty ? "下载文件" : clean
    return String(value.prefix(180))
  }

  private func availableURL(in folder: URL, filename: String) -> URL {
    let candidate = folder.appendingPathComponent(filename)
    guard fileManager.fileExists(atPath: candidate.path) else {
      return candidate
    }
    let extensionName = candidate.pathExtension
    let stem = candidate.deletingPathExtension().lastPathComponent
    for index in 2...9_999 {
      let suffix = "\(stem) \(index)"
      let value = extensionName.isEmpty
        ? suffix
        : "\(suffix).\(extensionName)"
      let url = folder.appendingPathComponent(value)
      if !fileManager.fileExists(atPath: url.path) {
        return url
      }
    }
    return folder.appendingPathComponent("\(UUID().uuidString)-\(filename)")
  }
}
