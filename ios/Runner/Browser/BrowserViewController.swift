@preconcurrency import AVFoundation
import UIKit
import WebKit

enum BrowserSearchEngine: String, CaseIterable {
  case google
  case bing
  case duckDuckGo
  case baidu

  func searchURL(for query: String) -> URL? {
    let base: String
    let parameter: String
    switch self {
    case .google:
      base = "https://www.google.com/search"
      parameter = "q"
    case .bing:
      base = "https://www.bing.com/search"
      parameter = "q"
    case .duckDuckGo:
      base = "https://duckduckgo.com/"
      parameter = "q"
    case .baidu:
      base = "https://www.baidu.com/s"
      parameter = "wd"
    }
    var components = URLComponents(string: base)
    components?.queryItems = [URLQueryItem(name: parameter, value: query)]
    return components?.url
  }
}

enum BrowserURLResolver {
  static func resolve(
    _ rawValue: String,
    searchEngine: BrowserSearchEngine = .google
  ) -> URL? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if let explicitURL = URL(string: value),
       let scheme = explicitURL.scheme?.lowercased(),
       ["http", "https"].contains(scheme) {
      return explicitURL
    }

    if looksLikeHost(value),
       let url = URL(string: "https://\(value)") {
      return url
    }

    return searchEngine.searchURL(for: value)
  }

  private static func looksLikeHost(_ value: String) -> Bool {
    guard !value.contains(where: \.isWhitespace) else { return false }
    if value == "localhost" || value.hasPrefix("localhost:") {
      return true
    }
    guard let components = URLComponents(string: "https://\(value)"),
          let host = components.host
    else {
      return false
    }
    return host.contains(".") || host.contains(":")
  }
}

@MainActor
final class BrowserViewController: UIViewController {
  private let tabManager: BrowserTabManager
  private let addressBar = AddressBarView()
  private let toolbar = BrowserToolbar()
  private let contentView = UIView()
  private let homeView = BrowserHomeView()
  private let errorView = BrowserErrorView()
  private let tabCountButton = UIButton(type: .system)
  private let privateBadge = UILabel()
  private let moreButton = UIButton(type: .system)
  private let findBar = BrowserFindBar()
  private let refreshControl = UIRefreshControl()
  private let downloadCoordinator = BrowserDownloadCoordinator()
  private let bookmarkManager = BookmarkManager()
  private let historyManager = BrowserHistoryManager()
  private let sessionManager = BrowserSessionManager()

  private var observations: [NSKeyValueObservation] = []
  private var searchEngine: BrowserSearchEngine {
    BrowserSettingsStore.shared.value.searchEngine
  }
  private var lastFailedURL: URL?
  private var sessionPersistenceTask: Task<Void, Never>?
  private var hasRestoredSession = false

  convenience init() {
    self.init(tabManager: BrowserTabManager())
  }

  init(tabManager: BrowserTabManager) {
    self.tabManager = tabManager
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    tabManager = BrowserTabManager()
    super.init(coder: coder)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
    configureActions()
    configureDownloadCoordinator()
    configureLifecycleObservers()
    applyBrowserSettings()
    if tabManager.tabs.isEmpty {
      _ = tabManager.createTab()
    }
    if let tab = tabManager.selectedTab {
      display(tab)
    }
    restoreSession()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    sessionPersistenceTask?.cancel()
  }

  private var activeWebView: WKWebView? {
    tabManager.selectedTab?.webView
  }

