import UIKit
import WebKit

@MainActor
final class BrowserTabManager {
  nonisolated static let defaultMaximumActiveWebViews = 6

  private(set) var tabs: [BrowserTab] = []
  private(set) var recentlyClosed: [BrowserTabSnapshot] = []
  private(set) var selectedTabID: UUID?

  let maximumActiveWebViews: Int
  var onTabsChanged: (() -> Void)?
  var onSelectedTabChanged: ((BrowserTab) -> Void)?

  init(maximumActiveWebViews: Int = defaultMaximumActiveWebViews) {
    self.maximumActiveWebViews = max(1, maximumActiveWebViews)
  }

  var selectedTab: BrowserTab? {
    guard let selectedTabID else { return nil }
    return tabs.first { $0.id == selectedTabID }
  }

  @discardableResult
  func createTab(url: URL? = nil, isPrivate: Bool = false) -> BrowserTab {
    let tab = BrowserTab(url: url, isPrivate: isPrivate)
    tabs.append(tab)
    selectedTabID = tab.id
    materializeWebView(for: tab)
    notifyChanges(selected: tab)
    enforceActiveLimit(excluding: tab.id)
    return tab
  }

  @discardableResult
  func activateTab(id: UUID) -> BrowserTab? {
    guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
    if tab.webView == nil {
      materializeWebView(for: tab)
    }
    selectedTabID = id
    tab.lastVisitedDate = Date()
    notifyChanges(selected: tab)
    enforceActiveLimit(excluding: id)
    return tab
  }

  func closeTab(id: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    let tab = tabs.remove(at: index)
    if let webView = tab.webView {
      tab.captureState(from: webView)
      webView.stopLoading()
      webView.removeFromSuperview()
    }
    if !tab.isPrivate {
      recentlyClosed.insert(tab.makeSnapshot(), at: 0)
      recentlyClosed = Array(recentlyClosed.prefix(20))
    }

    if tabs.isEmpty || tabs.allSatisfy(\.isPrivate) {
      _ = createTab()
      return
    }

    if selectedTabID == id {
      let nextIndex = min(index, tabs.count - 1)
      selectedTabID = tabs[nextIndex].id
      _ = activateTab(id: tabs[nextIndex].id)
    } else {
      onTabsChanged?()
    }
  }

  func closeAllPrivateTabs() {
    let privateIDs = tabs.filter(\.isPrivate).map(\.id)
    for id in privateIDs {
      closeTab(id: id)
    }
  }

  @discardableResult
  func restoreMostRecentlyClosed() -> BrowserTab? {
    guard !recentlyClosed.isEmpty else { return nil }
    let snapshot = recentlyClosed.removeFirst()
    let tab = BrowserTab(snapshot: snapshot)
    tabs.append(tab)
    selectedTabID = tab.id
    materializeWebView(for: tab)
    notifyChanges(selected: tab)
    enforceActiveLimit(excluding: tab.id)
    return tab
  }

  func replaceNormalTabs(with snapshots: [BrowserTabSnapshot]) {
    for tab in tabs where !tab.isPrivate {
      tab.webView?.stopLoading()
      tab.webView?.removeFromSuperview()
    }
    tabs.removeAll { !$0.isPrivate }
    tabs.insert(
      contentsOf: snapshots
        .filter { !$0.isPrivate }
        .map(BrowserTab.init(snapshot:)),
      at: 0
    )
    if let first = tabs.first(where: { !$0.isPrivate }) {
      selectedTabID = first.id
      materializeWebView(for: first)
      notifyChanges(selected: first)
    } else {
      _ = createTab()
    }
  }

  private func materializeWebView(for tab: BrowserTab) {
    guard tab.webView == nil else { return }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = tab.isPrivate
      ? WKWebsiteDataStore.nonPersistent()
      : WKWebsiteDataStore.default()
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.allowsBackForwardNavigationGestures = true
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    tab.webView = webView

    if let url = tab.url {
      webView.load(URLRequest(url: url))
    }
  }

  private func enforceActiveLimit(excluding selectedID: UUID) {
    let active = tabs.filter { $0.webView != nil }
    guard active.count > maximumActiveWebViews else { return }
    guard let candidate = active
      .filter({ $0.id != selectedID })
      .min(by: { $0.lastVisitedDate < $1.lastVisitedDate }),
      let webView = candidate.webView
    else {
      return
    }

    candidate.captureState(from: webView)
    let snapshotConfiguration = WKSnapshotConfiguration()
    webView.takeSnapshot(with: snapshotConfiguration) { [weak candidate] image, _ in
      candidate?.screenshot = image
    }
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.removeFromSuperview()
    candidate.webView = nil
  }

  private func notifyChanges(selected tab: BrowserTab) {
    onTabsChanged?()
    onSelectedTabChanged?(tab)
  }
}
