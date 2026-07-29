import XCTest
import WebKit
@testable import Runner

@MainActor
final class BrowserCoreTests: XCTestCase {
  func testTabSnapshotPreservesRestorableState() {
    let id = UUID()
    let url = URL(string: "https://example.com/page")!
    let tab = BrowserTab(
      id: id,
      title: "Example",
      url: url,
      lastVisitedDate: Date(timeIntervalSince1970: 123),
      scrollPosition: CGPoint(x: 10, y: 420),
      backList: [URL(string: "https://example.com")!],
      forwardList: [URL(string: "https://example.com/next")!]
    )

    let restored = BrowserTab(snapshot: tab.makeSnapshot())

    XCTAssertEqual(restored.id, id)
    XCTAssertEqual(restored.title, "Example")
    XCTAssertEqual(restored.url, url)
    XCTAssertEqual(restored.scrollPosition, CGPoint(x: 10, y: 420))
    XCTAssertEqual(restored.backList.count, 1)
    XCTAssertEqual(restored.forwardList.count, 1)
    XCTAssertFalse(restored.isPrivate)
  }

  func testManagerLimitsActiveWebViews() {
    let manager = BrowserTabManager(maximumActiveWebViews: 3)
    for index in 0..<7 {
      _ = manager.createTab(
        url: URL(string: "https://example.com/\(index)")
      )
    }

    XCTAssertEqual(manager.tabs.count, 7)
    XCTAssertLessThanOrEqual(
      manager.tabs.filter { $0.webView != nil }.count,
      3
    )
    XCTAssertNotNil(manager.selectedTab?.webView)
  }

  func testClosingLastNormalTabCreatesBlankNormalTab() {
    let manager = BrowserTabManager()
    let normal = manager.createTab(url: URL(string: "https://example.com"))
    _ = manager.createTab(isPrivate: true)

    manager.closeTab(id: normal.id)

    XCTAssertTrue(manager.tabs.contains { !$0.isPrivate })
  }

  func testPrivateTabUsesNonPersistentDataStore() {
    let manager = BrowserTabManager()
    let privateTab = manager.createTab(isPrivate: true)

    XCTAssertNotNil(privateTab.webView)
    XCTAssertFalse(
      privateTab.webView?.configuration.websiteDataStore
        === WKWebsiteDataStore.default()
    )
  }
}
