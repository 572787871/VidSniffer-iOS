import Foundation
import os

enum AppLogCategory: String, CaseIterable {
  case browser
  case navigation
  case download
  case storage
  case player
  case database
  case privacy
  case performance
}

enum AppLogger {
  private static let subsystem =
    Bundle.main.bundleIdentifier ?? "com.vidsniffer.pro"

  static func debug(
    _ message: String,
    category: AppLogCategory
  ) {
    #if DEBUG
    logger(for: category).debug("\(message, privacy: .public)")
    #endif
  }

  static func info(
    _ message: String,
    category: AppLogCategory
  ) {
    logger(for: category).info("\(message, privacy: .public)")
  }

  static func error(
    _ message: String,
    category: AppLogCategory
  ) {
    logger(for: category).error("\(message, privacy: .public)")
  }

  static func sanitizedURLDescription(_ url: URL?) -> String {
    guard let url else { return "无网址" }
    var components = URLComponents()
    components.scheme = url.scheme
    components.host = url.host
    components.port = url.port
    components.path = url.path
    return components.string ?? url.host ?? "未知网站"
  }

  private static func logger(for category: AppLogCategory) -> Logger {
    Logger(subsystem: subsystem, category: category.rawValue)
  }
}
