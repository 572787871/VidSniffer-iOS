import XCTest
import WebKit
@testable import Runner

final class BrowserCoreTests: XCTestCase {
  func testVideoResourceStoreAcceptsAndDeduplicatesDirectMediaURL() async throws {
    let url = try XCTUnwrap(
      URL(string: "https://cdn.example.com/video/sample.mp4")
    )
    await MainActor.run {
      let store = VideoResourceStore()
      let payload: [String: Any] = [
        "url": url.absoluteString,
        "type": "video/mp4",
        "title": "Sample",
        "height": 1080,
        "duration": 65,
      ]
      store.receive(
        payload: payload,
        fallbackPageURL: URL(string: "https://example.com/watch"),
        fallbackTitle: "Fallback"
      )
      store.receive(
        payload: payload,
        fallbackPageURL: URL(string: "https://example.com/watch"),
        fallbackTitle: "Fallback"
      )

      XCTAssertEqual(store.resources.count, 1)
      XCTAssertEqual(store.resources.first?.url, url)
      XCTAssertEqual(store.resources.first?.format, "MP4")
      XCTAssertEqual(store.resources.first?.quality, "1080p")
      XCTAssertEqual(store.resources.first?.duration, 65)
    }
  }

  func testHLSManifestParserSortDataCanExposeEveryVariant() throws {
    let base = try XCTUnwrap(
      URL(string: "https://cdn.example.com/master.m3u8")
    )
    let manifest = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1920x1080
    high/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720
    medium/index.m3u8
    """

    let variants = HLSManifestParser.variants(in: manifest, baseURL: base)

    XCTAssertEqual(variants.count, 2)
    XCTAssertEqual(variants[0].height, 1080)
    XCTAssertEqual(
      variants[1].url.absoluteString,
      "https://cdn.example.com/medium/index.m3u8"
    )
  }

  func testHLSManifestDurationUsesAllSegments() {
    let manifest = """
    #EXTM3U
    #EXTINF:4.5,
    one.ts
    #EXTINF:5.25,
    two.ts
    """
    XCTAssertEqual(HLSManifestParser.duration(in: manifest), 9.75)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "BrowserCoreTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

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
      let manager = BrowserTabManager(
        maximumActiveWebViews: 3,
        appliesContentRules: false
      )
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
      let manager = BrowserTabManager(appliesContentRules: false)
      let normal = manager.createTab()
      _ = manager.createTab(isPrivate: true)

      manager.closeTab(id: normal.id)

      XCTAssertTrue(manager.tabs.contains { !$0.isPrivate })
    }
  }

  func testPrivateTabUsesNonPersistentDataStore() async {
    await MainActor.run {
      let manager = BrowserTabManager(appliesContentRules: false)
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
      let manager = BrowserTabManager(appliesContentRules: false)
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

  func testBookmarkCRUDUsesUnifiedRepository() async throws {
    let directory = try makeTemporaryDirectory()
    let repository = BrowserDataRepository(
      fileURL: directory.appendingPathComponent("browser-data.json")
    )
    let manager = BookmarkManager(repository: repository)
    let url = URL(string: "https://example.com/bookmark")!

    let bookmark = try await manager.add(title: "Example", url: url)
    let initialBookmarks = try await manager.load()
    XCTAssertEqual(initialBookmarks.count, 1)

    var updated = bookmark
    updated.title = "Updated"
    try await manager.update(updated)
    let updatedBookmarks = try await manager.load()
    XCTAssertEqual(updatedBookmarks.first?.title, "Updated")

    try await manager.remove(id: bookmark.id)
    let finalBookmarks = try await manager.load()
    XCTAssertTrue(finalBookmarks.isEmpty)
  }

  func testPrivateHistoryIsNotPersistedAndHistoryCanBeCleared() async throws {
    let directory = try makeTemporaryDirectory()
    let repository = BrowserDataRepository(
      fileURL: directory.appendingPathComponent("browser-data.json")
    )
    let manager = BrowserHistoryManager(repository: repository)
    let url = URL(string: "https://example.com/history")!

    try await manager.add(title: "Private", url: url, isPrivate: true)
    let privateHistory = try await manager.load()
    XCTAssertTrue(privateHistory.isEmpty)

    try await manager.add(title: "Normal", url: url, isPrivate: false)
    let normalHistory = try await manager.load()
    XCTAssertEqual(normalHistory.count, 1)
    try await manager.clear()
    let clearedHistory = try await manager.load()
    XCTAssertTrue(clearedHistory.isEmpty)
  }

  func testSessionRestoreExcludesPrivateTabsAndKeepsSelection() async throws {
    let directory = try makeTemporaryDirectory()
    let manager = BrowserSessionManager(
      supportDirectory: directory.appendingPathComponent("Support"),
      cacheDirectory: directory.appendingPathComponent("Caches")
    )
    let normal = await MainActor.run {
      BrowserTab(title: "Normal", url: URL(string: "https://example.com"))
    }
    let privateTab = await MainActor.run {
      BrowserTab(
        title: "Private",
        url: URL(string: "https://example.com/private"),
        isPrivate: true
      )
    }
    let state = await MainActor.run {
      BrowserSessionState(
        selectedTabID: normal.id,
        tabs: [normal.makeSnapshot(), privateTab.makeSnapshot()]
      )
    }
    let normalID = await MainActor.run { normal.id }

    try await manager.save(state)
    let restored = try await manager.restore()

    XCTAssertEqual(restored?.selectedTabID, normalID)
    XCTAssertEqual(restored?.tabs.count, 1)
    XCTAssertFalse(restored?.tabs.first?.isPrivate ?? true)
  }

  func testDownloadRepositoryPersistsTaskAndPreferences() async throws {
    let directory = try makeTemporaryDirectory()
    let repository = DownloadRepository(
      fileURL: directory.appendingPathComponent("tasks.json")
    )
    let url = try XCTUnwrap(URL(string: "https://example.com/video.mp4"))
    var task = DownloadTaskModel(
      url: url,
      filename: "video.mp4",
      expectedSize: 1_000
    )
    try await repository.upsert(task)
    task.state = .paused
    task.downloadedSize = 400
    task.resumeData = Data([1, 2, 3])
    try await repository.upsert(task)
    var preferences = DownloadPreferences()
    preferences.maximumConcurrentDownloads = 2
    preferences.wifiOnly = true
    try await repository.savePreferences(preferences)

    let restoredTasks = try await repository.tasks()
    let restoredPreferences = try await repository.preferences()

    XCTAssertEqual(restoredTasks, [task])
    XCTAssertEqual(restoredPreferences, preferences)
  }

  func testDownloadFilenameSanitizationPreventsPathTraversal() {
    XCTAssertEqual(
      DownloadDestinationManager.sanitizedFilename("../../bad:name.mp4"),
      ".._.._bad_name.mp4"
    )
    XCTAssertEqual(
      DownloadDestinationManager.sanitizedFilename("   "),
      "下载文件"
    )
  }

  func testDownloadTaskStateCapabilities() {
    XCTAssertTrue(DownloadTaskState.downloading.canPause)
    XCTAssertTrue(DownloadTaskState.paused.canResume)
    XCTAssertTrue(DownloadTaskState.failed.canResume)
    XCTAssertFalse(DownloadTaskState.completed.canPause)
    XCTAssertFalse(DownloadTaskState.cancelled.canResume)
  }

  func testHLSResourcesUseSystemOfflineAssetDownload() throws {
    let url = try XCTUnwrap(
      URL(string: "https://cdn.example.com/master.m3u8")
    )
    let resource = DetectedMediaResource(
      url: url,
      title: "Example",
      mimeType: "application/vnd.apple.mpegurl",
      format: "HLS"
    )
    let task = DownloadTaskModel(
      url: url,
      filename: resource.suggestedFilename,
      mimeType: resource.mimeType
    )

    XCTAssertEqual(resource.suggestedFilename, "Example.movpkg")
    XCTAssertTrue(task.usesHLSAssetDownload)
  }

  func testLibraryRepositoryUsesUUIDsAndPreservesFilesWhenFolderRemoved()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let repository = LibraryRepository(
      fileURL: directory.appendingPathComponent("library.json")
    )
    let folder = try await repository.addFolder(name: "旅行记录")
    let file = LibraryFile(
      folderID: folder.id,
      displayName: "video.mp4",
      relativePath: "Downloads/video.mp4",
      size: 1_024
    )
    try await repository.upsert(file: file)
    try await repository.removeFolder(id: folder.id)

    let snapshot = try await repository.snapshot()

    XCTAssertTrue(snapshot.0.isEmpty)
    XCTAssertEqual(snapshot.1.count, 1)
    XCTAssertEqual(snapshot.1.first?.id, file.id)
    XCTAssertNil(snapshot.1.first?.folderID)
  }

  func testLibraryFolderNameSanitization() {
    XCTAssertEqual(
      LibraryRepository.cleanFolderName("../旅行/记录"),
      ".._旅行_记录"
    )
    XCTAssertEqual(LibraryRepository.cleanFolderName(""), "下载文件")
  }

  func testLibraryFilesDoNotUseFilenameAsIdentity() {
    let first = LibraryFile(
      displayName: "同名视频.mp4",
      relativePath: "Downloads/同名视频.mp4"
    )
    let second = LibraryFile(
      displayName: "同名视频.mp4",
      relativePath: "Downloads/同名视频 2.mp4"
    )

    XCTAssertNotEqual(first.id, second.id)
  }

}
