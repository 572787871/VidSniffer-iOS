import Foundation

extension Notification.Name {
  static let downloadTasksDidChange = Notification.Name(
    "DownloadTasksDidChange"
  )
}

@MainActor
final class DownloadManager {
  static let shared = DownloadManager()

  private(set) var tasks: [DownloadTaskModel] = []
  private(set) var preferences = DownloadPreferences()

  private let repository: DownloadRepository
  private let service: BackgroundDownloadService
  private let destinationManager: DownloadDestinationManager
  private let notificationManager: DownloadNotificationManager
  private var lastPublishedAt: [UUID: Date] = [:]
  private var isReady = false

  init(
    repository: DownloadRepository = .shared,
    service: BackgroundDownloadService = .shared,
    destinationManager: DownloadDestinationManager = DownloadDestinationManager(),
    notificationManager: DownloadNotificationManager =
      DownloadNotificationManager()
  ) {
    self.repository = repository
    self.service = service
    self.destinationManager = destinationManager
    self.notificationManager = notificationManager
    configureService()
    Task { await restore() }
  }

  @discardableResult
  func enqueue(
    url: URL,
    filename: String,
    mimeType: String? = nil,
    expectedSize: Int64 = 0,
    destinationFolderID: UUID? = nil,
    requestHeaders: [String: String]? = nil
  ) async -> DownloadTaskModel? {
    await ensureReady()
    if let duplicate = tasks.first(where: {
      $0.originalURL == url
        && ![.failed, .cancelled].contains($0.state)
    }) {
      return duplicate
    }
    let task = DownloadTaskModel(
      url: url,
      filename: DownloadDestinationManager.sanitizedFilename(filename),
      mimeType: mimeType,
      expectedSize: max(0, expectedSize),
      destinationFolderID: destinationFolderID,
      requestHeaders: requestHeaders
    )
    tasks.insert(task, at: 0)
    await persist(task)
    publish()
    startWaitingTasks()
    return task
  }

  func pause(id: UUID) {
    guard let index = index(of: id),
          let identifier = tasks[index].sessionTaskIdentifier,
          tasks[index].state.canPause
    else {
      return
    }
    tasks[index].state = .paused
    tasks[index].speed = 0
    tasks[index].remainingTime = nil
    tasks[index].updatedAt = Date()
    publishAndPersist(tasks[index])
    service.pause(taskIdentifier: identifier) { [weak self] resumeData in
      Task { @MainActor in
        guard let self, let currentIndex = self.index(of: id) else { return }
        self.tasks[currentIndex].resumeData = resumeData
        self.tasks[currentIndex].sessionTaskIdentifier = nil
        self.tasks[currentIndex].updatedAt = Date()
        self.publishAndPersist(self.tasks[currentIndex])
        self.startWaitingTasks()
      }
    }
  }

  func resume(id: UUID) {
    guard let index = index(of: id), tasks[index].state.canResume else { return }
    tasks[index].state = .waiting
    tasks[index].errorMessage = nil
    tasks[index].updatedAt = Date()
    publishAndPersist(tasks[index])
    startWaitingTasks()
  }

  func cancel(id: UUID) {
    guard let index = index(of: id) else { return }
    if let identifier = tasks[index].sessionTaskIdentifier {
      service.cancel(taskIdentifier: identifier)
    }
    tasks[index].state = .cancelled
    tasks[index].speed = 0
    tasks[index].remainingTime = nil
    tasks[index].resumeData = nil
    tasks[index].sessionTaskIdentifier = nil
    tasks[index].updatedAt = Date()
    publishAndPersist(tasks[index])
    startWaitingTasks()
  }

  func retry(id: UUID) {
    guard let index = index(of: id),
          [.failed, .cancelled].contains(tasks[index].state)
    else {
      return
    }
    tasks[index].state = .waiting
    tasks[index].errorMessage = nil
    tasks[index].updatedAt = Date()
    publishAndPersist(tasks[index])
    startWaitingTasks()
  }

  func removeRecord(id: UUID) {
    guard let task = tasks.first(where: { $0.id == id }),
          task.state != .downloading
    else {
      return
    }
    tasks.removeAll { $0.id == id }
    Task { try? await repository.remove(id: id) }
    publish()
  }

