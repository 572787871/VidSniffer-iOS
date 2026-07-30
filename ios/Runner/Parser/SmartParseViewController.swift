import AVFoundation
import AVKit
import UIKit
import WebKit

struct DetectedMediaResource: Identifiable, Hashable {
  let id: UUID
  let url: URL
  var title: String
  var mimeType: String?
  var quality: String
  var format: String
  var expectedSize: Int64
  var bitrate: Int
  var duration: TimeInterval?
  var posterURL: URL?
  var pageURL: URL?

  init(
    id: UUID = UUID(),
    url: URL,
    title: String,
    mimeType: String? = nil,
    quality: String = "自动",
    format: String? = nil,
    expectedSize: Int64 = 0,
    bitrate: Int = 0,
    duration: TimeInterval? = nil,
    posterURL: URL? = nil,
    pageURL: URL? = nil
  ) {
    self.id = id
    self.url = url
    self.title = title
    self.mimeType = mimeType
    self.quality = quality
    self.format = format ?? Self.format(for: url, mimeType: mimeType)
    self.expectedSize = expectedSize
    self.bitrate = bitrate
    self.duration = duration
    self.posterURL = posterURL
    self.pageURL = pageURL
  }

  var isHLS: Bool {
    format == "HLS"
      || mimeType?.lowercased().contains("mpegurl") == true
      || url.pathExtension.lowercased() == "m3u8"
  }

  var suggestedFilename: String {
    let safeTitle = DownloadDestinationManager.sanitizedFilename(title)
    let ext: String
    switch format {
    case _ where isHLS: ext = "movpkg"
    case "MOV": ext = "mov"
    case "M4V": ext = "m4v"
    case "WEBM": ext = "webm"
    default: ext = url.pathExtension.isEmpty
      ? "mp4"
      : url.pathExtension.lowercased()
    }
    return "\(safeTitle).\(ext)"
  }

  static func format(for url: URL, mimeType: String?) -> String {
    let mime = mimeType?.lowercased() ?? ""
    let ext = url.pathExtension.lowercased()
    if ext == "m3u8" || mime.contains("mpegurl") {
      return "HLS"
    }
    if ext == "m4v" { return "M4V" }
    if ext == "mov" { return "MOV" }
    if ext == "webm" || mime.contains("webm") { return "WEBM" }
    return "MP4"
  }
}

struct HLSVariant: Equatable {
  let url: URL
  let bandwidth: Int
  let width: Int
  let height: Int
}

enum HLSManifestParser {
  static func variants(in manifest: String, baseURL: URL) -> [HLSVariant] {
    let lines = manifest.components(separatedBy: .newlines)
    var results: [HLSVariant] = []
    var index = 0
    while index < lines.count {
      let line = lines[index].trimmingCharacters(in: .whitespaces)
      guard line.hasPrefix("#EXT-X-STREAM-INF:") else {
        index += 1
        continue
      }
      let attributes = parseAttributes(
        String(line.dropFirst("#EXT-X-STREAM-INF:".count))
      )
      var next = index + 1
      while next < lines.count {
        let candidate = lines[next].trimmingCharacters(in: .whitespaces)
        if !candidate.isEmpty && !candidate.hasPrefix("#") {
          let dimensions = attributes["RESOLUTION"]?
            .split(separator: "x")
            .compactMap { Int($0) } ?? []
          if let url = URL(string: candidate, relativeTo: baseURL)?.absoluteURL {
            results.append(HLSVariant(
              url: url,
              bandwidth: Int(attributes["BANDWIDTH"] ?? "") ?? 0,
              width: dimensions.first ?? 0,
              height: dimensions.count > 1 ? dimensions[1] : 0
            ))
          }
          break
        }
        next += 1
      }
      index = next + 1
    }
    return results
  }

  static func duration(in manifest: String) -> TimeInterval? {
    let values = manifest
      .components(separatedBy: .newlines)
      .compactMap { line -> Double? in
        guard line.hasPrefix("#EXTINF:") else { return nil }
        return Double(
          line
            .dropFirst("#EXTINF:".count)
            .split(separator: ",", maxSplits: 1)
            .first ?? ""
        )
      }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
  }

