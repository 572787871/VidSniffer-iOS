import Foundation
import WebKit

@MainActor
final class ContentBlockerManager {
  static let shared = ContentBlockerManager()

  private let identifier = "VidSniffer.ContentBlocker.v2"
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
          "if-domain": [
            "*doubleclick.net",
            "*googlesyndication.com",
            "*googleadservices.com",
            "*adservice.google.com",
            "*adnxs.com",
            "*adsrvr.org",
            "*adsterra.com",
            "*exoclick.com",
            "*exosrv.com",
            "*juicyads.com",
            "*popads.net",
            "*popcash.net",
            "*propellerads.com",
            "*trafficjunky.com",
            "*tsyndicate.com",
          ],
        ],
        "action": ["type": "block"],
      ])
      rules.append([
        "trigger": ["url-filter": ".*"],
        "action": [
          "type": "css-display-none",
          "selector": [
            ".adsbygoogle",
            ".xqbj-component-adfloat",
            "[data-ad]",
            "[data-ad-id]",
            "[data-ad_type]",
            "[data-event='ad_click']",
            "[data-page_name*='广告']",
            "[id^='ad-card-']",
            "iframe[src*='doubleclick']",
            "iframe[src*='googlesyndication']",
            "iframe[src*='adservice']",
            "iframe[id^='ad_']",
            "iframe[class*=' ad-']",
          ].joined(separator: ","),
        ],
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