  private func configureView() {
    view.backgroundColor = .systemGroupedBackground

    tabCountButton.translatesAutoresizingMaskIntoConstraints = false
    tabCountButton.titleLabel?.font = .monospacedDigitSystemFont(
      ofSize: 16,
      weight: .semibold
    )
    tabCountButton.setTitleColor(.label, for: .normal)
    tabCountButton.backgroundColor = .secondarySystemGroupedBackground
    tabCountButton.layer.cornerRadius = 12
    tabCountButton.layer.cornerCurve = .continuous
    tabCountButton.accessibilityLabel = "打开标签页"

    privateBadge.translatesAutoresizingMaskIntoConstraints = false
    privateBadge.text = "无痕"
    privateBadge.textColor = .systemPurple
    privateBadge.font = .preferredFont(forTextStyle: .caption1)
    privateBadge.isHidden = true

    moreButton.translatesAutoresizingMaskIntoConstraints = false
    moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
    moreButton.tintColor = .label
    moreButton.showsMenuAsPrimaryAction = true
    moreButton.accessibilityLabel = "更多"

    contentView.translatesAutoresizingMaskIntoConstraints = false
    contentView.backgroundColor = .systemBackground
    contentView.layer.cornerRadius = 16
    contentView.layer.cornerCurve = .continuous
    contentView.clipsToBounds = true

    homeView.translatesAutoresizingMaskIntoConstraints = false
    errorView.translatesAutoresizingMaskIntoConstraints = false
    errorView.isHidden = true
    findBar.translatesAutoresizingMaskIntoConstraints = false
    findBar.isHidden = true

    view.addSubview(tabCountButton)
    view.addSubview(privateBadge)
    view.addSubview(moreButton)
    view.addSubview(addressBar)
    view.addSubview(contentView)
    view.addSubview(findBar)
    view.addSubview(toolbar)
    contentView.addSubview(homeView)
    contentView.addSubview(errorView)

    NSLayoutConstraint.activate([
      tabCountButton.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 6
      ),
      tabCountButton.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: 16
      ),
      tabCountButton.widthAnchor.constraint(equalToConstant: 46),
      tabCountButton.heightAnchor.constraint(equalToConstant: 34),
      privateBadge.leadingAnchor.constraint(
        equalTo: tabCountButton.trailingAnchor,
        constant: 10
      ),
      privateBadge.centerYAnchor.constraint(equalTo: tabCountButton.centerYAnchor),
      moreButton.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -16
      ),
      moreButton.centerYAnchor.constraint(equalTo: tabCountButton.centerYAnchor),
      moreButton.widthAnchor.constraint(equalToConstant: 44),
      moreButton.heightAnchor.constraint(equalToConstant: 44),
      addressBar.topAnchor.constraint(
        equalTo: tabCountButton.bottomAnchor,
        constant: 8
      ),
      addressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      addressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      contentView.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 8),
      contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: findBar.topAnchor, constant: -8),
      findBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      findBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      findBar.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -8),
      toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      toolbar.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -6
      ),
      toolbar.heightAnchor.constraint(equalToConstant: 56),
      homeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      homeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      homeView.topAnchor.constraint(equalTo: contentView.topAnchor),
      homeView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      errorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      errorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      errorView.topAnchor.constraint(equalTo: contentView.topAnchor),
      errorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  private func configureActions() {
    tabManager.onSelectedTabChanged = { [weak self] tab in
      self?.display(tab)
    }
    tabManager.onTabsChanged = { [weak self] in
      self?.refreshChrome()
    }

    tabCountButton.addAction(UIAction { [weak self] _ in
      self?.showTabs()
    }, for: .touchUpInside)

    addressBar.onSubmit = { [weak self] value in
      self?.navigate(to: value)
    }
    addressBar.onLongPress = { [weak self] in
      guard let self else { return }
      self.showAddressActions()
    }
    addressBar.onPaste = { [weak self] in
      guard let value = UIPasteboard.general.string else { return }
      self?.navigate(to: value)
    }
    addressBar.onScan = { [weak self] in
      self?.showQRScanner()
    }
    addressBar.onReloadOrStop = { [weak self] in
      guard let webView = self?.activeWebView else { return }
      if webView.isLoading {
        webView.stopLoading()
      } else {
        webView.reload()
      }
    }

    toolbar.onBack = { [weak self] in self?.activeWebView?.goBack() }
    toolbar.onForward = { [weak self] in self?.activeWebView?.goForward() }
    toolbar.onHome = { [weak self] in self?.showHome() }
    toolbar.onShare = { [weak self] in self?.shareCurrentPage() }
    toolbar.onTabs = { [weak self] in self?.showTabs() }
    toolbar.onBackHistory = { [weak self] in
      self?.showNavigationHistory(isBackList: true)
    }
    toolbar.onForwardHistory = { [weak self] in
      self?.showNavigationHistory(isBackList: false)
    }

    homeView.onOpen = { [weak self] value in
      self?.navigate(to: value)
    }
    homeView.onShortcut = { [weak self] url in
      self?.load(url)
    }
    errorView.onRetry = { [weak self] in
      guard let self else { return }
      if let lastFailedURL {
        self.load(lastFailedURL)
      } else {
        self.activeWebView?.reload()
      }
    }
    findBar.onChange = { [weak self] query in
      self?.find(query: query)
    }
    findBar.onPrevious = { [weak self] query in
      self?.find(query: query, backwards: true)
    }
    findBar.onNext = { [weak self] query in
      self?.find(query: query)
    }
    findBar.onClose = { [weak self] in
      self?.setFindBarVisible(false)
    }
  }

  private func configureLifecycleObservers() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillTerminate),
      name: UIApplication.willTerminateNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(browserSettingsDidChange),
      name: .browserSettingsDidChange,
      object: nil
    )
  }

  private func restoreSession() {
    guard !hasRestoredSession else { return }
    hasRestoredSession = true
    guard BrowserSettingsStore.shared.value.restoresTabs else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        guard let state = try await self.sessionManager.restore(),
              !state.tabs.isEmpty
        else {
          return
        }
        let restoredTabs = state.tabs
        self.tabManager.replaceNormalTabs(
          with: restoredTabs,
          selectedTabID: state.selectedTabID
        )
        for snapshot in restoredTabs {
          guard let fileName = snapshot.screenshotFileName,
                let data = try? await self.sessionManager.screenshotData(
                  fileName: fileName
                ),
                let image = UIImage(data: data),
                let tab = self.tabManager.tab(id: snapshot.id)
          else {
            continue
          }
          tab.screenshot = image
        }
      } catch {
        self.showNotice(
          title: "标签页恢复失败",
          message: "已为你打开一个新的空白标签页。"
        )
      }
    }
  }

  private func persistSession() {
    sessionPersistenceTask?.cancel()
    sessionPersistenceTask = Task { [weak self] in
      guard let self else { return }
      var snapshots: [BrowserTabSnapshot] = []
      var screenshotNames = Set<String>()

      for tab in self.tabManager.tabs where !tab.isPrivate {
        if let webView = tab.webView {
          tab.captureState(from: webView)
          if let image = await self.snapshot(of: webView) {
            tab.screenshot = image
          }
        }
        var screenshotFileName: String?
        if let data = tab.screenshot?.jpegData(compressionQuality: 0.72),
           let savedName = try? await self.sessionManager.saveScreenshot(
             data,
             tabID: tab.id
           ) {
          screenshotFileName = savedName
          screenshotNames.insert(savedName)
        }
        snapshots.append(
          tab.makeSnapshot(screenshotFileName: screenshotFileName)
        )
      }
      guard !Task.isCancelled else { return }
      let selectedNormalID = self.tabManager.selectedTab?.isPrivate == false
        ? self.tabManager.selectedTabID
        : snapshots.first?.id
      do {
        try await self.sessionManager.save(
          BrowserSessionState(
            selectedTabID: selectedNormalID,
            tabs: snapshots
          )
        )
        try await self.sessionManager.pruneScreenshots(
          keeping: screenshotNames
        )
      } catch {
        // Session persistence is best-effort; the active browser remains usable.
      }
    }
  }

  private func snapshot(of webView: WKWebView) async -> UIImage? {
    await withCheckedContinuation { continuation in
      webView.takeSnapshot(with: nil) { image, _ in
        continuation.resume(returning: image)
      }
    }
  }

  @objc private func applicationDidEnterBackground() {
    persistSession()
  }

  @objc private func applicationWillTerminate() {
    persistSession()
    tabManager.closeAllPrivateTabs()
    Task {
      try? await sessionManager.removePrivateArtifacts()
    }
  }

  @objc private func browserSettingsDidChange() {
    applyBrowserSettings()
    Task {
      for tab in tabManager.tabs {
        guard let webView = tab.webView else { continue }
        await ContentBlockerManager.shared.apply(
          to: webView,
          for: tab.url?.host
        )
      }
      activeWebView?.reload()
    }
  }

  private func configureDownloadCoordinator() {
    downloadCoordinator.onFinished = { [weak self] url in
      self?.showNotice(
        title: "下载完成",
        message: url?.lastPathComponent ?? "文件已保存"
      )
    }
    downloadCoordinator.onFailure = { [weak self] _, _ in
      self?.showNotice(
        title: "下载失败",
        message: "服务器中断了下载，请稍后重试。"
      )
    }
  }

  private func display(_ tab: BrowserTab) {
    if let previous = contentView.subviews.compactMap({ $0 as? WKWebView }).first,
       previous !== tab.webView {
      if #available(iOS 15.0, *) {
        previous.pauseAllMediaPlayback()
      }
      previous.removeFromSuperview()
    }

    observations.removeAll()
    errorView.isHidden = true
    guard let webView = tab.webView else {
      homeView.isHidden = false
      refreshChrome(for: tab)
      return
    }
    configure(webView)
    webView.translatesAutoresizingMaskIntoConstraints = false
    contentView.insertSubview(webView, belowSubview: homeView)
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.topAnchor.constraint(equalTo: contentView.topAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
    observe(webView, tab: tab)
    homeView.isHidden = tab.url != nil
    if tab.url == nil {
      webView.isHidden = true
    } else {
      webView.isHidden = false
    }
    refreshChrome(for: tab)
  }

  private func configure(_ webView: WKWebView) {
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    webView.scrollView.keyboardDismissMode = .interactive
    if refreshControl.superview == nil {
      refreshControl.addTarget(
        self,
        action: #selector(pulledToRefresh),
        for: .valueChanged
      )
      webView.scrollView.refreshControl = refreshControl
    } else if webView.scrollView.refreshControl == nil {
      webView.scrollView.refreshControl = UIRefreshControl()
      webView.scrollView.refreshControl?.addTarget(
        self,
        action: #selector(pulledToRefresh),
        for: .valueChanged
      )
    }
    webView.scrollView.refreshControl?.isEnabled =
      BrowserSettingsStore.shared.value.pullToRefresh
  }

  private func observe(_ webView: WKWebView, tab: BrowserTab) {
    observations = [
      observe(webView, \.title, tab: tab),
      observe(webView, \.url, tab: tab),
      observe(webView, \.estimatedProgress, tab: tab),
      observe(webView, \.canGoBack, tab: tab),
      observe(webView, \.canGoForward, tab: tab),
      observe(webView, \.isLoading, tab: tab),
    ]
  }

  private func observe<Value>(
    _ webView: WKWebView,
    _ keyPath: KeyPath<WKWebView, Value>,
    tab: BrowserTab
  ) -> NSKeyValueObservation {
    webView.observe(keyPath, options: [.initial, .new]) {
      [weak self, weak tab] webView, _ in
      Task { @MainActor in
        guard let self, let tab else { return }
        tab.captureState(from: webView)
        self.refreshChrome(for: tab)
      }
    }
  }

  private func refreshChrome() {
    guard let tab = tabManager.selectedTab else { return }
    refreshChrome(for: tab)
  }

  private func refreshChrome(for tab: BrowserTab) {
    addressBar.update(
      text: tab.url?.absoluteString ?? "",
      isSecure: tab.url?.scheme?.lowercased() == "https",
      progress: tab.estimatedProgress,
      isLoading: tab.isLoading
    )
    toolbar.update(
      canGoBack: tab.canGoBack,
      canGoForward: tab.canGoForward,
      tabCount: tabManager.tabs.count
    )
    tabCountButton.setTitle(String(tabManager.tabs.count), for: .normal)
    privateBadge.isHidden = !tab.isPrivate
    moreButton.menu = makePageMenu()
    homeView.isHidden = tab.url != nil
  }

  private func navigate(to rawValue: String) {
    guard let url = BrowserURLResolver.resolve(
      rawValue,
      searchEngine: searchEngine
    ) else {
      return
    }
    load(url)
  }

  private func load(_ url: URL) {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let tab = tabManager.selectedTab
    else {
      return
    }
    tab.url = url
    homeView.isHidden = true
    errorView.isHidden = true
    tab.webView?.isHidden = false
    tab.webView?.load(URLRequest(url: url))
  }

  private func showHome() {
    activeWebView?.stopLoading()
    tabManager.selectedTab?.url = nil
    activeWebView?.isHidden = true
    homeView.isHidden = false
    errorView.isHidden = true
    addressBar.update(
      text: "",
      isSecure: false,
      progress: 0,
      isLoading: false
    )
  }

  private func shareCurrentPage() {
    guard let url = tabManager.selectedTab?.url else { return }
    let controller = UIActivityViewController(
      activityItems: [url],
      applicationActivities: nil
    )
    controller.popoverPresentationController?.sourceView = toolbar.shareButton
    present(controller, animated: true)
  }

  private func showTabs() {
    captureCurrentSnapshot()
    let controller = BrowserTabSwitcherViewController(manager: tabManager)
    controller.onSelectTab = { [weak self, weak controller] id in
      _ = self?.tabManager.activateTab(id: id)
      controller?.dismiss(animated: true)
    }
    let navigation = UINavigationController(rootViewController: controller)
    navigation.modalPresentationStyle = .pageSheet
    if let sheet = navigation.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
    }
    present(navigation, animated: true)
  }

  private func captureCurrentSnapshot() {
    guard let tab = tabManager.selectedTab,
          let webView = tab.webView,
          tab.url != nil,
          !tab.isPrivate
    else {
      return
    }
    webView.takeSnapshot(with: nil) { [weak tab] image, _ in
      tab?.screenshot = image
    }
  }

  private func makePageMenu() -> UIMenu {
    let hasPage = tabManager.selectedTab?.url != nil
    return UIMenu(children: [
      UIMenu(title: "", options: .displayInline, children: [
        UIAction(
          title: activeWebView?.isLoading == true ? "停止载入" : "重新载入",
          image: UIImage(
            systemName: activeWebView?.isLoading == true
              ? "xmark"
              : "arrow.clockwise"
          ),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          guard let webView = self?.activeWebView else { return }
          if webView.isLoading {
            webView.stopLoading()
          } else {
            webView.reload()
          }
        },
        UIAction(
          title: "在网页内查找",
          image: UIImage(systemName: "text.magnifyingglass"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          self?.setFindBarVisible(true)
        },
        UIAction(
          title: "添加书签",
          image: UIImage(systemName: "bookmark")
        ) { [weak self] _ in
          self?.addCurrentPageToBookmarks()
        },
      ]),
      UIMenu(title: "浏览器资料", children: [
        UIAction(
          title: "书签",
          image: UIImage(systemName: "bookmark.fill")
        ) { [weak self] _ in
          self?.showBrowserLibrary(showHistory: false)
        },
        UIAction(
          title: "历史记录",
          image: UIImage(systemName: "clock.arrow.circlepath")
        ) { [weak self] _ in
          self?.showBrowserLibrary(showHistory: true)
        },
        UIAction(
          title: "下载记录",
          image: UIImage(systemName: "arrow.down.circle")
        ) { [weak self] _ in
          self?.showDownloads()
        },
        UIAction(
          title: "已下载",
          image: UIImage(systemName: "folder")
        ) { [weak self] _ in
          self?.showLibrary()
        },
      ]),
      UIMenu(title: "网页显示", children: [
        UIAction(
          title: "请求桌面网站",
          image: UIImage(systemName: "desktopcomputer"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          self?.requestDesktopSite()
        },
        UIAction(
          title: "请求移动网站",
          image: UIImage(systemName: "iphone"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          self?.requestMobileSite()
        },
      ]),
      UIMenu(title: "", options: .displayInline, children: [
        UIAction(
          title: "复制链接",
          image: UIImage(systemName: "doc.on.doc"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          UIPasteboard.general.url = self?.tabManager.selectedTab?.url
        },
        UIAction(
          title: "在 Safari 中打开",
          image: UIImage(systemName: "safari"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          guard let url = self?.tabManager.selectedTab?.url else { return }
          UIApplication.shared.open(url)
        },
        UIAction(
          title: "网站信息",
          image: UIImage(systemName: "info.circle"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          self?.showWebsiteInformation()
        },
        UIAction(
          title: "清除此网站数据",
          image: UIImage(systemName: "trash"),
          attributes: hasPage ? [.destructive] : [.disabled]
        ) { [weak self] _ in
          self?.confirmClearCurrentWebsiteData()
        },
        UIAction(
          title: "设置",
          image: UIImage(systemName: "gearshape")
        ) { [weak self] _ in
          self?.showSettings()
        },
      ]),
    ])
  }

  private func showAddressActions() {
    let alert = UIAlertController(
      title: tabManager.selectedTab?.url?.host ?? "地址",
      message: tabManager.selectedTab?.url?.absoluteString,
      preferredStyle: .actionSheet
    )
    alert.addAction(UIAlertAction(title: "复制网址", style: .default) {
      [weak self] _ in
      UIPasteboard.general.url = self?.tabManager.selectedTab?.url
    })
    if UIPasteboard.general.hasStrings {
      alert.addAction(UIAlertAction(title: "粘贴并访问", style: .default) {
        [weak self] _ in
        guard let value = UIPasteboard.general.string else { return }
        self?.navigate(to: value)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.sourceView = addressBar
    present(alert, animated: true)
  }

  private func showNavigationHistory(isBackList: Bool) {
    guard let webView = activeWebView else { return }
    let items = isBackList
      ? webView.backForwardList.backList.reversed()
      : webView.backForwardList.forwardList
    let alert = UIAlertController(
      title: isBackList ? "后退历史" : "前进历史",
      message: nil,
      preferredStyle: .actionSheet
    )
    for item in items.prefix(12) {
      alert.addAction(UIAlertAction(
        title: item.title?.isEmpty == false ? item.title : item.url.host,
        style: .default
      ) { [weak webView] _ in
        webView?.go(to: item)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.sourceView = isBackList
      ? toolbar.backButton
      : toolbar.forwardButton
    present(alert, animated: true)
  }

  private func setFindBarVisible(_ visible: Bool) {
    findBar.isHidden = !visible
    if visible {
      findBar.focus()
    } else {
      view.endEditing(true)
    }
  }

  private func find(query: String, backwards: Bool = false) {
    guard !query.isEmpty, let webView = activeWebView else {
      findBar.update(resultText: "0/0")
      return
    }
    let configuration = WKFindConfiguration()
    configuration.backwards = backwards
    configuration.wraps = true
    webView.find(query, configuration: configuration) {
      [weak self] result in
      self?.findBar.update(
        resultText: result.matchFound ? "已找到" : "无结果"
      )
    }
  }

  private func requestDesktopSite() {
    activeWebView?.customUserAgent =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    activeWebView?.reload()
  }

  private func requestMobileSite() {
    activeWebView?.customUserAgent = nil
    activeWebView?.reload()
  }

  private func addCurrentPageToBookmarks() {
    guard let tab = tabManager.selectedTab,
          let url = tab.url
    else {
      return
    }
    Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await self.bookmarkManager.add(
          title: tab.title,
          url: url
        )
        self.showNotice(title: "已添加书签", message: tab.title)
      } catch {
        self.showNotice(
          title: "无法添加书签",
          message: "浏览器资料暂时无法保存，请稍后重试。"
        )
      }
    }
  }

  private func showBrowserLibrary(showHistory: Bool) {
    let controller = BrowserLibraryViewController(showHistory: showHistory)
    controller.onOpenURL = { [weak self, weak controller] url, newTab in
      guard let self else { return }
      if newTab {
        _ = self.tabManager.createTab(url: url)
      } else {
        self.load(url)
      }
      controller?.dismiss(animated: true)
    }
    let navigation = UINavigationController(rootViewController: controller)
    navigation.modalPresentationStyle = .pageSheet
    if let sheet = navigation.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
    }
    present(navigation, animated: true)
  }

  private func showDownloads() {
    let controller = DownloadViewController()
    let navigation = UINavigationController(rootViewController: controller)
    navigation.navigationBar.prefersLargeTitles = true
    navigation.modalPresentationStyle = .pageSheet
    if let sheet = navigation.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
    }
    present(navigation, animated: true)
  }

  private func showLibrary() {
    let controller = LibraryViewController()
    let navigation = UINavigationController(rootViewController: controller)
    navigation.navigationBar.prefersLargeTitles = true
    navigation.modalPresentationStyle = .fullScreen
    present(navigation, animated: true)
  }

  private func showSettings() {
    let controller = SettingsViewController()
    let navigation = UINavigationController(rootViewController: controller)
    navigation.navigationBar.prefersLargeTitles = true
    navigation.modalPresentationStyle = .fullScreen
    present(navigation, animated: true)
  }

  private func applyBrowserSettings() {
    let settings = BrowserSettingsStore.shared.value
    overrideUserInterfaceStyle = {
      switch settings.appearance {
      case .system: return .unspecified
      case .light: return .light
      case .dark: return .dark
      }
    }()
    refreshControl.isEnabled = settings.pullToRefresh
  }

  private func showWebsiteInformation() {
    guard let url = tabManager.selectedTab?.url else { return }
    let secure = url.scheme?.lowercased() == "https"
    showNotice(
      title: secure ? "连接安全" : "连接未加密",
      message: "\(url.host ?? url.absoluteString)\n\(secure ? "使用 HTTPS 连接" : "请勿在此页面输入敏感信息")"
    )
  }

  private func confirmClearCurrentWebsiteData() {
    guard let host = tabManager.selectedTab?.url?.host else { return }
    let alert = UIAlertController(
      title: "清除 \(host) 的网站数据？",
      message: "Cookie、缓存和本地存储将被删除，网页可能需要重新登录。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "清除", style: .destructive) {
      [weak self] _ in
      Task { @MainActor in
        let records = await WebsiteDataManager.shared.records()
          .filter { $0.displayName == host || host.hasSuffix($0.displayName) }
        await WebsiteDataManager.shared.remove(records: records)
        self?.activeWebView?.reload()
      }
    })
    present(alert, animated: true)
  }

  private func showQRScanner() {
    let scanner = QRScannerViewController()
    scanner.onResult = { [weak self, weak scanner] value in
      scanner?.dismiss(animated: true)
      self?.navigate(to: value)
    }
    let navigation = UINavigationController(rootViewController: scanner)
    navigation.modalPresentationStyle = .fullScreen
    present(navigation, animated: true)
  }

  private func showNotice(title: String, message: String?) {
    let alert = UIAlertController(
      title: title,
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  private func showLoadError(_ error: Error, url: URL?) {
    let nsError = error as NSError
    if nsError.code == NSURLErrorCancelled { return }
    lastFailedURL = url
    errorView.configure(message: localizedMessage(for: nsError))
    errorView.isHidden = false
    homeView.isHidden = true
  }

  private func localizedMessage(for error: NSError) -> String {
    switch error.code {
    case NSURLErrorNotConnectedToInternet:
      "网络连接已断开，请检查网络后重试。"
    case NSURLErrorTimedOut:
      "网页响应时间过长，请稍后重试。"
    case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
      "找不到该网站，请检查网址是否正确。"
    case NSURLErrorServerCertificateUntrusted,
         NSURLErrorServerCertificateHasBadDate,
         NSURLErrorServerCertificateHasUnknownRoot:
      "网站证书无效，为保护你的安全已停止载入。"
    default:
      "网页暂时无法打开，请稍后重试。"
    }
  }

  private func confirmOpenExternalURL(_ url: URL) {
    guard UIApplication.shared.canOpenURL(url) else {
      showNotice(title: "无法打开", message: "设备上没有可处理此链接的应用。")
      return
    }
    let alert = UIAlertController(
      title: "离开 VidSniffer Pro？",
      message: "即将在其他应用中打开 \(url.scheme ?? "链接")。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "打开", style: .default) { _ in
      UIApplication.shared.open(url)
    })
    present(alert, animated: true)
  }

  @objc private func pulledToRefresh(_ sender: UIRefreshControl) {
    activeWebView?.reload()
    sender.endRefreshing()
  }
}

extension BrowserViewController: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    let scheme = url.scheme?.lowercased() ?? ""
    if ["http", "https", "about", "data", "blob"].contains(scheme) {
      if #available(iOS 14.5, *), navigationAction.shouldPerformDownload {
        decisionHandler(.download)
      } else {
        decisionHandler(.allow)
      }
      return
    }

    decisionHandler(.cancel)
    confirmOpenExternalURL(url)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if #available(iOS 14.5, *),
       !navigationResponse.canShowMIMEType {
      decisionHandler(.download)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(
    _ webView: WKWebView,
    didStartProvisionalNavigation navigation: WKNavigation?
  ) {
    errorView.isHidden = true
  }

  func webView(
    _ webView: WKWebView,
    didFinish navigation: WKNavigation?
  ) {
    guard let tab = tab(for: webView) else { return }
    tab.captureState(from: webView)
    refreshChrome(for: tab)
    webView.scrollView.refreshControl?.endRefreshing()
    if let url = tab.url {
      Task { [historyManager] in
        try? await historyManager.add(
          title: tab.title,
          url: url,
          isPrivate: tab.isPrivate
        )
      }
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation?,
    withError error: Error
  ) {
    showLoadError(error, url: webView.url)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation?,
    withError error: Error
  ) {
    showLoadError(error, url: webView.url ?? tab(for: webView)?.url)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    showNotice(
      title: "网页已自动恢复",
      message: "网页进程意外退出，正在重新载入。"
    )
    webView.reload()
  }

  func webView(
    _ webView: WKWebView,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (
      URLSession.AuthChallengeDisposition,
      URLCredential?
    ) -> Void
  ) {
    let method = challenge.protectionSpace.authenticationMethod
    if method == NSURLAuthenticationMethodHTTPBasic
      || method == NSURLAuthenticationMethodHTTPDigest {
      let alert = UIAlertController(
        title: "网站需要登录",
        message: challenge.protectionSpace.host,
        preferredStyle: .alert
      )
      alert.addTextField { field in
        field.placeholder = "用户名"
        field.textContentType = .username
      }
      alert.addTextField { field in
        field.placeholder = "密码"
        field.isSecureTextEntry = true
        field.textContentType = .password
      }
      alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
        completionHandler(.cancelAuthenticationChallenge, nil)
      })
      alert.addAction(UIAlertAction(title: "登录", style: .default) { _ in
        let username = alert.textFields?.first?.text ?? ""
        let password = alert.textFields?.last?.text ?? ""
        completionHandler(
          .useCredential,
          URLCredential(
            user: username,
            password: password,
            persistence: .forSession
          )
        )
      })
      present(alert, animated: true)
      return
    }

    completionHandler(.performDefaultHandling, nil)
  }

  @available(iOS 14.5, *)
  func webView(
    _ webView: WKWebView,
    navigationAction: WKNavigationAction,
    didBecome download: WKDownload
  ) {
    download.delegate = downloadCoordinator
  }

  @available(iOS 14.5, *)
  func webView(
    _ webView: WKWebView,
    navigationResponse: WKNavigationResponse,
    didBecome download: WKDownload
  ) {
    download.delegate = downloadCoordinator
  }

  private func tab(for webView: WKWebView) -> BrowserTab? {
    tabManager.tabs.first { $0.webView === webView }
  }
}

extension BrowserViewController: WKUIDelegate {
  @available(iOS 15.0, *)
  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    let resource: String
    switch type {
    case .camera: resource = "摄像头"
    case .microphone: resource = "麦克风"
    case .cameraAndMicrophone: resource = "摄像头和麦克风"
    @unknown default: resource = "媒体设备"
    }
    let alert = UIAlertController(
      title: "\(origin.host) 想使用\(resource)",
      message: "只有在你允许后，此网站才能访问\(resource)。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "不允许", style: .cancel) { _ in
      decisionHandler(.deny)
    })
    alert.addAction(UIAlertAction(title: "允许", style: .default) { _ in
      decisionHandler(.grant)
    })
    present(alert, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    guard navigationAction.targetFrame == nil else { return nil }
    let settings = BrowserSettingsStore.shared.value
    if settings.blocksPopups,
       navigationAction.navigationType == .other,
       let sourceHost = webView.url?.host,
       let destinationHost = navigationAction.request.url?.host,
       sourceHost != destinationHost {
      return nil
    }
    let sourceIsPrivate = tab(for: webView)?.isPrivate ?? false
    let tab = tabManager.createTab(isPrivate: sourceIsPrivate)
    guard let newWebView = tab.webView else { return nil }
    configure(newWebView)
    if let url = navigationAction.request.url {
      tab.url = url
    }
    return newWebView
  }

  func webViewDidClose(_ webView: WKWebView) {
    guard let tab = tab(for: webView) else { return }
    tabManager.closeTab(id: tab.id)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping () -> Void
  ) {
    let alert = UIAlertController(
      title: webView.url?.host ?? "网页提示",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default) { _ in
      completionHandler()
    })
    present(alert, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (Bool) -> Void
  ) {
    let alert = UIAlertController(
      title: webView.url?.host ?? "网页确认",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
      completionHandler(false)
    })
    alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
      completionHandler(true)
    })
    present(alert, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void
  ) {
    let alert = UIAlertController(
      title: webView.url?.host ?? "网页输入",
      message: prompt,
      preferredStyle: .alert
    )
    alert.addTextField { $0.text = defaultText }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
      completionHandler(nil)
    })
    alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
      completionHandler(alert.textFields?.first?.text)
    })
    present(alert, animated: true)
  }
}

