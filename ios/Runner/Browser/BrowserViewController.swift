import UIKit
import WebKit

@MainActor
final class BrowserViewController: UIViewController {
  private let tabManager: BrowserTabManager
  private let addressBar = AddressBarView()
  private let toolbar = BrowserToolbar()
  private let contentView = UIView()
  private let homeLabel = UILabel()
  private var observations: [NSKeyValueObservation] = []

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
    if tabManager.tabs.isEmpty {
      _ = tabManager.createTab()
    }
    if let tab = tabManager.selectedTab {
      display(tab)
    }
  }

  private func configureView() {
    view.backgroundColor = .systemGroupedBackground

    contentView.translatesAutoresizingMaskIntoConstraints = false
    contentView.backgroundColor = .systemBackground

    homeLabel.translatesAutoresizingMaskIntoConstraints = false
    homeLabel.text = "浏览器"
    homeLabel.font = .preferredFont(forTextStyle: .largeTitle)
    homeLabel.adjustsFontForContentSizeCategory = true
    homeLabel.textColor = .secondaryLabel
    homeLabel.textAlignment = .center

    view.addSubview(addressBar)
    view.addSubview(contentView)
    view.addSubview(toolbar)
    contentView.addSubview(homeLabel)

    NSLayoutConstraint.activate([
      addressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      addressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      addressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      contentView.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 8),
      contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -8),
      toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
      toolbar.heightAnchor.constraint(equalToConstant: 56),
      homeLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      homeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  private func configureActions() {
    tabManager.onSelectedTabChanged = { [weak self] tab in
      self?.display(tab)
    }
    tabManager.onTabsChanged = { [weak self] in
      guard let self else { return }
      self.toolbar.update(
        canGoBack: self.tabManager.selectedTab?.canGoBack ?? false,
        canGoForward: self.tabManager.selectedTab?.canGoForward ?? false,
        tabCount: self.tabManager.tabs.count
      )
    }

    addressBar.onSubmit = { [weak self] value in
      self?.navigate(to: value)
    }
    addressBar.onLongPress = { [weak self] in
      guard let url = self?.tabManager.selectedTab?.url else { return }
      UIPasteboard.general.url = url
    }
    toolbar.onBack = { [weak self] in self?.activeWebView?.goBack() }
    toolbar.onForward = { [weak self] in self?.activeWebView?.goForward() }
    toolbar.onHome = { [weak self] in self?.showHome() }
    toolbar.onShare = { [weak self] in self?.shareCurrentPage() }
    toolbar.onTabs = { [weak self] in self?.showTabs() }
  }

  private var activeWebView: WKWebView? {
    tabManager.selectedTab?.webView
  }

  private func display(_ tab: BrowserTab) {
    observations.removeAll()
    contentView.subviews
      .filter { $0 is WKWebView }
      .forEach { $0.removeFromSuperview() }

    guard let webView = tab.webView else {
      homeLabel.isHidden = false
      return
    }
    homeLabel.isHidden = tab.url != nil
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.navigationDelegate = self
    webView.uiDelegate = self
    contentView.insertSubview(webView, belowSubview: homeLabel)
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.topAnchor.constraint(equalTo: contentView.topAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
    observe(webView, tab: tab)
    refreshChrome(for: tab)
  }

  private func observe(_ webView: WKWebView, tab: BrowserTab) {
    observations = [
      webView.observe(\.title, options: [.initial, .new]) { [weak self, weak tab] webView, _ in
        Task { @MainActor in
          guard let self, let tab else { return }
          tab.captureState(from: webView)
          self.refreshChrome(for: tab)
        }
      },
      webView.observe(\.url, options: [.initial, .new]) { [weak self, weak tab] webView, _ in
        Task { @MainActor in
          guard let self, let tab else { return }
          tab.captureState(from: webView)
          self.refreshChrome(for: tab)
        }
      },
      webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self, weak tab] webView, _ in
        Task { @MainActor in
          guard let self, let tab else { return }
          tab.captureState(from: webView)
          self.refreshChrome(for: tab)
        }
      },
      webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self, weak tab] webView, _ in
        Task { @MainActor in
          guard let self, let tab else { return }
          tab.captureState(from: webView)
          self.refreshChrome(for: tab)
        }
      },
      webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self, weak tab] webView, _ in
        Task { @MainActor in
          guard let self, let tab else { return }
          tab.captureState(from: webView)
          self.refreshChrome(for: tab)
        }
      },
      webView.observe(\.isLoading, options: [.initial, .new]) { [weak self, weak tab] webView, _ in
        Task { @MainActor in
          guard let self, let tab else { return }
          tab.captureState(from: webView)
          self.refreshChrome(for: tab)
        }
      },
    ]
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
    homeLabel.isHidden = tab.url != nil
  }

  private func navigate(to rawValue: String) {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    let url: URL?
    if let candidate = URL(string: value),
       candidate.scheme?.isEmpty == false {
      url = candidate
    } else if value.contains(".") && !value.contains(" ") {
      url = URL(string: "https://\(value)")
    } else {
      var components = URLComponents(string: "https://www.google.com/search")
      components?.queryItems = [URLQueryItem(name: "q", value: value)]
      url = components?.url
    }
    guard let url, let tab = tabManager.selectedTab else { return }
    tab.url = url
    homeLabel.isHidden = true
    tab.webView?.load(URLRequest(url: url))
  }

  private func showHome() {
    activeWebView?.stopLoading()
    homeLabel.isHidden = false
    addressBar.update(text: "", isSecure: false, progress: 0, isLoading: false)
  }

  private func shareCurrentPage() {
    guard let url = tabManager.selectedTab?.url else { return }
    let controller = UIActivityViewController(
      activityItems: [url],
      applicationActivities: nil
    )
    present(controller, animated: true)
  }

  private func showTabs() {
    let controller = BrowserTabSwitcherViewController(manager: tabManager)
    controller.onSelectTab = { [weak self, weak controller] id in
      _ = self?.tabManager.activateTab(id: id)
      controller?.dismiss(animated: true)
    }
    let navigation = UINavigationController(rootViewController: controller)
    navigation.modalPresentationStyle = .pageSheet
    present(navigation, animated: true)
  }
}

extension BrowserViewController: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    didFinish navigation: WKNavigation?
  ) {
    guard let tab = tabManager.selectedTab else { return }
    tab.captureState(from: webView)
    refreshChrome(for: tab)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webView.reload()
  }
}

extension BrowserViewController: WKUIDelegate {}
