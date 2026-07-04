import Foundation
import UIKit
import WebKit
import AVKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AppTheme.install()
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

enum AppTheme {
    static let accent = UIColor(red: 0.02, green: 0.39, blue: 0.92, alpha: 1)
    static let accent2 = UIColor(red: 0.00, green: 0.66, blue: 0.75, alpha: 1)
    static let warning = UIColor(red: 0.94, green: 0.43, blue: 0.12, alpha: 1)

    static func install() {
        UINavigationBar.appearance().tintColor = accent
        UITabBar.appearance().tintColor = accent
        UITableView.appearance().backgroundColor = .systemGroupedBackground
    }
}

final class HeroPanelView: UIView {
    private let gradient = CAGradientLayer()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let badgeLabel = UILabel()

    init(title: String, subtitle: String, badge: String) {
        super.init(frame: .zero)
        layer.cornerRadius = 18
        layer.masksToBounds = true
        gradient.colors = [AppTheme.accent.cgColor, AppTheme.accent2.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)

        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .title1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2

        badgeLabel.text = badge
        badgeLabel.textColor = .white
        badgeLabel.font = .preferredFont(forTextStyle: .caption1)
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.layer.masksToBounds = true
        badgeLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [badgeLabel, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            badgeLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

final class ResourceCell: UITableViewCell {
    private let typeBadge = UILabel()
    private let title = UILabel()
    private let detail = UILabel()
    private let downloadButton = UIButton(type: .system)
    private var onDownload: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        contentView.backgroundColor = .secondarySystemGroupedBackground

        typeBadge.textAlignment = .center
        typeBadge.font = .preferredFont(forTextStyle: .caption1)
        typeBadge.adjustsFontForContentSizeCategory = true
        typeBadge.textColor = .white
        typeBadge.backgroundColor = AppTheme.accent
        typeBadge.layer.cornerRadius = 8
        typeBadge.layer.masksToBounds = true

        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 2

        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 2

        downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        downloadButton.setTitle(" 下载", for: .normal)
        downloadButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        downloadButton.tintColor = .white
        downloadButton.backgroundColor = AppTheme.accent
        downloadButton.layer.cornerRadius = 16
        downloadButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [typeBadge, title, detail])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 6

        let row = UIStackView(arrangedSubviews: [textStack, downloadButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            typeBadge.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            typeBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            downloadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with resource: VideoResource, onDownload: @escaping () -> Void) {
        typeBadge.text = resource.type
        typeBadge.backgroundColor = resource.type == "HLS" ? AppTheme.warning : AppTheme.accent
        title.text = resource.title
        detail.text = "\(resource.source)\n\(resource.url.absoluteString)"
        self.onDownload = onDownload
    }

    @objc private func downloadTapped() {
        onDownload?()
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
        record.status = resource.type == "HLS" ? "HLS 转码保存中" : "下载中"
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
        if resource.type == "HLS" {
            exportHLS(resource: resource, completion: completion)
            return
        }

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

    private func exportHLS(resource: VideoResource, completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            try FileManager.default.createDirectory(at: Self.videosDirectory, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        let asset = AVURLAsset(url: resource.url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
            ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            completion(.failure(NSError(domain: "VidSniffer", code: -20, userInfo: [NSLocalizedDescriptionKey: "当前系统无法导出这个 m3u8 视频"])))
            return
        }

        let outputType: AVFileType
        let outputExtension: String
        if session.supportedFileTypes.contains(.mp4) {
            outputType = .mp4
            outputExtension = "mp4"
        } else if session.supportedFileTypes.contains(.m4v) {
            outputType = .m4v
            outputExtension = "m4v"
        } else {
            completion(.failure(NSError(domain: "VidSniffer", code: -21, userInfo: [NSLocalizedDescriptionKey: "这个 m3u8 不支持导出为本地视频文件"])))
            return
        }

        let target = Self.videosDirectory.appendingPathComponent(fileName(for: resource, forcedExtension: outputExtension))
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        session.outputURL = target
        session.outputFileType = outputType
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {
            DispatchQueue.main.async {
                switch session.status {
                case .completed:
                    completion(.success(target))
                case .failed:
                    completion(.failure(session.error ?? NSError(domain: "VidSniffer", code: -22, userInfo: [NSLocalizedDescriptionKey: "m3u8 转码失败"])))
                case .cancelled:
                    completion(.failure(NSError(domain: "VidSniffer", code: -23, userInfo: [NSLocalizedDescriptionKey: "m3u8 转码已取消"])))
                default:
                    completion(.failure(NSError(domain: "VidSniffer", code: -24, userInfo: [NSLocalizedDescriptionKey: "m3u8 转码没有完成"])))
                }
            }
        }
    }

    private func fileName(for resource: VideoResource, response: URLResponse?) -> String {
        fileName(for: resource, forcedExtension: nil)
    }

    private func fileName(for resource: VideoResource, forcedExtension: String?) -> String {
        let rawTitle = resource.title.isEmpty ? "video" : resource.title
        let safeTitle = rawTitle
            .replacingOccurrences(of: "[^A-Za-z0-9._ -]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = forcedExtension ?? (resource.url.pathExtension.isEmpty ? "mp4" : resource.url.pathExtension)
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
        view.backgroundColor = .systemGroupedBackground
        tabBar.tintColor = AppTheme.accent
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
        controller.navigationBar.tintColor = AppTheme.accent
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
    private let hero = HeroPanelView(
        title: "视频解析工作台",
        subtitle: "输入网页链接后扫描直链；m3u8 会尝试转存为本地视频，不再只保存文本清单。",
        badge: "Native iOS"
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "解析"
        view.backgroundColor = .systemGroupedBackground
        configureUI()
        store.observe { [weak self] in self?.tableView.reloadData() }
    }

    private func configureUI() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        urlField.borderStyle = .roundedRect
        urlField.placeholder = "粘贴网页或视频链接"
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.clearButtonMode = .whileEditing
        urlField.font = .preferredFont(forTextStyle: .body)
        urlField.returnKeyType = .go
        urlField.addTarget(self, action: #selector(parseTapped), for: .primaryActionTriggered)
        urlField.backgroundColor = .secondarySystemGroupedBackground

        let button = UIButton(type: .system)
        button.setTitle("解析", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.tintColor = .white
        button.backgroundColor = AppTheme.accent
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(parseTapped), for: .touchUpInside)

        statusLabel.text = "输入网页后会扫描源码里的 mp4、m3u8、ts 资源。"
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 104
        tableView.keyboardDismissMode = .onDrag
        tableView.register(ResourceCell.self, forCellReuseIdentifier: "ResourceCell")

        let row = UIStackView(arrangedSubviews: [urlField, button])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .fill
        button.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let inputPanel = UIStackView(arrangedSubviews: [row, statusLabel])
        inputPanel.axis = .vertical
        inputPanel.spacing = 10
        inputPanel.backgroundColor = .secondarySystemGroupedBackground
        inputPanel.layer.cornerRadius = 16
        inputPanel.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        inputPanel.isLayoutMarginsRelativeArrangement = true

        let stack = UIStackView(arrangedSubviews: [hero, inputPanel, tableView])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hero.heightAnchor.constraint(greaterThanOrEqualToConstant: 136)
        ])
    }

    @objc private func parseTapped() {
        dismissKeyboard()
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
        let item = store.parsedResources[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "ResourceCell", for: indexPath) as! ResourceCell
        cell.configure(with: item) { [weak self] in
            self?.dismissKeyboard()
            self?.store.startDownload(item)
            self?.tabBarController?.selectedIndex = 2
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        store.startDownload(store.parsedResources[indexPath.row])
        tabBarController?.selectedIndex = 2
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}

final class BrowserViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, UITableViewDataSource, UITableViewDelegate {
    private let store = AppStore.shared
    private let addressField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let hero = HeroPanelView(
        title: "浏览器嗅探",
        subtitle: "打开网页后自动捕获 video、fetch、XHR 和网络性能记录里的媒体链接。",
        badge: "Live Sniffer"
    )
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
        view.backgroundColor = .systemGroupedBackground
        configureUI()
        store.observe { [weak self] in self?.tableView.reloadData() }
    }

    private func configureUI() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        addressField.borderStyle = .roundedRect
        addressField.placeholder = "输入网页地址"
        addressField.text = "https://"
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.font = .preferredFont(forTextStyle: .body)
        addressField.addTarget(self, action: #selector(loadTapped), for: .primaryActionTriggered)
        addressField.backgroundColor = .secondarySystemGroupedBackground

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(refreshTapped)),
            UIBarButtonItem(image: UIImage(systemName: "play.circle"), style: .plain, target: self, action: #selector(loadTapped))
        ]

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 104
        tableView.keyboardDismissMode = .onDrag
        tableView.register(ResourceCell.self, forCellReuseIdentifier: "ResourceCell")
        tableView.layer.cornerRadius = 16

        webView.layer.cornerRadius = 16
        webView.layer.masksToBounds = true

        let stack = UIStackView(arrangedSubviews: [hero, addressField, webView, tableView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            hero.heightAnchor.constraint(greaterThanOrEqualToConstant: 126),
            webView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.55)
        ])
    }

    @objc private func loadTapped() {
        dismissKeyboard()
        guard let url = normalizedURL(addressField.text ?? "") else { return }
        addressField.text = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    @objc private func refreshTapped() {
        dismissKeyboard()
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
        let item = store.sniffedResources[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "ResourceCell", for: indexPath) as! ResourceCell
        cell.configure(with: item) { [weak self] in
            self?.dismissKeyboard()
            self?.store.startDownload(item)
            self?.tabBarController?.selectedIndex = 2
        }
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

    @objc private func dismissKeyboard() {
        view.endEditing(true)
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
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        store.observe { [weak self] in self?.tableView.reloadData() }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.downloads.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let item = store.downloads[indexPath.row]
        cell.textLabel?.text = item.resource.title
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = "\(item.resource.type) · \(item.status)"
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: item.localURL == nil ? "clock.arrow.circlepath" : "checkmark.circle.fill")
        cell.imageView?.tintColor = item.localURL == nil ? AppTheme.warning : AppTheme.accent
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
