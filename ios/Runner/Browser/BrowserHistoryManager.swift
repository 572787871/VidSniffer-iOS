import Foundation

struct BrowserHistoryEntry: Codable, Identifiable, Equatable {
  let id: UUID
  var title: String
  var url: URL
  var visitedAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    url: URL,
    visitedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.visitedAt = visitedAt
  }
}

actor BrowserHistoryManager {
  private let fileURL: URL
  private var entries: [BrowserHistoryEntry] = []

  init(fileManager: FileManager = .default) {
    let directory = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    fileURL = directory.appendingPathComponent("browser-history.json")
  }

  func load() throws -> [BrowserHistoryEntry] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      entries = []
      return []
    }
    entries = try JSONDecoder().decode(
      [BrowserHistoryEntry].self,
      from: Data(contentsOf: fileURL)
    )
    return entries
  }

  func add(title: String, url: URL, isPrivate: Bool) throws {
    guard !isPrivate else { return }
    entries.insert(BrowserHistoryEntry(title: title, url: url), at: 0)
    try persist()
  }

  func search(_ query: String) -> [BrowserHistoryEntry] {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return entries }
    return entries.filter {
      $0.title.localizedCaseInsensitiveContains(value)
        || $0.url.absoluteString.localizedCaseInsensitiveContains(value)
    }
  }

  func remove(id: UUID) throws {
    entries.removeAll { $0.id == id }
    try persist()
  }

  func clear(from startDate: Date? = nil) throws {
    if let startDate {
      entries.removeAll { $0.visitedAt >= startDate }
    } else {
      entries.removeAll()
    }
    try persist()
  }

  private func persist() throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(entries)
    try data.write(to: fileURL, options: .atomic)
  }
}
