import Foundation
import WebKit

@available(iOS 14.5, *)
final class BrowserDownloadCoordinator: NSObject, WKDownloadDelegate {
  var destinationProvider: ((URLResponse, String) -> URL?)?
  var onFinished: ((URL?) -> Void)?
  var onFailure: ((Error, Data?) -> Void)?

  private var destinations: [ObjectIdentifier: URL] = [:]

  func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String,
    completionHandler: @escaping (URL?) -> Void
  ) {
    let destination = destinationProvider?(response, suggestedFilename)
    if let destination {
      destinations[ObjectIdentifier(download)] = destination
    }
    completionHandler(destination)
  }

  func downloadDidFinish(_ download: WKDownload) {
    let destination = destinations.removeValue(
      forKey: ObjectIdentifier(download)
    )
    onFinished?(destination)
  }

  func download(
    _ download: WKDownload,
    didFailWithError error: Error,
    resumeData: Data?
  ) {
    destinations.removeValue(forKey: ObjectIdentifier(download))
    onFailure?(error, resumeData)
  }
}
