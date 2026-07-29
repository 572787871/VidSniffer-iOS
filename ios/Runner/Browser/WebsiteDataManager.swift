import Foundation
import WebKit

final class WebsiteDataManager {
  static let shared = WebsiteDataManager()

  private init() {}

  func records(
    dataTypes: Set<String> = WKWebsiteDataStore.allWebsiteDataTypes()
  ) async -> [WKWebsiteDataRecord] {
    await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().fetchDataRecords(
        ofTypes: dataTypes
      ) { records in
        continuation.resume(returning: records)
      }
    }
  }

  func remove(
    records: [WKWebsiteDataRecord],
    dataTypes: Set<String> = WKWebsiteDataStore.allWebsiteDataTypes()
  ) async {
    await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().removeData(
        ofTypes: dataTypes,
        for: records
      ) {
        continuation.resume()
      }
    }
  }

  func removeAll(
    since date: Date,
    dataTypes: Set<String> = WKWebsiteDataStore.allWebsiteDataTypes()
  ) async {
    await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().removeData(
        ofTypes: dataTypes,
        modifiedSince: date
      ) {
        continuation.resume()
      }
    }
  }
}
