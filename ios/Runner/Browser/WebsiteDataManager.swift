import Foundation
import WebKit

@MainActor
final class WebsiteDataManager {
  static let shared = WebsiteDataManager()

  private init() {}

  func records(
    dataTypes: Set<String>? = nil
  ) async -> [WKWebsiteDataRecord] {
    let types = dataTypes ?? WKWebsiteDataStore.allWebsiteDataTypes()
    return await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().fetchDataRecords(
        ofTypes: types
      ) { records in
        continuation.resume(returning: records)
      }
    }
  }

  func remove(
    records: [WKWebsiteDataRecord],
    dataTypes: Set<String>? = nil
  ) async {
    let types = dataTypes ?? WKWebsiteDataStore.allWebsiteDataTypes()
    await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().removeData(
        ofTypes: types,
        for: records
      ) {
        continuation.resume()
      }
    }
  }

  func removeAll(
    since date: Date,
    dataTypes: Set<String>? = nil
  ) async {
    let types = dataTypes ?? WKWebsiteDataStore.allWebsiteDataTypes()
    await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().removeData(
        ofTypes: types,
        modifiedSince: date
      ) {
        continuation.resume()
      }
    }
  }
}
