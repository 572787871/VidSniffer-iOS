import Foundation
import WebKit

@MainActor
final class ContentBlockerManager {
  static let shared = ContentBlockerManager()

  private let identifier = "VidSniffer.BasicContentBlocker.v1"
  private var cachedRuleList: WKContentRuleList?
  private var compilationTask: Task<WKContentRuleList?, Never>?

  private init() {}

  func apply(to webView: WKWebView, for host: String? = nil) async {
    webView.configuration.userContentController.removeAllContentRuleLists()
    let settings = BrowserSettingsStore.shared.value
    guard settings.contentBlockingEnabled,
          !BrowserSettingsStore.shared.isWhitelisted(host: host),
          let ruleList = await ruleList(for: settings)
    else {
      return
    }
    webView.configuration.userContentController.add(ruleList)
  }

  func invalidate() {
    cachedRuleList = nil
    compilationTask?.cancel()
    compilationTask = nil
    WKContentRuleListStore.default().removeContentRuleList(
      forIdentifier: identifier
    ) { _ in }
  }

  private func ruleList(
    for settings: BrowserSettings
  ) async -> WKContentRuleList? {
    if let cachedRuleList {
      return cachedRuleList
    }
    if let compilationTask {
      return await compilationTask.value
    }
    let json = Self.rulesJSON(settings: settings)
    let task = Task<WKContentRuleList?, Never> {
      await withCheckedContinuation { continuation in
        WKContentRuleListStore.default().compileContentRuleList(
          forIdentifier: identifier,
          encodedContentRuleList: json
        ) { list, _ in
          continuation.resume(returning: list)
        }
      }
    }
    compilationTask = task
    let list = await task.value
    cachedRuleList = list
    compilationTask = nil
    return list
  }

  nonisolated static func rulesJSON(
    settings: BrowserSettings
  ) -> String {
    var rules: [[String: Any]] = []
    if settings.blocksAds {
      rules.append([
        "trigger": [
          "url-filter": ".*",
          "resource-type": ["image", "style-sheet", "script", "font"],
          "if-domain": [
            "*doubleclick.net",
            "*googlesyndication.com",
            "*googleadservices.com",
            "*adservice.google.com",
          ],
        ],
        "action": ["type": "block"],
      ])
    }
    if settings.blocksTrackers || settings.preventsCrossSiteTracking {
      rules.append([
        "trigger": [
          "url-filter": ".*",
          "resource-type": ["script", "raw"],
          "if-domain": [
            "*google-analytics.com",
            "*googletagmanager.com",
            "*facebook.net",
          ],
        ],
        "action": ["type": "block"],
      ])
    }
    let data = try? JSONSerialization.data(
      withJSONObject: rules,
      options: [.sortedKeys]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
  }
}