  func pauseAll() {
    tasks.filter(\.state.canPause).forEach { pause(id: $0.id) }
  }

  func resumeAll() {
    tasks.filter(\.state.canResume).forEach { resume(id: $0.id) }
  }

  func updatePreferences(_ value: DownloadPreferences) {
    preferences = value
    Task { try? await repository.savePreferences(value) }
    startWaitingTasks()
  }

  func registerWebKitDownload(
    response: URLResponse,
    suggestedFilename: String
  ) throws -> (UUID, URL) {
    let url = response.url
      ?? URL(string: "about:blank")!
    let destination = try destinationManager.destination(
      filename: suggestedFilename,
      folderID: nil
    )
    let task = DownloadTaskModel(
      url: url,
      filename: destination.lastPathComponent,
      mimeType: response.mimeType,
      expectedSize: max(0, response.expectedContentLength),
      state: .downloading
    )
    tasks.insert(task, at: 0)
    publishAndPersist(task)
    return (task.id, destination)
  }

  func completeWebKitDownload(id: UUID, destination: URL?) {
    guard let index = index(of: id) else { return }
    tasks[index].state = .completed
    tasks[index].downloadedSize = max(
      tasks[index].downloadedSize,
      tasks[index].expectedSize
    )
    tasks[index].progress = 1
    tasks[index].remainingTime = 0
    tasks[index].localRelativePath = destination.flatMap {
      destinationManager.relativePath(for: $0)
    }
    tasks[index].updatedAt = Date()
    let completedTask = tasks[index]
    publishAndPersist(completedTask)
    LibraryManager.shared.registerCompletedDownload(completedTask)
    if preferences.notifiesOnCompletion {
      Task { await notificationManager.notifyCompletion(of: completedTask) }
    }
    startWaitingTasks()
  }

  func failWebKitDownload(id: UUID, error: Error, resumeData: Data?) {
    guard let index = index(of: id) else { return }
    tasks[index].state = .failed
    tasks[index].resumeData = resumeData
    tasks[index].errorMessage = userFacingMessage(for: error)
    tasks[index].updatedAt = Date()
    publishAndPersist(tasks[index])
    startWaitingTasks()
  }

  private func configureService() {
    service.onProgress = { [weak self] id, written, expected, speed in
      Task { @MainActor in
        self?.handleProgress(
          id: id,
          written: written,
          expected: expected,
          speed: speed
        )
      }
    }
    service.onFinished = { [weak self] id, location in
      Task { @MainActor in self?.handleFinished(id: id, location: location) }
    }
    service.onFailure = { [weak self] id, error, resumeData in
      Task { @MainActor in
        self?.handleFailure(id: id, error: error, resumeData: resumeData)
      }
    }
  }

  private func restore() async {
    tasks = (try? await repository.tasks()) ?? []
    preferences = (try? await repository.preferences())
      ?? DownloadPreferences()
    let active = await withCheckedContinuation { continuation in
      service.restoreTasks { continuation.resume(returning: $0) }
    }
    let activeByID = Dictionary(
      uniqueKeysWithValues: active.map { ($0.0, ($0.1, $0.2)) }
    )
    for index in tasks.indices {
      if let restored = activeByID[tasks[index].id] {
        tasks[index].sessionTaskIdentifier = restored.0
        tasks[index].state = restored.1 == .suspended
          ? .paused
          : .downloading
      } else if tasks[index].state == .downloading {
        tasks[index].state = tasks[index].resumeData == nil
          ? .waiting
          : .paused
        tasks[index].sessionTaskIdentifier = nil
      }
    }
    isReady = true
    publish()
    startWaitingTasks()
  }

  private func ensureReady() async {
    while !isReady {
      await Task.yield()
    }
  }

  private func startWaitingTasks() {
    guard isReady else { return }
    let activeCount = tasks.filter { $0.state == .downloading }.count
    let available = max(
      0,
      preferences.maximumConcurrentDownloads - activeCount
    )
    guard available > 0 else { return }
    let waitingIDs = tasks
      .filter { $0.state == .waiting }
      .sorted { $0.createdAt < $1.createdAt }
      .prefix(available)
      .map(\.id)
    for id in waitingIDs {
      start(id: id)
    }
  }