  private static func parseAttributes(_ value: String) -> [String: String] {
    var result: [String: String] = [:]
    var current = ""
    var isQuoted = false
    var parts: [String] = []
    for character in value {
      if character == "\"" { isQuoted.toggle() }
      if character == "," && !isQuoted {
        parts.append(current)
        current = ""
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty { parts.append(current) }
    for part in parts {
      let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
      if pair.count == 2 {
        result[pair[0]] = pair[1].trimmingCharacters(
          in: CharacterSet(charactersIn: "\"")
        )
      }
    }
    return result
  }
}

@MainActor
final class VideoResourceStore {
  private(set) var resources: [DetectedMediaResource] = []
  var onChange: (([DetectedMediaResource]) -> Void)?

  private var knownURLs = Set<String>()
  private var enrichmentTasks: [String: Task<Void, Never>] = [:]

  deinit {
    enrichmentTasks.values.forEach { $0.cancel() }
  }

  func reset() {
    enrichmentTasks.values.forEach { $0.cancel() }
    enrichmentTasks.removeAll()
    knownURLs.removeAll()
    resources.removeAll()
    onChange?(resources)
  }

  func receive(
    payload: [String: Any],
    fallbackPageURL: URL?,
    fallbackTitle: String
  ) {
    guard let rawURL = payload["url"] as? String,
          let url = URL(string: rawURL, relativeTo: fallbackPageURL)?.absoluteURL,
          Self.isMediaCandidate(
            url: url,
            mimeType: payload["type"] as? String,
            assertedByPlayer: payload["player"] as? Bool == true
          )
    else {
      return
    }

    let key = Self.canonicalKey(for: url)
    let width = Self.intValue(payload["width"])
    let height = Self.intValue(payload["height"])
    let duration = Self.doubleValue(payload["duration"])
    let mimeType = payload["type"] as? String
    let title = (payload["title"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let poster = (payload["poster"] as? String).flatMap {
      URL(string: $0, relativeTo: fallbackPageURL)?.absoluteURL
    }
    if knownURLs.contains(key) {
      update(key: key) {
        if let mimeType, !mimeType.isEmpty {
          $0.mimeType = mimeType
          $0.format = DetectedMediaResource.format(
            for: $0.url,
            mimeType: mimeType
          )
        }
        if height > 0 { $0.quality = "\(height)p" }
        if duration > 0 { $0.duration = duration }
        if let poster { $0.posterURL = poster }
        if let title, !title.isEmpty { $0.title = title }
      }
      if let resource = resources.first(where: {
        Self.canonicalKey(for: $0.url) == key
      }) {
        enrich(resource)
      }
      return
    }

    knownURLs.insert(key)
    let resource = DetectedMediaResource(
      url: url,
      title: title?.isEmpty == false ? title! : fallbackTitle,
      mimeType: mimeType,
      quality: Self.quality(height: height, url: url),
      duration: duration > 0 ? duration : nil,
      posterURL: poster,
      pageURL: fallbackPageURL
    )
    resources.append(resource)
    sortAndPublish()
    enrich(resource)

    if width > 0 && height > 0 {
      update(url: url) { $0.quality = "\(height)p" }
    }
  }

  private func enrich(_ resource: DetectedMediaResource) {
    let key = Self.canonicalKey(for: resource.url)
    enrichmentTasks[key]?.cancel()
    enrichmentTasks[key] = Task { [weak self] in
      guard let self else { return }
      let result = await VideoResourceMetadataService.shared.inspect(resource)
      guard !Task.isCancelled else { return }
      self.update(url: resource.url) {
        $0.mimeType = result.mimeType ?? $0.mimeType
        $0.format = DetectedMediaResource.format(
          for: $0.url,
          mimeType: $0.mimeType
        )
        $0.expectedSize = result.expectedSize > 0
          ? result.expectedSize
          : $0.expectedSize
        $0.duration = result.duration ?? $0.duration
      }
      for variant in result.variants {
        let variantKey = Self.canonicalKey(for: variant.url)
        guard self.knownURLs.insert(variantKey).inserted else { continue }
        self.resources.append(DetectedMediaResource(
          url: variant.url,
          title: resource.title,
          mimeType: "application/vnd.apple.mpegurl",
          quality: variant.height > 0 ? "\(variant.height)p" : "自动",
          format: "HLS",
          expectedSize: result.duration.map {
            Int64((Double(variant.bandwidth) / 8) * $0)
          } ?? 0,
          bitrate: variant.bandwidth,
          duration: result.duration ?? resource.duration,
          posterURL: resource.posterURL,
          pageURL: resource.pageURL
        ))
      }
      self.sortAndPublish()
      self.enrichmentTasks[key] = nil
    }
  }

  private func update(
    url: URL,
    change: (inout DetectedMediaResource) -> Void
  ) {
    update(key: Self.canonicalKey(for: url), change: change)
  }

  private func update(
    key: String,
    change: (inout DetectedMediaResource) -> Void
  ) {
    guard let index = resources.firstIndex(where: {
      Self.canonicalKey(for: $0.url) == key
    }) else {
      return
    }
    change(&resources[index])
    sortAndPublish()
  }

  private func sortAndPublish() {
    resources.sort {
      let left = Self.qualityNumber($0.quality)
      let right = Self.qualityNumber($1.quality)
      if left != right { return left > right }
      if $0.format != $1.format { return $0.format < $1.format }
      return $0.url.absoluteString < $1.url.absoluteString
    }
    onChange?(resources)
  }

  private static func isMediaCandidate(
    url: URL,
    mimeType: String?,
    assertedByPlayer: Bool
  ) -> Bool {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      return false
    }
    let ext = url.pathExtension.lowercased()
    if ["mp4", "m4v", "mov", "webm", "m3u8"].contains(ext) {
      return true
    }
    let mime = mimeType?.lowercased() ?? ""
    return assertedByPlayer
      || mime.hasPrefix("video/")
      || mime.contains("mpegurl")
      || mime.contains("x-mpegurl")
  }

  private static func canonicalKey(for url: URL) -> String {
    var components = URLComponents(
      url: url,
      resolvingAgainstBaseURL: false
    )
    components?.fragment = nil
    return components?.string ?? url.absoluteString
  }

  private static func quality(height: Int, url: URL) -> String {
    if height > 0 { return "\(height)p" }
    let value = url.absoluteString.lowercased()
    for quality in [4320, 2160, 1440, 1080, 720, 540, 480, 360, 240] {
      if value.range(
        of: #"(^|[^0-9])\#(quality)p?([^0-9]|$)"#,
        options: .regularExpression
      ) != nil {
        return "\(quality)p"
      }
    }
    return "自动"
  }

  private static func qualityNumber(_ value: String) -> Int {
    Int(value.filter(\.isNumber)) ?? 0
  }

  private static func intValue(_ value: Any?) -> Int {
    if let value = value as? Int { return value }
    if let value = value as? Double { return Int(value) }
    if let value = value as? String { return Int(value) ?? 0 }
    return 0
  }

  private static func doubleValue(_ value: Any?) -> Double {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? String { return Double(value) ?? 0 }
    return 0
  }
}

actor VideoResourceMetadataService {
  static let shared = VideoResourceMetadataService()

  struct Result {
    var mimeType: String?
    var expectedSize: Int64 = 0
    var duration: TimeInterval?
    var variants: [HLSVariant] = []
  }

  func inspect(
    _ resource: DetectedMediaResource,
    requestHeaders: [String: String]? = nil
  ) async -> Result {
    var result = Result(duration: resource.duration)
    var request = URLRequest(url: resource.url)
    request.httpMethod = resource.isHLS ? "GET" : "HEAD"
    request.timeoutInterval = 12
    requestHeaders?.forEach {
      request.setValue($0.value, forHTTPHeaderField: $0.key)
    }
    if request.value(forHTTPHeaderField: "User-Agent") == nil {
      request.setValue(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
          + "AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1",
        forHTTPHeaderField: "User-Agent"
      )
    }
    if let pageURL = resource.pageURL {
      request.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
    }
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      result.mimeType = response.mimeType
      result.expectedSize = max(0, response.expectedContentLength)
      let responseIsHLS = response.mimeType?.lowercased()
        .contains("mpegurl") == true
      var manifestData = data
      var manifestResponse = response
      if responseIsHLS, request.httpMethod == "HEAD" {
        var manifestRequest = request
        manifestRequest.httpMethod = "GET"
        let responseValue = try await URLSession.shared.data(
          for: manifestRequest
        )
        manifestData = responseValue.0
        manifestResponse = responseValue.1
      }
      if (resource.isHLS || responseIsHLS),
         let manifest = String(data: manifestData, encoding: .utf8) {
        result.variants = HLSManifestParser.variants(
          in: manifest,
          baseURL: manifestResponse.url ?? resource.url
        )
        result.duration = HLSManifestParser.duration(in: manifest)
          ?? result.duration
      }
    } catch {
      return result
    }
    return result
  }
}

final class VideoDetectionBridge: NSObject, WKScriptMessageHandler {
  static let messageName = "vidSnifferResource"

  private weak var store: VideoResourceStore?
  private let pageContext: () -> (URL?, String)

  init(
    store: VideoResourceStore,
    pageContext: @escaping () -> (URL?, String)
  ) {
    self.store = store
    self.pageContext = pageContext
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.name == Self.messageName,
          let payload = message.body as? [String: Any]
    else {
      return
    }
    let context = pageContext()
    Task { @MainActor [weak store] in
      store?.receive(
        payload: payload,
        fallbackPageURL: context.0,
        fallbackTitle: context.1
      )
    }
  }

  static var userScript: WKUserScript {
    WKUserScript(
      source: scriptSource,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: false
    )
  }

  private static let scriptSource = #"""
  (() => {
    if (window.__vidSnifferInstalled) return;
    window.__vidSnifferInstalled = true;
    const sent = new Set();
    const absolute = value => {
      try { return new URL(value, document.baseURI).href; } catch (_) { return ""; }
    };
    const report = (value, type = "", element = null) => {
      const url = absolute(value);
      if (!url || sent.has(url) || !/^https?:/i.test(url)) return;
      const lower = url.toLowerCase();
      const mediaType = String(type || "").toLowerCase();
      const video = element && element.tagName === "VIDEO"
        ? element
        : (element && element.closest ? element.closest("video") : null);
      if (!/\.(m3u8|mp4|m4v|mov|webm)(?:$|[?#])/i.test(lower)
          && !mediaType.startsWith("video/")
          && !mediaType.includes("mpegurl")
          && !video) return;
      sent.add(url);
      window.webkit.messageHandlers.vidSnifferResource.postMessage({
        url,
        type: type || (element && element.type) || "",
        title: document.title || location.hostname,
        duration: video && Number.isFinite(video.duration) ? video.duration : 0,
        width: video ? (video.videoWidth || 0) : 0,
        height: video ? (video.videoHeight || 0) : 0,
        poster: video ? absolute(video.poster || "") : "",
        player: Boolean(video)
      });
    };
    const scan = root => {
      if (!root || !root.querySelectorAll) return;
      root.querySelectorAll("video, video source").forEach(node => {
        report(node.currentSrc || node.src || node.getAttribute("src"), node.type, node);
      });
      root.querySelectorAll(
        "meta[property='og:video'], meta[property='og:video:url'], "
          + "meta[name='twitter:player:stream'], link[type^='video/'], "
          + "a[href*='.m3u8'], a[href*='.mp4']"
      ).forEach(node => {
        report(node.content || node.href || node.getAttribute("content"));
      });
    };
    const originalFetch = window.fetch;
    if (originalFetch) {
      window.fetch = function(input, init) {
        const value = typeof input === "string" ? input : input && input.url;
        report(value);
        return originalFetch.apply(this, arguments).then(response => {
          report(response.url, response.headers && response.headers.get("content-type"));
          return response;
        });
      };
    }
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      report(url);
      this.addEventListener("load", () => {
        report(this.responseURL, this.getResponseHeader("content-type"));
      }, { once: true });
      return originalOpen.apply(this, arguments);
    };
    if (window.PerformanceObserver) {
      try {
        new PerformanceObserver(list => {
          list.getEntries().forEach(entry => report(entry.name));
        }).observe({ type: "resource", buffered: true });
      } catch (_) {}
    }
    const observer = new MutationObserver(records => {
      records.forEach(record => {
        record.addedNodes.forEach(node => {
          if (node.nodeType === 1) {
            if (node.matches && node.matches("video, source")) {
              report(node.currentSrc || node.src || node.getAttribute("src"), node.type, node);
            }
            scan(node);
          }
        });
        if (record.type === "attributes") {
          const node = record.target;
          report(node.currentSrc || node.src || node.getAttribute("src"), node.type, node);
        }
      });
    });
    const attachObserver = () => {
      if (!document.documentElement) return;
      observer.observe(document.documentElement, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["src", "type"]
      });
    };
    const scanInlineConfiguration = () => {
      const scripts = Array.from(document.scripts);
      let index = 0;
      let scanned = 0;
      const next = deadline => {
        while (index < scripts.length
               && scanned < 1500000
               && (!deadline || deadline.timeRemaining() > 2)) {
          const text = scripts[index++].textContent || "";
          scanned += text.length;
          const normalized = text
            .replace(/\\\//g, "/")
            .replace(/\\u0026/gi, "&");
          const matches = normalized.match(
            /(?:https?:)?\/\/[^"'<>\\s]+?\.(?:m3u8|mp4|m4v|mov|webm)(?:\?[^"'<>\\s]*)?/gi
          ) || [];
          matches.forEach(report);
        }
        if (index < scripts.length && scanned < 1500000) {
          if (window.requestIdleCallback) {
            requestIdleCallback(next, { timeout: 500 });
          } else {
            setTimeout(() => next(null), 0);
          }
        }
      };
      if (window.requestIdleCallback) {
        requestIdleCallback(next, { timeout: 500 });
      } else {
        setTimeout(() => next(null), 0);
      }
    };
    const finishScan = () => {
      attachObserver();
      scan(document);
      scanInlineConfiguration();
      document.querySelectorAll("video").forEach(video => {
        ["loadedmetadata", "durationchange"].forEach(name => {
          video.addEventListener(name, () => {
            report(video.currentSrc || video.src, video.type, video);
            scan(video.parentElement || document);
          }, { passive: true });
        });
      });
    };
    if (document.documentElement) attachObserver();
    document.addEventListener("DOMContentLoaded", finishScan, { once: true });
    window.addEventListener("load", finishScan, { once: true });
  })();
  """#
}

@MainActor
final class VideoResourceSheetViewController: UIViewController {
  var onDownload: ((DetectedMediaResource) -> Void)?
  var onDownloadAll: (([DetectedMediaResource]) -> Void)?
  var onPreview: ((DetectedMediaResource) -> Void)?

  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var resources: [DetectedMediaResource]

  init(resources: [DetectedMediaResource]) {
    self.resources = resources
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "检测到 \(resources.count) 个视频资源"
    view.backgroundColor = .systemGroupedBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "全部下载",
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        self.onDownloadAll?(self.resources)
      }
    )

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.backgroundColor = .clear
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = 104
    tableView.accessibilityIdentifier = "browser.detectedResources"
    view.addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func contextMenu(for resource: DetectedMediaResource) -> UIMenu {
    UIMenu(children: [
      UIAction(
        title: "在线播放",
        image: UIImage(systemName: "play.circle")
      ) { [weak self] _ in self?.onPreview?(resource) },
      UIAction(
        title: "复制链接",
        image: UIImage(systemName: "doc.on.doc")
      ) { _ in UIPasteboard.general.url = resource.url },
      UIAction(
        title: "分享",
        image: UIImage(systemName: "square.and.arrow.up")
      ) { [weak self] _ in
        let controller = UIActivityViewController(
          activityItems: [resource.url],
          applicationActivities: nil
        )
        self?.present(controller, animated: true)
      },
      UIAction(
        title: "下载",
        image: UIImage(systemName: "arrow.down.circle")
      ) { [weak self] _ in self?.onDownload?(resource) },
    ])
  }
}

extension VideoResourceSheetViewController:
  UITableViewDataSource,
  UITableViewDelegate
{
  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    resources.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let identifier = "DetectedMediaCell"
    let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
    let resource = resources[indexPath.row]
    var content = cell.defaultContentConfiguration()
    content.text = resource.title
    content.textProperties.numberOfLines = 2
    content.secondaryText = metadataText(for: resource)
    content.secondaryTextProperties.color = .secondaryLabel
    content.image = UIImage(systemName: resource.isHLS
      ? "dot.radiowaves.left.and.right"
      : "play.rectangle.fill")
    content.imageProperties.tintColor = .systemBlue
    cell.contentConfiguration = content

    var buttonConfiguration = UIButton.Configuration.tinted()
    buttonConfiguration.image = UIImage(systemName: "arrow.down")
    buttonConfiguration.cornerStyle = .capsule
    let button = UIButton(configuration: buttonConfiguration)
    button.accessibilityLabel = "下载 \(resource.quality)"
    button.addAction(UIAction { [weak self] _ in
      self?.onDownload?(resource)
    }, for: .touchUpInside)
    cell.accessoryView = button
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onPreview?(resources[indexPath.row])
  }

  func tableView(
    _ tableView: UITableView,
    contextMenuConfigurationForRowAt indexPath: IndexPath,
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    let resource = resources[indexPath.row]
    return UIContextMenuConfiguration(
      identifier: resource.id.uuidString as NSString,
      previewProvider: nil
    ) { [weak self] _ in
      self?.contextMenu(for: resource)
    }
  }

  private func metadataText(for resource: DetectedMediaResource) -> String {
    var values = [resource.quality, resource.format]
    if resource.expectedSize > 0 {
      values.append(ByteCountFormatter.string(
        fromByteCount: resource.expectedSize,
        countStyle: .file
      ))
    } else {
      values.append("大小未知")
    }
    if resource.bitrate > 0 {
      values.append("\(resource.bitrate / 1_000) kbps")
    }
    if let duration = resource.duration, duration.isFinite, duration > 0 {
      let formatter = DateComponentsFormatter()
      formatter.allowedUnits = duration >= 3600
        ? [.hour, .minute, .second]
        : [.minute, .second]
      formatter.zeroFormattingBehavior = .pad
      values.append(formatter.string(from: duration) ?? "")
    }
    return values.filter { !$0.isEmpty }.joined(separator: " · ")
  }
}
