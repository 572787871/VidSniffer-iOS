import Foundation
import UIKit
import WebKit
import AVKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MainTabController()
        window?.makeKeyAndVisible()
        return true
    }
}

struct VideoResource: Hashable, Codable {
    var title: String
    var url: URL
    var type: String
    var source: String

    var detail: String {
        "\(type) · \(source)"
    }
}

final class AppStore {
    static let shared = AppStore()

    private(set) var parsedResources: [VideoResource] = []
    private(set) var sniffedResources: [VideoResource] = []
    private(set) var downloads: [DownloadRecord] = []
    private var observers: [() -> Void] = []

    private init() {
        reloadLocalFiles()
    }

    func setParsed(_ resources: [VideoResource]) {
        parsedResources = ordered(unique: resources)
        notify()
    }

    func addSniffed(_ resource: VideoResource) {
        guard isMediaURL(resource.url) else { return }
        if sniffedResources.contains(where: { $0.url == resource.url }) { return }
        sniffedResources.insert(resource, at: 0)
        sniffedResources = ordered(unique: sniffedResources)
        notify()
    }

    func startDownload(_ resource: VideoResource) {
        let record = DownloadRecord(resource: resource)
        downloads.insert(record, at: 0)
        notify()
        DownloadManager.shared.download(resource: resource) { [weak self, weak record] result in
            DispatchQueue.main.async {
                guard let record = record else { return }
                switch result {
                case .success(let fileURL):
                    record.status = "已保存"
                    record.localURL = fileURL
                case .failure(let error):
                    record.status = "失败：\(error.localizedDescription)"
                }
                self?.reloadLocalFiles()
                self?.notify()
            }
        }
    }

    func reloadLocalFiles() {
        try? FileManager.default.createDirectory(at: DownloadManager.videosDirectory, withIntermediateDirectories: true)
    }

    func observe(_ handler: @escaping () -> Void) {
        observers.append(handler)
    }

    private func notify() {
        observers.forEach { $0() }
    }

    private func ordered(unique resources: [VideoResource]) -> [VideoResource] {
        var seen = Set<URL>()
        return resources
            .filter { seen.insert($0.url).inserted }
            .sorted { priority($0) < priority($1) }
    }

    private func priority(_ resource: VideoResource) -> Int {
        let value = resource.url.absoluteString.lowercased()
        if value.contains(".m3u8") { return 0 }
        if value.contains(".mp4") || value.contains(".m4v") || value.contains(".mov") { return 1 }
        if value.contains(".ts") { return 2 }
        return 9
    }
}

final class DownloadRecord {
    let resource: VideoResource
    var status: String = "下载中"
    var localURL: URL?

    init(resource: VideoResource) {
        self.resource = resource
    }
}

