import Foundation

actor DownloadRepository {
  private struct Envelope: Codable {
    var schemaVersion = 1
    var tasks: [DownloadTaskModel] = []
    var preferences = DownloadPreferences()
  }

  static let shared = DownloadRepository()

  private let fileManager: FileManager
  private let fileURL: URL
  private var cachedEnvelope: Envelope?

  init(
    fileManager: FileManager = .default,
    fileURL: URL? = nil
  ) {
    self.fileManager = fileManager
    let supportDirectory = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    self.fileURL = fileURL
      ?? supportDirectory.appendingPathComponent("downloads/tasks.json")
  }

  func tasks() throws -> [DownloadTaskModel] {
    try load().tasks.sorted { $0.createdAt > $1.createdAt }
  }

  func task(id: UUID) throws -> DownloadTaskModel? {
    try load().tasks.first { $0.id == id }
  }

  func upsert(_ task: DownloadTaskModel) throws {
    var envelope = try load()
    if let index = envelope.tasks.firstIndex(where: { $0.id == task.id }) {
      envelope.tasks[index] = task
    } else {
      envelope.tasks.append(task)
    }
    try save(envelope)
  }

  func remove(id: UUID) throws {
    var envelope = try load()
    envelope.tasks.removeAll { $0.id == id }
    try save(envelope)
  }

  func preferences() throws -> DownloadPreferences {
    try load().preferences
  }

  func savePreferences(_ preferences: DownloadPreferences) throws {
    var envelope = try load()
    envelope.preferences = preferences
    try save(envelope)
  }

  private func load() throws -> Envelope {
    if let cachedEnvelope {
      return cachedEnvelope
    }
    guard fileManager.fileExists(atPath: fileURL.path) else {
      let envelope = Envelope()
      cachedEnvelope = envelope
      return envelope
    }
    let data = try Data(contentsOf: fileURL)
    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
    cachedEnvelope = envelope
    return envelope
  }

  private func save(_ envelope: Envelope) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(envelope)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    cachedEnvelope = envelope
  }
}
