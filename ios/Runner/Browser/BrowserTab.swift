import UIKit
import WebKit

struct BrowserTabSnapshot: Codable, Equatable {
  let id: UUID
  var title: String
  var url: URL?
  var lastVisitedDate: Date
  var scrollX: Double
  var scrollY: Double
  var isPrivate: Bool
  var backList: [URL]
  var forwardList: [URL]
  var screenshotFileName: String?
}

@MainActor
final class BrowserTab: Identifiable {
  let id: UUID
  var title: String
  var url: URL?
  var favicon: UIImage?
  var webView: WKWebView?
  var canGoBack = false
  var canGoForward = false
  var estimatedProgress = 0.0
  var isLoading = false
  var lastVisitedDate: Date
  var scrollPosition: CGPoint
  let isPrivate: Bool
  var screenshot: UIImage?
  var backList: [URL]
  var forwardList: [URL]
  let videoResources = VideoResourceStore()
  var videoDetectionBridge: VideoDetectionBridge?

  init(
    id: UUID = UUID(),
    title: String = "新标签页",
    url: URL? = nil,
    isPrivate: Bool = false,
    lastVisitedDate: Date = Date(),
    scrollPosition: CGPoint = .zero,
    backList: [URL] = [],
    forwardList: [URL] = []
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.isPrivate = isPrivate
    self.lastVisitedDate = lastVisitedDate
    self.scrollPosition = scrollPosition
    self.backList = backList
    self.forwardList = forwardList
  }

  var isSleeping: Bool {
    webView == nil
  }

  func captureState(from webView: WKWebView) {
    title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? title
    url = webView.url ?? url
    canGoBack = webView.canGoBack
    canGoForward = webView.canGoForward
    estimatedProgress = webView.estimatedProgress
    isLoading = webView.isLoading
    scrollPosition = webView.scrollView.contentOffset
    lastVisitedDate = Date()
    backList = webView.backForwardList.backList.compactMap(\.url)
    forwardList = webView.backForwardList.forwardList.compactMap(\.url)
  }

  func makeSnapshot(screenshotFileName: String? = nil) -> BrowserTabSnapshot {
    BrowserTabSnapshot(
      id: id,
      title: title,
      url: url,
      lastVisitedDate: lastVisitedDate,
      scrollX: scrollPosition.x,
      scrollY: scrollPosition.y,
      isPrivate: isPrivate,
      backList: backList,
      forwardList: forwardList,
      screenshotFileName: screenshotFileName
    )
  }

  convenience init(snapshot: BrowserTabSnapshot) {
    self.init(
      id: snapshot.id,
      title: snapshot.title,
      url: snapshot.url,
      isPrivate: snapshot.isPrivate,
      lastVisitedDate: snapshot.lastVisitedDate,
      scrollPosition: CGPoint(x: snapshot.scrollX, y: snapshot.scrollY),
      backList: snapshot.backList,
      forwardList: snapshot.forwardList
    )
  }
}

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
