import Foundation

enum DownloadTaskState: String, Codable, CaseIterable {
  case waiting
  case downloading
  case paused
  case completed
  case failed
  case cancelled
  case merging
  case verifying

  var canPause: Bool {
    self == .waiting || self == .downloading
  }

  var canResume: Bool {
    self == .paused || self == .failed
  }

  var displayName: String {
    switch self {
    case .waiting: return "等待下载"
    case .downloading: return "下载中"
    case .paused: return "已暂停"
    case .completed: return "已完成"
    case .failed: return "下载失败"
    case .cancelled: return "已取消"
    case .merging: return "正在合并"
    case .verifying: return "正在验证"
    }
  }
}

struct DownloadTaskModel: Codable, Identifiable, Equatable {
  let id: UUID
  var url: URL
  var originalURL: URL
  var filename: String
  var mimeType: String?
  var expectedSize: Int64
  var downloadedSize: Int64
  var progress: Double
  var speed: Double
  var remainingTime: TimeInterval?
  let createdAt: Date
  var updatedAt: Date
  var destinationFolderID: UUID?
  var resumeData: Data?
  var errorMessage: String?
  var sourceDomain: String
  var state: DownloadTaskState
  var localRelativePath: String?
  var sessionTaskIdentifier: Int?

  init(
    id: UUID = UUID(),
    url: URL,
    originalURL: URL? = nil,
    filename: String,
    mimeType: String? = nil,
    expectedSize: Int64 = 0,
    downloadedSize: Int64 = 0,
    progress: Double = 0,
    speed: Double = 0,
    remainingTime: TimeInterval? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    destinationFolderID: UUID? = nil,
    resumeData: Data? = nil,
    errorMessage: String? = nil,
    sourceDomain: String? = nil,
    state: DownloadTaskState = .waiting,
    localRelativePath: String? = nil,
    sessionTaskIdentifier: Int? = nil
  ) {
    self.id = id
    self.url = url
    self.originalURL = originalURL ?? url
    self.filename = filename
    self.mimeType = mimeType
    self.expectedSize = expectedSize
    self.downloadedSize = downloadedSize
    self.progress = progress
    self.speed = speed
    self.remainingTime = remainingTime
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.destinationFolderID = destinationFolderID
    self.resumeData = resumeData
    self.errorMessage = errorMessage
    self.sourceDomain = sourceDomain ?? url.host ?? "未知来源"
    self.state = state
    self.localRelativePath = localRelativePath
    self.sessionTaskIdentifier = sessionTaskIdentifier
  }
}

struct DownloadPreferences: Codable, Equatable {
  var maximumConcurrentDownloads = 3
  var wifiOnly = false
  var asksForDestination = true
  var notifiesOnCompletion = true
}
