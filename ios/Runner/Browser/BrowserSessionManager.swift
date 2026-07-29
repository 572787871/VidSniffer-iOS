import Foundation

actor BrowserSessionManager {
  private let sessionFileURL: URL
  private let screenshotDirectoryURL: URL

  init(fileManager: FileManager = .default) {
    let supportDirectory = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let cacheDirectory = fileManager.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first!
    sessionFileURL = supportDirectory.appendingPathComponent(
      "browser-session.json"
    )
    screenshotDirectoryURL = cacheDirectory.appendingPathComponent(
      "BrowserTabScreenshots",
      isDirectory: true
    )
  }

  func restoreNormalTabs() throws -> [BrowserTabSnapshot] {
    guard FileManager.default.fileExists(atPath: sessionFileURL.path) else {
      return []
    }
    return try JSONDecoder()
      .decode([BrowserTabSnapshot].self, from: Data(contentsOf: sessionFileURL))
      .filter { !$0.isPrivate }
  }

  func saveNormalTabs(_ snapshots: [BrowserTabSnapshot]) throws {
    let normalSnapshots = snapshots.filter { !$0.isPrivate }
    try FileManager.default.createDirectory(
      at: sessionFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder()
      .encode(normalSnapshots)
      .write(to: sessionFileURL, options: .atomic)
  }

  func saveScreenshot(_ data: Data, tabID: UUID) throws -> String {
    try FileManager.default.createDirectory(
      at: screenshotDirectoryURL,
      withIntermediateDirectories: true
    )
    let fileName = "\(tabID.uuidString).jpg"
    try data.write(
      to: screenshotDirectoryURL.appendingPathComponent(fileName),
      options: .atomic
    )
    return fileName
  }

  func screenshotData(fileName: String) throws -> Data {
    try Data(
      contentsOf: screenshotDirectoryURL.appendingPathComponent(fileName)
    )
  }

  func removePrivateArtifacts() throws {
    guard FileManager.default.fileExists(
      atPath: screenshotDirectoryURL.path
    ) else {
      return
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: screenshotDirectoryURL,
      includingPropertiesForKeys: nil
    )
    for file in files where file.lastPathComponent.hasPrefix("private-") {
      try? FileManager.default.removeItem(at: file)
    }
  }
}