  private func start(id: UUID) {
    guard let index = index(of: id), tasks[index].state == .waiting else {
      return
    }
    var request = URLRequest(url: tasks[index].url)
    request.allowsCellularAccess = !preferences.wifiOnly
    request.timeoutInterval = 60
    tasks[index].requestHeaders?.forEach {
      request.setValue($0.value, forHTTPHeaderField: $0.key)
    }
    let identifier = service.start(
      id: id,
      request: request,
      resumeData: tasks[index].resumeData
    )
    tasks[index].state = .downloading
    tasks[index].sessionTaskIdentifier = identifier
    tasks[index].updatedAt = Date()
    publishAndPersist(tasks[index])
  }

  private func handleProgress(
    id: UUID,
    written: Int64,
    expected: Int64,
    speed: Double
  ) {
    guard let index = index(of: id) else { return }
    tasks[index].state = .downloading
    tasks[index].downloadedSize = written
    if expected > 0 {
      tasks[index].expectedSize = expected
      tasks[index].progress = min(1, Double(written) / Double(expected))
    }
    tasks[index].speed = speed
    let remainingBytes = max(0, tasks[index].expectedSize - written)
    tasks[index].remainingTime = speed > 0 && tasks[index].expectedSize > 0
      ? Double(remainingBytes) / speed
      : nil
    tasks[index].updatedAt = Date()
    let now = Date()
    if now.timeIntervalSince(lastPublishedAt[id] ?? .distantPast) >= 0.2 {
      lastPublishedAt[id] = now
      publishAndPersist(tasks[index])
    }
  }

  private func handleFinished(id: UUID, location: URL) {
    guard let index = index(of: id) else { return }
    do {
      let destination = try destinationManager.destination(
        filename: tasks[index].filename,
        folderID: tasks[index].destinationFolderID
      )
      try FileManager.default.moveItem(at: location, to: destination)
      tasks[index].state = .completed
      tasks[index].downloadedSize = max(
        tasks[index].downloadedSize,
        tasks[index].expectedSize
      )
      tasks[index].progress = 1
      tasks[index].speed = 0
      tasks[index].remainingTime = 0
      tasks[index].resumeData = nil
      tasks[index].sessionTaskIdentifier = nil
      tasks[index].localRelativePath =
        destinationManager.relativePath(for: destination)
      tasks[index].updatedAt = Date()
      let completedTask = tasks[index]
      publishAndPersist(completedTask)
      LibraryManager.shared.registerCompletedDownload(completedTask)
      if preferences.notifiesOnCompletion {
        Task { await notificationManager.notifyCompletion(of: completedTask) }
      }
    } catch {
      handleFailure(id: id, error: error, resumeData: nil)
    }
    startWaitingTasks()
  }

  private func handleFailure(id: UUID, error: Error, resumeData: Data?) {
    guard let index = index(of: id),
          tasks[index].state != .cancelled,
          tasks[index].state != .paused
    else {
      return
    }
    tasks[index].state = .failed
    tasks[index].speed = 0
    tasks[index].remainingTime = nil
    tasks[index].resumeData = resumeData
    tasks[index].sessionTaskIdentifier = nil
    tasks[index].errorMessage = userFacingMessage(for: error)
    tasks[index].updatedAt = Date()
    publishAndPersist(tasks[index])
    startWaitingTasks()
  }

  private func userFacingMessage(for error: Error) -> String {
    switch (error as NSError).code {
    case NSURLErrorNotConnectedToInternet:
      return "网络连接已断开，连接恢复后可以重试。"
    case NSURLErrorTimedOut:
      return "服务器响应超时，请稍后重试。"
    case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
      return "暂时无法连接下载服务器。"
    case NSURLErrorCancelled:
      return "下载已取消。"
    default:
      return "下载未能完成，可以保留进度后重试。"
    }
  }

  private func index(of id: UUID) -> Int? {
    tasks.firstIndex { $0.id == id }
  }

  private func persist(_ task: DownloadTaskModel) async {
    try? await repository.upsert(task)
  }

  private func publishAndPersist(_ task: DownloadTaskModel) {
    Task { try? await repository.upsert(task) }
    publish()
  }

  private func publish() {
    NotificationCenter.default.post(name: .downloadTasksDidChange, object: self)
  }
}