@MainActor
private final class BrowserHomeView: UIView {
  var onOpen: ((String) -> Void)?
  var onShortcut: ((URL) -> Void)?

  private let textField = UITextField()

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    backgroundColor = .systemGroupedBackground

    let title = UILabel()
    title.text = "浏览器"
    title.font = .preferredFont(forTextStyle: .largeTitle)
    title.adjustsFontForContentSizeCategory = true

    let subtitle = UILabel()
    subtitle.text = "搜索网页或输入网址"
    subtitle.font = .preferredFont(forTextStyle: .subheadline)
    subtitle.textColor = .secondaryLabel

    textField.backgroundColor = .secondarySystemGroupedBackground
    textField.layer.cornerRadius = 16
    textField.layer.cornerCurve = .continuous
    textField.placeholder = "搜索或输入网址"
    textField.returnKeyType = .go
    textField.keyboardType = .webSearch
    textField.autocapitalizationType = .none
    textField.autocorrectionType = .no
    textField.leftView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    textField.leftViewMode = .always
    textField.addAction(UIAction { [weak self] _ in
      guard let value = self?.textField.text else { return }
      self?.onOpen?(value)
      self?.textField.resignFirstResponder()
    }, for: .editingDidEndOnExit)
    textField.heightAnchor.constraint(equalToConstant: 54).isActive = true

