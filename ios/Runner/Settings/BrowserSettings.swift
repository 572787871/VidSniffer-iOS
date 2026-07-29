import Foundation

enum BrowserAppearance: String, Codable, CaseIterable {
  case system
  case light
  case dark

  var title: String {
    switch self {
    case .system: return "跟随系统"
    case .light: return "浅色"
    case .dark: return "深色"
    }
  }
}

struct BrowserSettings: Codable, Equatable {
  var searchEngine: BrowserSearchEngine = .google
  var restoresTabs = true
  var requestsDesktopSite = false
  var pullToRefresh = true
  var appearance: BrowserAppearance = .system
  var contentBlockingEnabled = true
  var blocksAds = true
  var blocksTrackers = true
  var blocksPopups = true
  var preventsCrossSiteTracking = true
  var contentBlockerWhitelist: [String] = []
}

extension BrowserSearchEngine: Codable {
  var title: String {
    switch self {
    case .google: return "Google"
    case .bing: return "Bing"
    case .duckDuckGo: return "DuckDuckGo"
    case .baidu: return "百度"
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = BrowserSearchEngine(rawValue: rawValue) ?? .google
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension Notification.Name {
  static let browserSettingsDidChange =
    Notification.Name("BrowserSettingsDidChange")
}

final class BrowserSettingsStore {
  static let shared = BrowserSettingsStore()

  private let defaults: UserDefaults
  private let key = "browser.settings.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var value: BrowserSettings {
    get {
      guard let data = defaults.data(forKey: key),
            let value = try? JSONDecoder().decode(
              BrowserSettings.self,
              from: data
            )
      else {
        return BrowserSettings()
      }
      return value
    }
    set {
      guard let data = try? JSONEncoder().encode(newValue) else { return }
      defaults.set(data, forKey: key)
      NotificationCenter.default.post(
        name: .browserSettingsDidChange,
        object: self
      )
    }
  }

  func isWhitelisted(host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return value.contentBlockerWhitelist.contains {
      host == $0.lowercased() || host.hasSuffix(".\($0.lowercased())")
    }
  }
}
