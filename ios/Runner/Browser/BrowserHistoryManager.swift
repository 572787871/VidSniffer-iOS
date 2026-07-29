import Foundation

struct BrowserHistoryEntry: Codable, Identifiable, Equatable {
  let id: UUID
  var title: String
  var url: URL
  var visitedAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    url: URL,
    visitedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.visitedAt = visitedAt
  }
}

enum BrowserHistoryPeriod: String, CaseIterable {
  case today = "今天"
  case yesterday = "昨天"
  case lastSevenDays = "最近七天"
  case earlier = "更早"
}

actor BrowserHistoryManager {
  private let repository: BrowserDataRepository
  private let calendar: Calendar

  init(
    repository: BrowserDataRepository = .shared,
    calendar: Calendar = .current
  ) {
    self.repository = repository
    self.calendar = calendar
  }

  func load() async throws -> [BrowserHistoryEntry] {
    try await repository.history()
  }

  func add(
    title: String,
    url: URL,
    isPrivate: Bool
  ) async throws {
    guard !isPrivate else { return }
    try await repository.addHistory(title: title, url: url)
  }

  func search(_ query: String) async throws -> [BrowserHistoryEntry] {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let entries = try await repository.history()
    guard !value.isEmpty else { return entries }
    return entries.filter {
      $0.title.localizedCaseInsensitiveContains(value)
        || $0.url.absoluteString.localizedCaseInsensitiveContains(value)
    }
  }

  func grouped(
    entries: [BrowserHistoryEntry]? = nil,
    now: Date = Date()
  ) async throws -> [(BrowserHistoryPeriod, [BrowserHistoryEntry])] {
    let values: [BrowserHistoryEntry]
    if let entries {
      values = entries
    } else {
      values = try await repository.history()
    }
    let startOfToday = calendar.startOfDay(for: now)
    let startOfYesterday = calendar.date(
      byAdding: .day,
      value: -1,
      to: startOfToday
    )!
    let startOfSevenDays = calendar.date(
      byAdding: .day,
      value: -7,
      to: startOfToday
    )!

    var result: [BrowserHistoryPeriod: [BrowserHistoryEntry]] = [:]
    for entry in values {
      let period: BrowserHistoryPeriod
      if entry.visitedAt >= startOfToday {
        period = .today
      } else if entry.visitedAt >= startOfYesterday {
        period = .yesterday
      } else if entry.visitedAt >= startOfSevenDays {
        period = .lastSevenDays
      } else {
        period = .earlier
      }
      result[period, default: []].append(entry)
    }
    return BrowserHistoryPeriod.allCases.compactMap { period in
      guard let entries = result[period], !entries.isEmpty else { return nil }
      return (period, entries)
    }
  }

  func remove(id: UUID) async throws {
    try await repository.removeHistory(id: id)
  }

  func clear(
    from startDate: Date? = nil,
    through endDate: Date? = nil
  ) async throws {
    try await repository.clearHistory(
      from: startDate,
      through: endDate
    )
  }
}
