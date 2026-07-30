import AVFoundation
import Foundation

final class BackgroundDownloadService: NSObject {
  static let shared = BackgroundDownloadService()

  var onProgress: ((UUID, Int64, Int64, Double) -> Void)?
  var onFinished: ((UUID, URL) -> Void)?
  var onFailure: ((UUID, Error, Data?) -> Void)?
  var backgroundEventsCompletionHandler: (() -> Void)?

  private var measurements: [UUID: (date: Date, bytes: Int64)] = [:]

  private lazy var session: URLSession = {
    let identifier = "\(Bundle.main.bundleIdentifier ?? "VidSniffer").downloads"
    let configuration = URLSessionConfiguration.background(
      withIdentifier: identifier
    )
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.waitsForConnectivity = true
    configuration.httpMaximumConnectionsPerHost = 4
    return URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: nil
    )
  }()

  func start(
    id: UUID,
    request: URLRequest,
    resumeData: Data? = nil
  ) -> Int {
    let task = resumeData.map(session.downloadTask(withResumeData:))
      ?? session.downloadTask(with: request)
    task.taskDescription = id.uuidString
    measurements[id] = (Date(), 0)
    task.resume()
    return task.taskIdentifier
  }

  func pause(taskIdentifier: Int, completion: @escaping (Data?) -> Void) {
    session.getAllTasks { tasks in
      guard let task = tasks.first(where: {
        $0.taskIdentifier == taskIdentifier
      }) as? URLSessionDownloadTask else {
        completion(nil)
        return
      }
      task.cancel(byProducingResumeData: completion)
    }
  }

  func cancel(taskIdentifier: Int) {
    session.getAllTasks { tasks in
      tasks.first { $0.taskIdentifier == taskIdentifier }?.cancel()
    }
  }

  func restoreTasks(
    completion: @escaping ([(UUID, Int, URLSessionTask.State)]) -> Void
  ) {
    session.getAllTasks { tasks in
      completion(tasks.compactMap { task in
        guard let rawID = task.taskDescription,
              let id = UUID(uuidString: rawID)
        else {
          return nil
        }
        return (id, task.taskIdentifier, task.state)
      })
    }
  }

  private func id(for task: URLSessionTask) -> UUID? {
    task.taskDescription.flatMap(UUID.init(uuidString:))
  }
}

final class HLSAssetDownloadService: NSObject {
  static let shared = HLSAssetDownloadService()

  var onProgress: ((UUID, Double) -> Void)?
  var onFinished: ((UUID, URL) -> Void)?
  var onFailure: ((UUID, Error) -> Void)?
  var backgroundEventsCompletionHandler: (() -> Void)?

  private lazy var session: AVAssetDownloadURLSession = {
    let identifier =
      "\(Bundle.main.bundleIdentifier ?? "VidSniffer").hls-downloads"
    let configuration = URLSessionConfiguration.background(
      withIdentifier: identifier
    )
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.waitsForConnectivity = true
    let queue = OperationQueue()
    queue.name = "com.vidsniffer.hls-downloads"
    queue.maxConcurrentOperationCount = 1
    return AVAssetDownloadURLSession(
      configuration: configuration,
      assetDownloadDelegate: self,
      delegateQueue: queue
    )
  }()

  func start(id: UUID, url: URL, title: String) -> Int? {
    let asset = AVURLAsset(url: url)
    guard let task = session.makeAssetDownloadTask(
      asset: asset,
      assetTitle: title,
      assetArtworkData: nil,
      options: [
        AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 0,
      ]
    ) else {
      return nil
    }
    task.taskDescription = id.uuidString
    task.resume()
    return task.taskIdentifier
  }

  func pause(taskIdentifier: Int) {
    session.getAllTasks { tasks in
      tasks.first { $0.taskIdentifier == taskIdentifier }?.suspend()
    }
  }

  func resume(taskIdentifier: Int) {
    session.getAllTasks { tasks in
      tasks.first { $0.taskIdentifier == taskIdentifier }?.resume()
    }
  }

  func cancel(taskIdentifier: Int) {
    session.getAllTasks { tasks in
      tasks.first { $0.taskIdentifier == taskIdentifier }?.cancel()
    }
  }

  func restoreTasks(
    completion: @escaping ([(UUID, Int, URLSessionTask.State)]) -> Void
  ) {
    session.getAllTasks { tasks in
      completion(tasks.compactMap { task in
        guard let rawID = task.taskDescription,
              let id = UUID(uuidString: rawID)
        else {
          return nil
        }
        return (id, task.taskIdentifier, task.state)
      })
    }
  }

  private func id(for task: URLSessionTask) -> UUID? {
    task.taskDescription.flatMap(UUID.init(uuidString:))
  }
}

extension HLSAssetDownloadService: AVAssetDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    assetDownloadTask: AVAssetDownloadTask,
    didLoad timeRange: CMTimeRange,
    totalTimeRangesLoaded loadedTimeRanges: [NSValue],
    timeRangeExpectedToLoad: CMTimeRange
  ) {
    guard let id = id(for: assetDownloadTask) else { return }
    let expected = timeRangeExpectedToLoad.duration.seconds
    guard expected.isFinite, expected > 0 else { return }
    let loaded = loadedTimeRanges.reduce(0.0) {
      $0 + $1.timeRangeValue.duration.seconds
    }
    onProgress?(id, min(1, max(0, loaded / expected)))
  }

  func urlSession(
    _ session: URLSession,
    assetDownloadTask: AVAssetDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let id = id(for: assetDownloadTask) else { return }
    onFinished?(id, location)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error, let id = id(for: task) else { return }
    onFailure?(id, error)
  }

  func urlSessionDidFinishEvents(
    forBackgroundURLSession session: URLSession
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.backgroundEventsCompletionHandler?()
      self?.backgroundEventsCompletionHandler = nil
    }
  }
}

extension BackgroundDownloadService:
  URLSessionDownloadDelegate,
  URLSessionTaskDelegate
{
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let id = id(for: downloadTask) else { return }
    let now = Date()
    let previous = measurements[id] ?? (now, totalBytesWritten - bytesWritten)
    let elapsed = now.timeIntervalSince(previous.date)
    guard elapsed >= 0.2 else { return }
    let speed = Double(totalBytesWritten - previous.bytes) / elapsed
    measurements[id] = (now, totalBytesWritten)
    onProgress?(
      id,
      totalBytesWritten,
      totalBytesExpectedToWrite,
      max(0, speed)
    )
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let id = id(for: downloadTask) else { return }
    measurements.removeValue(forKey: id)
    let stagingDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CompletedDownloads", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: stagingDirectory,
        withIntermediateDirectories: true
      )
      let stagedURL = stagingDirectory.appendingPathComponent(id.uuidString)
      try? FileManager.default.removeItem(at: stagedURL)
      try FileManager.default.moveItem(at: location, to: stagedURL)
      onFinished?(id, stagedURL)
    } catch {
      onFailure?(id, error, nil)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error, let id = id(for: task) else { return }
    measurements.removeValue(forKey: id)
    let data = (error as NSError).userInfo[
      NSURLSessionDownloadTaskResumeData
    ] as? Data
    onFailure?(id, error, data)
  }

  func urlSessionDidFinishEvents(
    forBackgroundURLSession session: URLSession
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.backgroundEventsCompletionHandler?()
      self?.backgroundEventsCompletionHandler = nil
    }
  }
}