    let shortcuts: [(String, String, String)] = [
      ("Google", "g.circle.fill", "https://www.google.com"),
      ("Bing", "b.circle.fill", "https://www.bing.com"),
      ("Wikipedia", "w.circle.fill", "https://www.wikipedia.org"),
      ("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com"),
      ("Apple", "apple.logo", "https://www.apple.com"),
    ]
    let shortcutStack = UIStackView()
    shortcutStack.axis = .horizontal
    shortcutStack.distribution = .fillEqually
    shortcutStack.spacing = 8
    for (name, icon, value) in shortcuts {
      let button = UIButton(type: .system)
      var configuration = UIButton.Configuration.gray()
      configuration.title = name
      configuration.image = UIImage(systemName: icon)
      configuration.imagePlacement = .top
      configuration.imagePadding = 7
      configuration.baseForegroundColor = .label
      configuration.cornerStyle = .large
      button.configuration = configuration
      button.addAction(UIAction { [weak self] _ in
        guard let url = URL(string: value) else { return }
        self?.onShortcut?(url)
      }, for: .touchUpInside)
      shortcutStack.addArrangedSubview(button)
    }
    shortcutStack.heightAnchor.constraint(equalToConstant: 82).isActive = true

    let stack = UIStackView(arrangedSubviews: [
      title,
      subtitle,
      textField,
      shortcutStack,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 12
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 34),
    ])
  }
}

