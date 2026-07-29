import XCTest
import WebKit
@testable import Runner

final class BrowserCoreTests: XCTestCase {
  func testURLResolverRecognizesExplicitAndImplicitURLs() {
    XCTAssertEqual(
      BrowserURLResolver.resolve("https://example.com/a")?.absoluteString,
      "https://example.com/a"
    )
    XCTAssertEqual(
      BrowserURLResolver.resolve("example.com/video")?.absoluteString,
      "https://example.com/video"
    )
  }

  func testURLResolverBuildsSelectedSearchEngineURL() {
    let result = BrowserURLResolver.resolve(
      "swift uikit browser",
      searchEngine: .duckDuckGo
    )
    XCTAssertEqual(result?.host, "duckduckgo.com")
    XCTAssertEqual(
      URLComponents(url: result!, resolvingAgainstBaseURL: false)?
        .queryItems?.first?.value,
      "swift uikit browser"
    )
  }

  func testTabSnapshotPreservesRestorableState() async {
    await MainActor.run {
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
  }

  func testManagerLimitsActiveWebViews() async {
    await MainActor.run {
      let manager = BrowserTabManager(maximumActiveWebViews: 3)
      for _ in 0..<7 {
        _ = manager.createTab()
      }

      XCTAssertEqual(manager.tabs.count, 7)
      XCTAssertLessThanOrEqual(
        manager.tabs.filter { $0.webView != nil }.count,
        3
      )
      XCTAssertNotNil(manager.selectedTab?.webView)
    }
  }

  func testClosingLastNormalTabCreatesBlankNormalTab() async {
    await MainActor.run {
      let manager = BrowserTabManager()
      let normal = manager.createTab()
      _ = manager.createTab(isPrivate: true)

      manager.closeTab(id: normal.id)

      XCTAssertTrue(manager.tabs.contains { !$0.isPrivate })
    }
  }

  func testPrivateTabUsesNonPersistentDataStore() async {
    await MainActor.run {
      let manager = BrowserTabManager()
      let privateTab = manager.createTab(isPrivate: true)

      XCTAssertNotNil(privateTab.webView)
      XCTAssertFalse(
        privateTab.webView?.configuration.websiteDataStore
          === WKWebsiteDataStore.default()
      )
    }
  }

  func testTabReorderingAndClosingOthers() async {
    await MainActor.run {
      let manager = BrowserTabManager()
      let first = manager.createTab()
      let second = manager.createTab()
      let third = manager.createTab()

      manager.moveTab(id: third.id, before: first.id)
      XCTAssertEqual(manager.tabs.first?.id, third.id)

      manager.closeOtherTabs(keeping: second.id)
      XCTAssertNotNil(manager.tab(id: second.id))
      XCTAssertEqual(manager.tabs.filter { !$0.isPrivate }.count, 1)
    }
  }
}