final class DownloadManager {
    static let shared = DownloadManager()
    static var videosDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VidSniffer Videos", isDirectory: true)
    }

    private init() {}

    func download(resource: VideoResource, completion: @escaping (Result<URL, Error>) -> Void) {
        let request = URLRequest(url: resource.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let tempURL = tempURL else {
                completion(.failure(NSError(domain: "VidSniffer", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有收到文件数据"])))
                return
            }
            do {
                try FileManager.default.createDirectory(at: Self.videosDirectory, withIntermediateDirectories: true)
                let name = self.fileName(for: resource, response: response)
                let target = Self.videosDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: tempURL, to: target)
                completion(.success(target))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func fileName(for resource: VideoResource, response: URLResponse?) -> String {
        let rawTitle = resource.title.isEmpty ? "video" : resource.title
        let safeTitle = rawTitle
            .replacingOccurrences(of: "[^A-Za-z0-9._ -]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = resource.url.pathExtension.isEmpty ? (resource.type == "HLS" ? "m3u8" : "mp4") : resource.url.pathExtension
        return "\(safeTitle.isEmpty ? "video" : safeTitle)-\(Int(Date().timeIntervalSince1970)).\(ext)"
    }
}

final class VideoParser {
    func parse(_ input: String, completion: @escaping (Result<[VideoResource], Error>) -> Void) {
        guard let pageURL = normalizedURL(input) else {
            completion(.failure(NSError(domain: "VidSniffer", code: -10, userInfo: [NSLocalizedDescriptionKey: "链接格式不正确"])))
            return
        }
        var request = URLRequest(url: pageURL, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let html = String(data: data ?? Data(), encoding: .utf8)
                ?? String(data: data ?? Data(), encoding: .isoLatin1)
                ?? ""
            let resources = self.scan(html: html, baseURL: pageURL)
            completion(.success(resources))
        }.resume()
    }

    func scan(html: String, baseURL: URL, source: String = "网页解析") -> [VideoResource] {
        let title = pageTitle(in: html) ?? baseURL.host ?? "网页视频"
        var candidates: [String] = []
        let patterns = [
            #"https?:[^"'\\\s<>]+?\.(?:m3u8|mp4|m4v|mov|ts)(?:\?[^"'\\\s<>]*)?"#,
            #"(?:src|href|url|file|video|source)["'\s:=]+([^"'\s<>]+?\.(?:m3u8|mp4|m4v|mov|ts)(?:\?[^"'\s<>]*)?)"#,
            #""([^"]+?\.(?:m3u8|mp4|m4v|mov|ts)(?:\?[^"]*)?)""#
        ]
        for pattern in patterns {
            candidates.append(contentsOf: matches(pattern: pattern, in: html))
        }
        return candidates.compactMap { raw in
            let cleaned = raw
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' <>"))
            guard let url = normalizedURL(cleaned, relativeTo: baseURL), isMediaURL(url) else { return nil }
            return VideoResource(title: title, url: url, type: mediaType(url), source: source)
        }
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let index = match.numberOfRanges > 1 ? 1 : 0
            guard let matchRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func pageTitle(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range), let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[titleRange])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func normalizedURL(_ value: String, relativeTo baseURL: URL? = nil) -> URL? {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("//") {
        text = "https:\(text)"
    } else if !text.contains("://"), baseURL == nil {
        text = "https://\(text)"
    }
    return URL(string: text, relativeTo: baseURL)?.absoluteURL
}

func isMediaURL(_ url: URL) -> Bool {
    let value = url.absoluteString.lowercased()
    if value.hasPrefix("blob:") || value.hasPrefix("data:") { return false }
    if value.contains("doubleclick") || value.contains("/ads/") || value.contains("analytics") { return false }
    return [".m3u8", ".mp4", ".m4v", ".mov", ".ts"].contains { value.contains($0) }
}

func mediaType(_ url: URL) -> String {
    let value = url.absoluteString.lowercased()
    if value.contains(".m3u8") { return "HLS" }
    if value.contains(".ts") { return "TS" }
    return "MP4"
}

final class MainTabController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.tintColor = .systemBlue
        viewControllers = [
            nav(HomeViewController(), title: "解析", icon: "link"),
            nav(BrowserViewController(), title: "浏览器", icon: "safari"),
            nav(DownloadsViewController(), title: "下载", icon: "arrow.down.circle"),
            nav(FilesViewController(), title: "文件", icon: "folder"),
            nav(SettingsViewController(), title: "设置", icon: "gearshape")
        ]
    }

    private func nav(_ root: UIViewController, title: String, icon: String) -> UIViewController {
        let controller = UINavigationController(rootViewController: root)
        controller.navigationBar.prefersLargeTitles = true
        controller.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: icon), selectedImage: UIImage(systemName: "\(icon).fill"))
        return controller
    }
}

final class HomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let parser = VideoParser()
    private let store = AppStore.shared
    private let urlField = UITextField()
    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "VidSniffer Pro"
        view.backgroundColor = .systemBackground
        configureUI()
        store.observe { [weak self] in self?.tableView.reloadData() }
    }

    private func configureUI() {
        urlField.borderStyle = .roundedRect
        urlField.placeholder = "粘贴网页或视频链接"
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.clearButtonMode = .whileEditing
        urlField.font = .preferredFont(forTextStyle: .body)
        urlField.returnKeyType = .go
        urlField.addTarget(self, action: #selector(parseTapped), for: .primaryActionTriggered)

        let button = UIButton(type: .system)
        button.setTitle("解析", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: #selector(parseTapped), for: .touchUpInside)

        statusLabel.text = "输入网页后会扫描源码里的 mp4、m3u8、ts 资源。"
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        tableView.dataSource = self
        tableView.delegate = self

        let row = UIStackView(arrangedSubviews: [urlField, button])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .fill
        button.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let stack = UIStackView(arrangedSubviews: [row, statusLabel, tableView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        row.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        row.isLayoutMarginsRelativeArrangement = true
        statusLabel.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    }

    @objc private func parseTapped() {
        let input = urlField.text ?? ""
        statusLabel.text = "正在解析..."
        parser.parse(input) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let resources):
                    self?.store.setParsed(resources)
                    self?.statusLabel.text = resources.isEmpty ? "没有发现可直接下载的视频资源，可到浏览器页打开网页进行嗅探。" : "发现 \(resources.count) 个资源。"
                case .failure(let error):
                    self?.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.parsedResources.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let item = store.parsedResources[indexPath.row]
        cell.textLabel?.text = item.title
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = item.detail
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryView = UIImageView(image: UIImage(systemName: "arrow.down.circle"))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        store.startDownload(store.parsedResources[indexPath.row])
    }
}

final class BrowserViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, UITableViewDataSource, UITableViewDelegate {
    private let store = AppStore.shared
    private let addressField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "VidSniffer")
        config.userContentController.addUserScript(WKUserScript(source: snifferScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "浏览器嗅探"
        view.backgroundColor = .systemBackground
        configureUI()
        store.observe { [weak self] in self?.tableView.reloadData() }
    }

    private func configureUI() {
        addressField.borderStyle = .roundedRect
        addressField.placeholder = "输入网页地址"
        addressField.text = "https://"
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.font = .preferredFont(forTextStyle: .body)
        addressField.addTarget(self, action: #selector(loadTapped), for: .primaryActionTriggered)

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(refreshTapped)),
            UIBarButtonItem(image: UIImage(systemName: "play.circle"), style: .plain, target: self, action: #selector(loadTapped))
        ]

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64

        let stack = UIStackView(arrangedSubviews: [addressField, webView, tableView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.55)
        ])
    }

    @objc private func loadTapped() {
        guard let url = normalizedURL(addressField.text ?? "") else { return }
        addressField.text = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    @objc private func refreshTapped() {
        webView.reload()
        injectScan()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectScan()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, isMediaURL(url) {
            store.addSniffed(VideoResource(title: webView.title ?? url.lastPathComponent, url: url, type: mediaType(url), source: "导航拦截"))
        }
        decisionHandler(.allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "VidSniffer", let body = message.body as? [String: Any], let value = body["url"] as? String else { return }
        let base = webView.url
        guard let url = normalizedURL(value, relativeTo: base) else { return }
        let title = (body["title"] as? String) ?? webView.title ?? url.lastPathComponent
        let source = (body["source"] as? String) ?? "浏览器嗅探"
        store.addSniffed(VideoResource(title: title, url: url, type: mediaType(url), source: source))
    }

    private func injectScan() {
        webView.evaluateJavaScript("window.__vidsnifferScan && window.__vidsnifferScan();", completionHandler: nil)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.sniffedResources.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let item = store.sniffedResources[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.detail
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .detailButton
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = store.sniffedResources[indexPath.row]
        if item.type == "MP4" || item.type == "HLS" {
            let player = AVPlayerViewController()
            player.player = AVPlayer(url: item.url)
            present(player, animated: true) { player.player?.play() }
        }
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        store.startDownload(store.sniffedResources[indexPath.row])
    }

    private var snifferScript: String {
        """
        (function() {
          if (window.__vidsnifferReady) { window.__vidsnifferScan && window.__vidsnifferScan(); return; }
          window.__vidsnifferReady = true;
          window.__vidsnifferSeen = {};
          window.__vidsnifferPost = function(url, source) {
            try {
              if (!url || typeof url !== 'string') return;
              var absolute = new URL(url, location.href).href;
              var lower = absolute.toLowerCase();
              if (lower.indexOf('blob:') === 0 || lower.indexOf('data:') === 0) return;
              if (!(lower.indexOf('.m3u8') >= 0 || lower.indexOf('.mp4') >= 0 || lower.indexOf('.m4v') >= 0 || lower.indexOf('.mov') >= 0 || lower.indexOf('.ts') >= 0)) return;
              if (window.__vidsnifferSeen[absolute]) return;
              window.__vidsnifferSeen[absolute] = true;
              window.webkit.messageHandlers.VidSniffer.postMessage({url: absolute, title: document.title || location.hostname, source: source});
            } catch (e) {}
          };
          window.__vidsnifferScan = function() {
            try {
              document.querySelectorAll('video, source, a, iframe').forEach(function(node) {
                ['src', 'currentSrc', 'href', 'data-src'].forEach(function(key) {
                  window.__vidsnifferPost(node[key] || (node.getAttribute && node.getAttribute(key)), node.tagName.toLowerCase());
                });
              });
              performance.getEntries().forEach(function(entry) { window.__vidsnifferPost(entry.name, 'network'); });
            } catch (e) {}
          };
          var nativeFetch = window.fetch;
          if (nativeFetch) {
            window.fetch = function() {
              try { window.__vidsnifferPost((typeof arguments[0] === 'string') ? arguments[0] : arguments[0].url, 'fetch'); } catch (e) {}
              return nativeFetch.apply(this, arguments).then(function(response) {
                try { window.__vidsnifferPost(response.url, 'fetch-response'); } catch (e) {}
                return response;
              });
            };
          }
          var nativeOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url) {
            try { window.__vidsnifferPost(url, 'xhr'); } catch (e) {}
            return nativeOpen.apply(this, arguments);
          };
          new MutationObserver(window.__vidsnifferScan).observe(document.documentElement, {subtree: true, childList: true, attributes: true});
          window.__vidsnifferScan();
          setInterval(window.__vidsnifferScan, 1500);
        })();
        """
    }
}

final class DownloadsViewController: UITableViewController {
    private let store = AppStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "下载"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        store.observe { [weak self] in self?.tableView.reloadData() }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.downloads.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let item = store.downloads[indexPath.row]
        cell.textLabel?.text = item.resource.title
        cell.detailTextLabel?.text = item.status
        cell.detailTextLabel?.numberOfLines = 2
        return cell
    }
}

final class FilesViewController: UITableViewController, UIDocumentInteractionControllerDelegate {
    private var files: [URL] = []
    private var interaction: UIDocumentInteractionController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "本地文件"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(reloadFiles))
        reloadFiles()
    }

    @objc private func reloadFiles() {
        files = ((try? FileManager.default.contentsOfDirectory(at: DownloadManager.videosDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let file = files[indexPath.row]
        cell.textLabel?.text = file.lastPathComponent
        cell.detailTextLabel?.text = file.path
        cell.detailTextLabel?.numberOfLines = 1
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = files[indexPath.row]
        if ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) {
            let player = AVPlayerViewController()
            player.player = AVPlayer(url: url)
            present(player, animated: true) { player.player?.play() }
        } else {
            interaction = UIDocumentInteractionController(url: url)
            interaction?.delegate = self
            interaction?.presentOptionsMenu(from: tableView.rectForRow(at: indexPath), in: tableView, animated: true)
        }
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        self
    }
}

final class SettingsViewController: UITableViewController {
    private let rows = [
        ("界面", "原生 iOS 字体和系统背景，减少视频观看干扰。"),
        ("解析", "源码扫描 + WKWebView fetch/XHR/performance 嗅探 + 导航拦截。"),
        ("打包", "GitHub Actions 生成未签名 IPA，下载后自行签名安装。")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = rows[indexPath.row].0
        cell.detailTextLabel?.text = rows[indexPath.row].1
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }
}
