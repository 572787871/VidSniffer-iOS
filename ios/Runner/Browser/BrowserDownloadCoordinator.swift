import Foundation
import WebKit

@available(iOS 14.5, *)
@MainActor
final class BrowserDownloadCoordinator: NSObject, WKDownloadDelegate {
  var onFinished: ((URL?) -> Void)?
  var onFailure: ((Error, Data?) -> Void)?

  private var destinations: [ObjectIdentifier: URL] = [:]
  private var taskIDs: [ObjectIdentifier: UUID] = [:]

  func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String,
    completionHandler: @escaping (URL?) -> Void
  ) {
    do {
      let registered = try DownloadManager.shared.registerWebKitDownload(
        response: response,
        suggestedFilename: suggestedFilename
      )
      let key = ObjectIdentifier(download)
      taskIDs[key] = registered.0
      destinations[key] = registered.1
      completionHandler(registered.1)
    } catch {
      onFailure?(error, nil)
      completionHandler(nil)
    }
  }

  func downloadDidFinish(_ download: WKDownload) {
    let key = ObjectIdentifier(download)
    let destination = destinations.removeValue(forKey: key)
    if let id = taskIDs.removeValue(forKey: key) {
      DownloadManager.shared.completeWebKitDownload(
        id: id,
        destination: destination
      )
    }
    onFinished?(destination)
  }

  func download(
    _ download: WKDownload,
    didFailWithError error: Error,
    resumeData: Data?
  ) {
    let key = ObjectIdentifier(download)
    destinations.removeValue(forKey: key)
    if let id = taskIDs.removeValue(forKey: key) {
      DownloadManager.shared.failWebKitDownload(
        id: id,
        error: error,
        resumeData: resumeData
      )
    }
    onFailure?(error, resumeData)
  }
}