@MainActor
private final class BrowserErrorView: UIView {
  var onRetry: (() -> Void)?
  private let messageLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  func configure(message: String) {
    messageLabel.text = message
  }

  private func configure() {
    backgroundColor = .systemBackground
    let icon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
    icon.tintColor = .secondaryLabel
    icon.contentMode = .scaleAspectFit
    icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

    let title = UILabel()
    title.text = "无法打开网页"
    title.font = .preferredFont(forTextStyle: .title2)
    title.textAlignment = .center

    messageLabel.font = .preferredFont(forTextStyle: .body)
    messageLabel.textColor = .secondaryLabel
    messageLabel.numberOfLines = 0
    messageLabel.textAlignment = .center

    let retry = UIButton(type: .system)
    var configuration = UIButton.Configuration.filled()
    configuration.title = "重试"
    configuration.cornerStyle = .large
    retry.configuration = configuration
    retry.addAction(UIAction { [weak self] _ in
      self?.onRetry?()
    }, for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [icon, title, messageLabel, retry])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 14
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 30),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -30),
      retry.heightAnchor.constraint(equalToConstant: 46),
    ])
  }
}

@MainActor
private final class BrowserFindBar: UIVisualEffectView {
  var onChange: ((String) -> Void)?
  var onPrevious: ((String) -> Void)?
  var onNext: ((String) -> Void)?
  var onClose: (() -> Void)?

