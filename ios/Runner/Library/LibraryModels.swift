import Foundation

struct LibraryFolder: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var order: Int
  let createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    order: Int = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.order = order
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

struct LibraryFile: Codable, Identifiable, Equatable {
  let id: UUID
  var downloadTaskID: UUID?
  var folderID: UUID?
  var displayName: String
  var relativePath: String
  var mimeType: String?
  var size: Int64
  let createdAt: Date
  var updatedAt: Date
  var isFavorite: Bool
  var duration: TimeInterval?
  var playbackPosition: TimeInterval

  init(
    id: UUID = UUID(),
    downloadTaskID: UUID? = nil,
    folderID: UUID? = nil,
    displayName: String,
    relativePath: String,
    mimeType: String? = nil,
    size: Int64 = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    isFavorite: Bool = false,
    duration: TimeInterval? = nil,
    playbackPosition: TimeInterval = 0
  ) {
    self.id = id
    self.downloadTaskID = downloadTaskID
    self.folderID = folderID
    self.displayName = displayName
    self.relativePath = relativePath
    self.mimeType = mimeType
    self.size = size
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isFavorite = isFavorite
    self.duration = duration
    self.playbackPosition = playbackPosition
  }
}

enum LibrarySort: String, Codable, CaseIterable {
  case name
  case date
  case size

  var title: String {
    switch self {
    case .name: return "名称"
    case .date: return "日期"
    case .size: return "大小"
    }
  }
}

enum LibraryLayout: String, Codable {
  case list
  case grid
}
