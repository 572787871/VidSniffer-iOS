import Foundation

struct Bookmark: Codable, Identifiable, Equatable {
  let id: UUID
  var title: String
  var url: URL
  var folderID: UUID?
  var order: Int
  var createdAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    url: URL,
    folderID: UUID? = nil,
    order: Int = 0,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.folderID = folderID
    self.order = order
    self.createdAt = createdAt
  }
}

actor BookmarkManager {
  private let fileURL: URL
  private var bookmarks: [Bookmark] = []

  init(fileManager: FileManager = .default) {
    let directory = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    fileURL = directory.appendingPathComponent("bookmarks.json")
  }

  func load() throws -> [Bookmark] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      bookmarks = []
      return []
    }
    bookmarks = try JSONDecoder().decode(
      [Bookmark].self,
      from: Data(contentsOf: fileURL)
    )
    return bookmarks.sorted { $0.order < $1.order }
  }

  @discardableResult
  func add(title: String, url: URL, folderID: UUID? = nil) throws -> Bookmark {
    let bookmark = Bookmark(
      title: title,
      url: url,
      folderID: folderID,
      order: bookmarks.count
    )
    bookmarks.append(bookmark)
    try persist()
    return bookmark
  }

  func update(_ bookmark: Bookmark) throws {
    guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else {
      return
    }
    bookmarks[index] = bookmark
    try persist()
  }

  func remove(id: UUID) throws {
    bookmarks.removeAll { $0.id == id }
    normalizeOrder()
    try persist()
  }

  func move(fromOffsets: IndexSet, toOffset: Int) throws {
    var ordered = bookmarks.sorted { $0.order < $1.order }
    let moving = fromOffsets.sorted().map { ordered[$0] }
    for index in fromOffsets.sorted(by: >) {
      ordered.remove(at: index)
    }
    ordered.insert(contentsOf: moving, at: min(toOffset, ordered.count))
    bookmarks = ordered
    normalizeOrder()
    try persist()
  }

  func exportJSON() throws -> Data {
    try JSONEncoder().encode(bookmarks)
  }

  func importJSON(_ data: Data) throws {
    bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
    normalizeOrder()
    try persist()
  }

  private func normalizeOrder() {
    for index in bookmarks.indices {
      bookmarks[index].order = index
    }
  }

  private func persist() throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(bookmarks).write(to: fileURL, options: .atomic)
  }
}
