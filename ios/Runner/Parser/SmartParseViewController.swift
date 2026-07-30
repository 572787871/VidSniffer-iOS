import UIKit

struct ParsedMedia: Hashable {
  let url: URL
  let title: String

  var format: String {
    url.pathExtension.isEmpty
      ? "媒体"
      : url.pathExtension.uppercased()
  }
}

actor SmartMediaParser {
  private let mediaExtensions = ["m3u8", "mp4", "m4v", "mov", "webm"]

  func parse(_ pageURL: URL) async throws -> [ParsedMedia] {
    if mediaExtensions.contains(pageURL.pathExtension.lowercased()) {
      return [ParsedMedia(
        url: pageURL,
        title: pageURL.deletingPathExtension().lastPathComponent
      )]
    }

    var request = URLRequest(url: pageURL)
    request.timeoutInterval = 20
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue(
      "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      forHTTPHeaderField: "Accept"
    )
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse,
          (200..<400).contains(http.statusCode)
    else {
      throw URLError(.badServerResponse)
    }
    let html = String(decoding: data, as: UTF8.self)
      .replacingOccurrences(of: "\\/", with: "/")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "\\u0026", with: "&")
    let title = pageTitle(in: html) ?? pageURL.host ?? "视频"
    return candidates(in: html, relativeTo: pageURL).map {
      ParsedMedia(url: $0, title: title)
    }
  }

  private func candidates(in html: String, relativeTo pageURL: URL) -> [URL] {
    let pattern =
      #"(?:https?:)?(?:\\?/)?[^"'<>\s]+?\.(?:m3u8|mp4|m4v|mov|webm)(?:\?[^"'<>\s]*)?"#
    guard let expression = try? NSRegularExpression(
      pattern: pattern,
      options: [.caseInsensitive]
    ) else {
      return []
    }
    let range = NSRange(html.startIndex..., in: html)
    var seen = Set<String>()
    return expression.matches(in: html, range: range).compactMap { match in
      guard let valueRange = Range(match.range, in: html) else { return nil }
      var value = String(html[valueRange])
        .replacingOccurrences(of: "\\", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      if value.hasPrefix("//") {
        value = "\(pageURL.scheme ?? "https"):\(value)"
      }
      guard let url = URL(string: value, relativeTo: pageURL)?.absoluteURL,
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            seen.insert(url.absoluteString).inserted
      else {
        return nil
      }
      return url
    }
  }

  private func pageTitle(in html: String) -> String? {
    guard let expression = try? NSRegularExpression(
      pattern: #"<title[^>]*>(.*?)</title>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators]
    ),
    let match = expression.firstMatch(
      in: html,
      range: NSRange(html.startIndex..., in: html)
    ),
    let range = Range(match.range(at: 1), in: html)
    else {
      return nil
    }
    return String(html[range])
      .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

@MainActor
final class SmartParseViewController: UIViewController {
  private let parser = SmartMediaParser()
  private let input = UITextField()
  private let parseButton = UIButton(type: .system)
  private let activity = UIActivityIndicatorView(style: .medium)
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let stateLabel = UILabel()
  private var results: [ParsedMedia] = []
  private var parseTask: Task<Void, Never>?

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "智能解析"
    navigationItem.largeTitleDisplayMode = .always
    view.backgroundColor = .systemGroupedBackground
    configureView()
  }

  deinit {
    parseTask?.cancel()
  }

  private func configureView() {
    let card = UIVisualEffectView(
      effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    card.translatesAutoresizingMaskIntoConstraints = false
    card.layer.cornerRadius = 20
    card.layer.cornerCurve = .continuous
    card.clipsToBounds = true

    input.translatesAutoresizingMaskIntoConstraints = false
    input.placeholder = "粘贴网页或媒体网址"
    input.keyboardType = .URL
    input.autocapitalizationType = .none
    input.autocorrectionType = .no
    input.returnKeyType = .search
    input.clearButtonMode = .whileEditing
    input.accessibilityIdentifier = "parser.urlField"
    input.addAction(UIAction { [weak self] _ in self?.startParsing() },
                    for: .editingDidEndOnExit)

    var configuration = UIButton.Configuration.filled()
    configuration.title = "解析"
    configuration.image = UIImage(systemName: "sparkles")
    configuration.imagePadding = 6
    configuration.cornerStyle = .capsule
    parseButton.configuration = configuration
    parseButton.translatesAutoresizingMaskIntoConstraints = false
    parseButton.accessibilityIdentifier = "parser.parseButton"
    parseButton.addAction(UIAction { [weak self] _ in
      self?.startParsing()
    }, for: .touchUpInside)

    activity.translatesAutoresizingMaskIntoConstraints = false
    activity.hidesWhenStopped = true

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.backgroundColor = .clear
    tableView.keyboardDismissMode = .interactive

    stateLabel.translatesAutoresizingMaskIntoConstraints = false
    stateLabel.text = "粘贴链接后解析可下载媒体"
    stateLabel.textColor = .secondaryLabel
    stateLabel.font = .preferredFont(forTextStyle: .body)
    stateLabel.textAlignment = .center
    stateLabel.numberOfLines = 0

    view.addSubview(card)
    card.contentView.addSubview(input)
    card.contentView.addSubview(parseButton)
    card.contentView.addSubview(activity)
    view.addSubview(tableView)
    view.addSubview(stateLabel)

    NSLayoutConstraint.activate([
      card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      card.heightAnchor.constraint(equalToConstant: 66),
      input.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
      input.centerYAnchor.constraint(equalTo: card.contentView.centerYAnchor),
      input.trailingAnchor.constraint(equalTo: parseButton.leadingAnchor, constant: -10),
      parseButton.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -10),
      parseButton.centerYAnchor.constraint(equalTo: card.contentView.centerYAnchor),
      activity.centerXAnchor.constraint(equalTo: parseButton.centerXAnchor),
      activity.centerYAnchor.constraint(equalTo: parseButton.centerYAnchor),
      tableView.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
      stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30),
    ])
  }

  private func startParsing() {
    guard let raw = input.text,
          let url = BrowserURLResolver.resolve(raw)
    else {
      showMessage("请输入有效的网址")
      return
    }
    view.endEditing(true)
    parseTask?.cancel()
    results = []
    tableView.reloadData()
    stateLabel.text = "正在分析网页…"
    stateLabel.isHidden = false
    parseButton.configuration?.title = nil
    parseButton.configuration?.image = nil
    parseButton.isEnabled = false
    activity.startAnimating()

    parseTask = Task { [weak self] in
      guard let self else { return }
      do {
        let values = try await parser.parse(url)
        guard !Task.isCancelled else { return }
        results = values
        tableView.reloadData()
        stateLabel.text = values.isEmpty
          ? "当前页面未发现可直接下载的媒体"
          : nil
        stateLabel.isHidden = !values.isEmpty
      } catch {
        guard !Task.isCancelled else { return }
        stateLabel.text = "解析失败，请检查网络或在浏览器中打开网页"
        stateLabel.isHidden = false
      }
      finishLoading()
    }
  }

  private func finishLoading() {
    activity.stopAnimating()
    parseButton.configuration?.title = "解析"
    parseButton.configuration?.image = UIImage(systemName: "sparkles")
    parseButton.isEnabled = true
  }

  private func showMessage(_ message: String) {
    let alert = UIAlertController(title: "无法解析", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  private func download(_ media: ParsedMedia) {
    let fallback = media.url.deletingPathExtension().lastPathComponent
    let name = fallback.isEmpty ? media.title : fallback
    let ext = media.url.pathExtension.isEmpty ? "mp4" : media.url.pathExtension
    Task {
      _ = await DownloadManager.shared.enqueue(
        url: media.url,
        filename: "\(DownloadDestinationManager.sanitizedFilename(name)).\(ext)"
      )
      tabBarController?.selectedIndex = 2
    }
  }
}

extension SmartParseViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    results.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let identifier = "ParsedMediaCell"
    let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
    let item = results[indexPath.row]
    cell.textLabel?.text = item.title
    cell.textLabel?.numberOfLines = 2
    cell.detailTextLabel?.text = "\(item.format) · \(item.url.host ?? "")"
    cell.detailTextLabel?.textColor = .secondaryLabel
    cell.imageView?.image = UIImage(systemName: "play.rectangle.fill")
    cell.imageView?.tintColor = .systemBlue
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    download(results[indexPath.row])
  }
}
