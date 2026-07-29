import Foundation

struct BrowserSessionState: Codable, Equatable {
  var selectedTabID: UUID?
  var tabs: [BrowserTabSnapshot]
  var savedAt: Date

  init(
    selectedTabID: UUID?,
    tabs: [BrowserTabSnapshot],
    savedAt: Date = Date()
  ) {
    self.selectedTabID = selectedTabID
    self.tabs = tabs.filter { !$0.isPrivate }
    self.savedAt = savedAt
  }
}

actor BrowserSessionManager {
  private let sessionFileURL: URL
  private let screenshotDirectoryURL: URL

  init(
    fileManager: FileManager = .default,
    supportDirectory: URL? = nil,
    cacheDirectory: URL? = nil
  ) {
    let supportDirectory = supportDirectory ?? fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let cacheDirectory = cacheDirectory ?? fileManager.urls(
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

  func restore() throws -> BrowserSessionState? {
    guard FileManager.default.fileExists(atPath: sessionFileURL.path) else {
      return nil
    }
    let data = try Data(contentsOf: sessionFileURL)
    if let state = try? JSONDecoder().decode(BrowserSessionState.self, from: data) {
      return BrowserSessionState(
        selectedTabID: state.selectedTabID,
        tabs: state.tabs
      )
    }

    // Migrate the phase-1 array format without discarding open tabs.
    let snapshots = try JSONDecoder()
      .decode([BrowserTabSnapshot].self, from: data)
      .filter { !$0.isPrivate }
    return BrowserSessionState(
      selectedTabID: snapshots.first?.id,
      tabs: snapshots
    )
  }

  func restoreNormalTabs() throws -> [BrowserTabSnapshot] {
    try restore()?.tabs ?? []
  }

  func save(_ state: BrowserSessionState) throws {
    try FileManager.default.createDirectory(
      at: sessionFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder()
      .encode(state)
      .write(
        to: sessionFileURL,
        options: [.atomic, .completeFileProtection]
      )
  }

  func saveNormalTabs(_ snapshots: [BrowserTabSnapshot]) throws {
    try save(
      BrowserSessionState(
        selectedTabID: snapshots.first?.id,
        tabs: snapshots
      )
    )
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

  func removeScreenshot(fileName: String) {
    try? FileManager.default.removeItem(
      at: screenshotDirectoryURL.appendingPathComponent(fileName)
    )
  }

  func pruneScreenshots(keeping fileNames: Set<String>) throws {
    guard FileManager.default.fileExists(
      atPath: screenshotDirectoryURL.path
    ) else {
      return
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: screenshotDirectoryURL,
      includingPropertiesForKeys: nil
    )
    for file in files where !fileNames.contains(file.lastPathComponent) {
      try? FileManager.default.removeItem(at: file)
    }
  }
}