  private let textField = UITextField()
  private let resultLabel = UILabel()

  init() {
    super.init(effect: UIBlurEffect(style: .systemChromeMaterial))
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    effect = UIBlurEffect(style: .systemChromeMaterial)
    configure()
  }

  func focus() {
    textField.becomeFirstResponder()
  }

  func update(resultText: String) {
    resultLabel.text = resultText
  }

  private func configure() {
    layer.cornerRadius = 16
    layer.cornerCurve = .continuous
    clipsToBounds = true
    heightAnchor.constraint(equalToConstant: 48).isActive = true

    textField.placeholder = "在网页内查找"
    textField.autocorrectionType = .no
    textField.clearButtonMode = .whileEditing
    textField.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      self.onChange?(self.textField.text ?? "")
    }, for: .editingChanged)

    resultLabel.text = "0/0"
    resultLabel.font = .preferredFont(forTextStyle: .caption1)
    resultLabel.textColor = .secondaryLabel

    let previous = makeButton(icon: "chevron.up") { [weak self] in
      guard let self else { return }
      self.onPrevious?(self.textField.text ?? "")
    }
    let next = makeButton(icon: "chevron.down") { [weak self] in
      guard let self else { return }
      self.onNext?(self.textField.text ?? "")
    }
    let close = makeButton(icon: "xmark") { [weak self] in
      self?.onClose?()
    }

    let stack = UIStackView(arrangedSubviews: [
      textField,
      resultLabel,
      previous,
      next,
      close,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.spacing = 8
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
    ])
  }

  private func makeButton(icon: String, action: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: icon), for: .normal)
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    button.widthAnchor.constraint(equalToConstant: 36).isActive = true
    return button
  }
}

@MainActor
private final class QRScannerViewController:
  UIViewController,
  @preconcurrency AVCaptureMetadataOutputObjectsDelegate
{
  var onResult: ((String) -> Void)?

  private let captureSession = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private let statusLabel = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "扫描二维码"
    view.backgroundColor = .black
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
    )
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.textColor = .white
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    statusLabel.text = "将二维码放入取景框"
    view.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      statusLabel.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -30
      ),
    ])
    requestCameraAccess()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if captureSession.isRunning {
      captureSession.stopRunning()
    }
  }

  private func requestCameraAccess() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureCaptureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        Task { @MainActor in
          granted
            ? self?.configureCaptureSession()
            : self?.showPermissionDenied()
        }
      }
    default:
      showPermissionDenied()
    }
  }

  private func configureCaptureSession() {
    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          captureSession.canAddInput(input)
    else {
      statusLabel.text = "无法使用相机"
      return
    }
    captureSession.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard captureSession.canAddOutput(output) else { return }
    captureSession.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]

    let preview = AVCaptureVideoPreviewLayer(session: captureSession)
    preview.videoGravity = .resizeAspectFill
    view.layer.insertSublayer(preview, at: 0)
    previewLayer = preview
    DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
      captureSession.startRunning()
    }
  }

  private func showPermissionDenied() {
    statusLabel.text = "相机权限未开启，请在系统设置中允许相机访问。"
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          let value = code.stringValue
    else {
      return
    }
    captureSession.stopRunning()
    onResult?(value)
  }
}
