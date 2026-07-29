import Foundation
import UIKit
import UniformTypeIdentifiers

struct Bookmark: Codable, Identifiable, Equatable {
  let id: UUID
  var title: String
  var url: URL
  var folderID: UUID?
  var order: Int
  var createdAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    url: URL,
    folderID: UUID? = nil,
    order: Int = 0,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.folderID = folderID
    self.order = order
    self.createdAt = createdAt
  }
}

struct BookmarkFolder: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var order: Int
  var createdAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    order: Int = 0,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.order = order
    self.createdAt = createdAt
  }
}

private struct BrowserDataEnvelope: Codable {
  var schemaVersion = 1
  var bookmarks: [Bookmark] = []
  var bookmarkFolders: [BookmarkFolder] = []
  var history: [BrowserHistoryEntry] = []
}

actor BrowserDataRepository {
  static let shared = BrowserDataRepository()

  private let fileURL: URL
  private let fileManager: FileManager
  private var cachedEnvelope: BrowserDataEnvelope?

  init(
    fileManager: FileManager = .default,
    fileURL: URL? = nil
  ) {
    self.fileManager = fileManager
    let support = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    self.fileURL = fileURL
      ?? support.appendingPathComponent("browser-data.json")
  }

  func bookmarks() throws -> [Bookmark] {
    try load().bookmarks.sorted { $0.order < $1.order }
  }

  func folders() throws -> [BookmarkFolder] {
    try load().bookmarkFolders.sorted { $0.order < $1.order }
  }

  func addBookmark(
    title: String,
    url: URL,
    folderID: UUID?
  ) throws -> Bookmark {
    var envelope = try load()
    if let existing = envelope.bookmarks.first(where: { $0.url == url }) {
      return existing
    }
    let order = envelope.bookmarks
      .filter { $0.folderID == folderID }
      .count
    let bookmark = Bookmark(
      title: title,
      url: url,
      folderID: folderID,
      order: order
    )
    envelope.bookmarks.append(bookmark)
    try save(envelope)
    return bookmark
  }

  func updateBookmark(_ bookmark: Bookmark) throws {
    var envelope = try load()
    guard let index = envelope.bookmarks.firstIndex(where: {
      $0.id == bookmark.id
    }) else {
      return
    }
    envelope.bookmarks[index] = bookmark
    normalizeBookmarks(&envelope.bookmarks)
    try save(envelope)
  }

  func removeBookmark(id: UUID) throws {
    var envelope = try load()
    envelope.bookmarks.removeAll { $0.id == id }
    normalizeBookmarks(&envelope.bookmarks)
    try save(envelope)
  }

  func moveBookmarks(
    fromOffsets: IndexSet,
    toOffset: Int,
    folderID: UUID?
  ) throws {
    var envelope = try load()
    var scoped = envelope.bookmarks
      .filter { $0.folderID == folderID }
      .sorted { $0.order < $1.order }
    let moving = fromOffsets.compactMap {
      scoped.indices.contains($0) ? scoped[$0] : nil
    }
    for index in fromOffsets.sorted(by: >) where scoped.indices.contains(index) {
      scoped.remove(at: index)
    }
    scoped.insert(
      contentsOf: moving,
      at: min(max(0, toOffset), scoped.count)
    )
    for (order, bookmark) in scoped.enumerated() {
      if let index = envelope.bookmarks.firstIndex(where: {
        $0.id == bookmark.id
      }) {
        envelope.bookmarks[index].order = order
      }
    }
    try save(envelope)
  }

  func addFolder(name: String) throws -> BookmarkFolder {
    var envelope = try load()
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let folder = BookmarkFolder(
      name: cleanName.isEmpty ? "新建文件夹" : cleanName,
      order: envelope.bookmarkFolders.count
    )
    envelope.bookmarkFolders.append(folder)
    try save(envelope)
    return folder
  }

  func updateFolder(_ folder: BookmarkFolder) throws {
    var envelope = try load()
    guard let index = envelope.bookmarkFolders.firstIndex(where: {
      $0.id == folder.id
    }) else {
      return
    }
    envelope.bookmarkFolders[index] = folder
    try save(envelope)
  }

  func moveFolders(fromOffsets: IndexSet, toOffset: Int) throws {
    var envelope = try load()
    var folders = envelope.bookmarkFolders.sorted { $0.order < $1.order }
    let moving = fromOffsets.compactMap {
      folders.indices.contains($0) ? folders[$0] : nil
    }
    for index in fromOffsets.sorted(by: >) where folders.indices.contains(index) {
      folders.remove(at: index)
    }
    folders.insert(
      contentsOf: moving,
      at: min(max(0, toOffset), folders.count)
    )
    for (order, folder) in folders.enumerated() {
      if let index = envelope.bookmarkFolders.firstIndex(where: {
        $0.id == folder.id
      }) {
        envelope.bookmarkFolders[index].order = order
      }
    }
    try save(envelope)
  }

  func removeFolder(id: UUID, deleteBookmarks: Bool) throws {
    var envelope = try load()
    envelope.bookmarkFolders.removeAll { $0.id == id }
    if deleteBookmarks {
      envelope.bookmarks.removeAll { $0.folderID == id }
    } else {
      for index in envelope.bookmarks.indices
      where envelope.bookmarks[index].folderID == id {
        envelope.bookmarks[index].folderID = nil
      }
    }
    normalizeBookmarks(&envelope.bookmarks)
    try save(envelope)
  }

  func history() throws -> [BrowserHistoryEntry] {
    try load().history.sorted { $0.visitedAt > $1.visitedAt }
  }

  func addHistory(title: String, url: URL) throws {
    var envelope = try load()
    if let first = envelope.history.first,
       first.url == url,
       Date().timeIntervalSince(first.visitedAt) < 30 {
      envelope.history[0].title = title
      envelope.history[0].visitedAt = Date()
    } else {
      envelope.history.insert(
        BrowserHistoryEntry(title: title, url: url),
        at: 0
      )
    }
    if envelope.history.count > 10_000 {
      envelope.history = Array(envelope.history.prefix(10_000))
    }
    try save(envelope)
  }

  func removeHistory(id: UUID) throws {
    var envelope = try load()
    envelope.history.removeAll { $0.id == id }
    try save(envelope)
  }

  func clearHistory(from startDate: Date?, through endDate: Date?) throws {
    var envelope = try load()
    if startDate == nil, endDate == nil {
      envelope.history.removeAll()
    } else {
      envelope.history.removeAll { entry in
        let isAfterStart = startDate.map { entry.visitedAt >= $0 } ?? true
        let isBeforeEnd = endDate.map { entry.visitedAt <= $0 } ?? true
        return isAfterStart && isBeforeEnd
      }
    }
    try save(envelope)
  }

  func exportBookmarks() throws -> Data {
    try JSONEncoder().encode(try bookmarks())
  }

  func importBookmarks(_ data: Data) throws {
    var envelope = try load()
    let imported = try JSONDecoder().decode([Bookmark].self, from: data)
    var knownIDs = Set(envelope.bookmarks.map(\.id))
    var knownURLs = Set(envelope.bookmarks.map(\.url))
    for bookmark in imported
    where !knownIDs.contains(bookmark.id) && !knownURLs.contains(bookmark.url) {
      envelope.bookmarks.append(bookmark)
      knownIDs.insert(bookmark.id)
      knownURLs.insert(bookmark.url)
    }
    normalizeBookmarks(&envelope.bookmarks)
    try save(envelope)
  }

  private func load() throws -> BrowserDataEnvelope {
    if let cachedEnvelope {
      return cachedEnvelope
    }
    if fileManager.fileExists(atPath: fileURL.path) {
      let envelope = try JSONDecoder().decode(
        BrowserDataEnvelope.self,
        from: Data(contentsOf: fileURL)
      )
      cachedEnvelope = envelope
      return envelope
    }

    let migrated = try migrateLegacyData()
    cachedEnvelope = migrated
    if !migrated.bookmarks.isEmpty || !migrated.history.isEmpty {
      try persist(migrated)
    }
    return migrated
  }

  private func save(_ envelope: BrowserDataEnvelope) throws {
    cachedEnvelope = envelope
    try persist(envelope)
  }

  private func persist(_ envelope: BrowserDataEnvelope) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder()
      .encode(envelope)
      .write(to: fileURL, options: [.atomic, .completeFileProtection])
  }

  private func migrateLegacyData() throws -> BrowserDataEnvelope {
    let directory = fileURL.deletingLastPathComponent()
    let bookmarkURL = directory.appendingPathComponent("bookmarks.json")
    let historyURL = directory.appendingPathComponent("browser-history.json")
    var envelope = BrowserDataEnvelope()

    if fileManager.fileExists(atPath: bookmarkURL.path),
       let data = try? Data(contentsOf: bookmarkURL),
       let values = try? JSONDecoder().decode([Bookmark].self, from: data) {
      envelope.bookmarks = values
      try? fileManager.removeItem(at: bookmarkURL)
    }
    if fileManager.fileExists(atPath: historyURL.path),
       let data = try? Data(contentsOf: historyURL),
       let values = try? JSONDecoder().decode(
         [BrowserHistoryEntry].self,
         from: data
       ) {
      envelope.history = values
      try? fileManager.removeItem(at: historyURL)
    }
    return envelope
  }

  private func normalizeBookmarks(_ bookmarks: inout [Bookmark]) {
    let folderIDs = Set(bookmarks.map(\.folderID))
    for folderID in folderIDs {
      let indices = bookmarks.indices
        .filter { bookmarks[$0].folderID == folderID }
        .sorted { bookmarks[$0].order < bookmarks[$1].order }
      for (order, index) in indices.enumerated() {
        bookmarks[index].order = order
      }
    }
  }
}

actor BookmarkManager {
  private let repository: BrowserDataRepository

  init(repository: BrowserDataRepository = .shared) {
    self.repository = repository
  }

  func load() async throws -> [Bookmark] {
    try await repository.bookmarks()
  }

  func folders() async throws -> [BookmarkFolder] {
    try await repository.folders()
  }

  func search(_ query: String, folderID: UUID? = nil) async throws -> [Bookmark] {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await repository.bookmarks().filter {
      (folderID == nil || $0.folderID == folderID)
        && (value.isEmpty
          || $0.title.localizedCaseInsensitiveContains(value)
          || $0.url.absoluteString.localizedCaseInsensitiveContains(value))
    }
  }

  @discardableResult
  func add(
    title: String,
    url: URL,
    folderID: UUID? = nil
  ) async throws -> Bookmark {
    try await repository.addBookmark(
      title: title,
      url: url,
      folderID: folderID
    )
  }

  func update(_ bookmark: Bookmark) async throws {
    try await repository.updateBookmark(bookmark)
  }

  func remove(id: UUID) async throws {
    try await repository.removeBookmark(id: id)
  }

  func move(
    fromOffsets: IndexSet,
    toOffset: Int,
    folderID: UUID? = nil
  ) async throws {
    try await repository.moveBookmarks(
      fromOffsets: fromOffsets,
      toOffset: toOffset,
      folderID: folderID
    )
  }

  @discardableResult
  func addFolder(name: String) async throws -> BookmarkFolder {
    try await repository.addFolder(name: name)
  }

  func updateFolder(_ folder: BookmarkFolder) async throws {
    try await repository.updateFolder(folder)
  }

  func moveFolders(fromOffsets: IndexSet, toOffset: Int) async throws {
    try await repository.moveFolders(
      fromOffsets: fromOffsets,
      toOffset: toOffset
    )
  }

  func removeFolder(id: UUID, deleteBookmarks: Bool) async throws {
    try await repository.removeFolder(
      id: id,
      deleteBookmarks: deleteBookmarks
    )
  }

  func exportJSON() async throws -> Data {
    try await repository.exportBookmarks()
  }

  func importJSON(_ data: Data) async throws {
    try await repository.importBookmarks(data)
  }
}

@MainActor
final class BrowserLibraryViewController:
  UIViewController,
  UISearchResultsUpdating,
  UITableViewDataSource,
  UITableViewDelegate,
  UIDocumentPickerDelegate
{
  private enum Mode: Int {
    case bookmarks
    case history
  }

  private enum Row {
    case folder(BookmarkFolder, count: Int)
    case bookmark(Bookmark)
    case history(BrowserHistoryEntry)
  }

  private struct Section {
    let title: String?
    var rows: [Row]
  }

  var onOpenURL: ((URL, Bool) -> Void)?

  private let bookmarkManager: BookmarkManager
  private let historyManager: BrowserHistoryManager
  private let initialMode: Mode
  private let folderID: UUID?
  private let folderTitle: String?
  private let segmentedControl = UISegmentedControl(items: ["书签", "历史记录"])
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let emptyLabel = UILabel()
  private let searchController = UISearchController(searchResultsController: nil)
  private var sections: [Section] = []
  private var loadTask: Task<Void, Never>?
  private var temporaryExportURL: URL?

  init(
    bookmarkManager: BookmarkManager = BookmarkManager(),
    historyManager: BrowserHistoryManager = BrowserHistoryManager(),
    showHistory: Bool = false,
    folderID: UUID? = nil,
    folderTitle: String? = nil
  ) {
    self.bookmarkManager = bookmarkManager
    self.historyManager = historyManager
    initialMode = showHistory ? .history : .bookmarks
    self.folderID = folderID
    self.folderTitle = folderTitle
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    loadTask?.cancel()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    title = folderTitle ?? "浏览器资料"
    if folderID == nil {
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        systemItem: .close,
        primaryAction: UIAction { [weak self] _ in
          self?.dismiss(animated: true)
        }
      )
    }

    segmentedControl.translatesAutoresizingMaskIntoConstraints = false
    segmentedControl.selectedSegmentIndex = initialMode.rawValue
    segmentedControl.isHidden = folderID != nil
    segmentedControl.addTarget(
      self,
      action: #selector(modeChanged),
      for: .valueChanged
    )

    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "搜索标题或网址"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    navigationItem.rightBarButtonItem = makeMoreButton()

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = 68
    tableView.register(
      UITableViewCell.self,
      forCellReuseIdentifier: "BrowserLibraryCell"
    )

    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.text = "暂无内容"
    emptyLabel.font = .preferredFont(forTextStyle: .title3)
    emptyLabel.textColor = .tertiaryLabel
    emptyLabel.textAlignment = .center
    emptyLabel.isHidden = true

    view.addSubview(segmentedControl)
    view.addSubview(tableView)
    view.addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      segmentedControl.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 8
      ),
      segmentedControl.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: 20
      ),
      segmentedControl.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -20
      ),
      tableView.topAnchor.constraint(
        equalTo: folderID == nil
          ? segmentedControl.bottomAnchor
          : view.safeAreaLayoutGuide.topAnchor,
        constant: 8
      ),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
    ])
    reloadData()
  }

  private var mode: Mode {
    folderID == nil
      ? Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .bookmarks
      : .bookmarks
  }

  private func makeMoreButton() -> UIBarButtonItem {
    UIBarButtonItem(
      image: UIImage(systemName: "ellipsis.circle"),
      menu: UIMenu(children: [
        UIMenu(
          title: "书签",
          options: .displayInline,
          children: [
            UIAction(
              title: "新建文件夹",
              image: UIImage(systemName: "folder.badge.plus")
            ) { [weak self] _ in
              self?.promptForNewFolder()
            },
            UIAction(
              title: "调整顺序",
              image: UIImage(systemName: "arrow.up.arrow.down")
            ) { [weak self] _ in
              self?.toggleReordering()
            },
            UIAction(
              title: "导入书签",
              image: UIImage(systemName: "square.and.arrow.down")
            ) { [weak self] _ in
              self?.importBookmarks()
            },
            UIAction(
              title: "导出书签",
              image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self] _ in
              self?.exportBookmarks()
            },
          ]
        ),
        UIAction(
          title: "清除历史记录",
          image: UIImage(systemName: "clock.badge.xmark"),
          attributes: [.destructive]
        ) { [weak self] _ in
          self?.showClearHistoryOptions()
        },
      ])
    )
  }

  private func toggleReordering() {
    guard mode == .bookmarks, searchController.searchBar.text?.isEmpty != false
    else {
      showMessage(title: "无法调整顺序", message: "请先清空搜索内容并切换到书签。")
      return
    }
    tableView.setEditing(!tableView.isEditing, animated: true)
  }

  private func importBookmarks() {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.json],
      asCopy: true
    )
    picker.delegate = self
    present(picker, animated: true)
  }

  private func exportBookmarks() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let data = try await bookmarkManager.exportJSON()
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("BrowserExports", isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("bookmarks.json")
        try data.write(to: url, options: [.atomic])
        temporaryExportURL = url
        let share = UIActivityViewController(
          activityItems: [url],
          applicationActivities: nil
        )
        share.popoverPresentationController?.barButtonItem =
          navigationItem.rightBarButtonItem
        share.completionWithItemsHandler = { [weak self] _, _, _, _ in
          guard let exportURL = self?.temporaryExportURL else { return }
          try? FileManager.default.removeItem(at: exportURL)
          self?.temporaryExportURL = nil
        }
        present(share, animated: true)
      } catch {
        showMessage(title: "导出失败", message: "暂时无法生成书签文件，请稍后重试。")
      }
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        let data = try Data(contentsOf: url)
        try await bookmarkManager.importJSON(data)
        reloadData()
        showMessage(title: "导入完成", message: "书签已经合并到资料库。")
      } catch {
        showMessage(title: "无法导入", message: "请选择由本 App 导出的有效 JSON 文件。")
      }
    }
  }

  @objc private func modeChanged() {
    searchController.searchBar.text = ""
    reloadData()
  }

  func updateSearchResults(for searchController: UISearchController) {
    reloadData()
  }

  private func reloadData() {
    loadTask?.cancel()
    let query = searchController.searchBar.text ?? ""
    loadTask = Task { [weak self] in
      guard let self else { return }
      do {
        switch self.mode {
        case .bookmarks:
          let bookmarks = try await self.bookmarkManager.search(
            query,
            folderID: self.folderID
          )
          if let folderID = self.folderID {
            self.sections = [
              Section(
                title: nil,
                rows: bookmarks
                  .filter { $0.folderID == folderID }
                  .map(Row.bookmark)
              ),
            ]
          } else {
            let folders = try await self.bookmarkManager.folders()
            let folderRows = folders.map { folder in
              Row.folder(
                folder,
                count: bookmarks.filter { $0.folderID == folder.id }.count
              )
            }
            self.sections = [
              Section(title: "文件夹", rows: folderRows),
              Section(
                title: "书签",
                rows: bookmarks
                  .filter { $0.folderID == nil }
                  .map(Row.bookmark)
              ),
            ].filter { !$0.rows.isEmpty }
          }
        case .history:
          let entries = try await self.historyManager.search(query)
          self.sections = try await self.historyManager
            .grouped(entries: entries)
            .map { Section(title: $0.0.rawValue, rows: $0.1.map(Row.history)) }
        }
        guard !Task.isCancelled else { return }
        self.emptyLabel.isHidden = !self.sections.isEmpty
        self.tableView.reloadData()
      } catch {
        self.sections = []
        self.emptyLabel.text = "无法读取浏览器资料"
        self.emptyLabel.isHidden = false
        self.tableView.reloadData()
      }
    }
  }

  func numberOfSections(in tableView: UITableView) -> Int {
    sections.count
  }

  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    sections[section].rows.count
  }

  func tableView(
    _ tableView: UITableView,
    titleForHeaderInSection section: Int
  ) -> String? {
    sections[section].title
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(
      withIdentifier: "BrowserLibraryCell",
      for: indexPath
    )
    var configuration = cell.defaultContentConfiguration()
    configuration.textProperties.numberOfLines = 1
    configuration.secondaryTextProperties.numberOfLines = 1
    switch sections[indexPath.section].rows[indexPath.row] {
    case let .folder(folder, count):
      configuration.text = folder.name
      configuration.secondaryText = "\(count) 个书签"
      configuration.image = UIImage(systemName: "folder.fill")
      configuration.imageProperties.tintColor = .systemBlue
      cell.accessoryType = .disclosureIndicator
    case let .bookmark(bookmark):
      configuration.text = bookmark.title
      configuration.secondaryText = bookmark.url.host
        ?? bookmark.url.absoluteString
      configuration.image = UIImage(systemName: "bookmark.fill")
      configuration.imageProperties.tintColor = .systemBlue
      cell.accessoryType = .none
    case let .history(entry):
      configuration.text = entry.title
      configuration.secondaryText = entry.url.host ?? entry.url.absoluteString
      configuration.image = UIImage(systemName: "clock")
      configuration.imageProperties.tintColor = .secondaryLabel
      cell.accessoryType = .none
    }
    cell.contentConfiguration = configuration
    return cell
  }

  func tableView(
    _ tableView: UITableView,
    canMoveRowAt indexPath: IndexPath
  ) -> Bool {
    guard mode == .bookmarks,
          searchController.searchBar.text?.isEmpty != false
    else {
      return false
    }
    switch sections[indexPath.section].rows[indexPath.row] {
    case .folder, .bookmark:
      return true
    case .history:
      return false
    }
  }

  func tableView(
    _ tableView: UITableView,
    targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
    toProposedIndexPath proposedDestinationIndexPath: IndexPath
  ) -> IndexPath {
    sourceIndexPath.section == proposedDestinationIndexPath.section
      ? proposedDestinationIndexPath
      : sourceIndexPath
  }

  func tableView(
    _ tableView: UITableView,
    moveRowAt sourceIndexPath: IndexPath,
    to destinationIndexPath: IndexPath
  ) {
    guard sourceIndexPath.section == destinationIndexPath.section else {
      reloadData()
      return
    }
    let sourceRow = sections[sourceIndexPath.section].rows[sourceIndexPath.row]
    let destinationOffset = destinationIndexPath.row > sourceIndexPath.row
      ? destinationIndexPath.row + 1
      : destinationIndexPath.row
    let movedRow = sections[sourceIndexPath.section].rows.remove(
      at: sourceIndexPath.row
    )
    sections[sourceIndexPath.section].rows.insert(
      movedRow,
      at: destinationIndexPath.row
    )
    Task { [weak self] in
      guard let self else { return }
      switch sourceRow {
      case .folder:
        try? await bookmarkManager.moveFolders(
          fromOffsets: IndexSet(integer: sourceIndexPath.row),
          toOffset: destinationOffset
        )
      case .bookmark:
        try? await bookmarkManager.move(
          fromOffsets: IndexSet(integer: sourceIndexPath.row),
          toOffset: destinationOffset,
          folderID: folderID
        )
      case .history:
        break
      }
      reloadData()
    }
  }

  func tableView(
    _ tableView: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch sections[indexPath.section].rows[indexPath.row] {
    case let .folder(folder, _):
      let controller = BrowserLibraryViewController(
        bookmarkManager: bookmarkManager,
        historyManager: historyManager,
        folderID: folder.id,
        folderTitle: folder.name
      )
      controller.onOpenURL = onOpenURL
      navigationController?.pushViewController(controller, animated: true)
    case let .bookmark(bookmark):
      onOpenURL?(bookmark.url, false)
      dismissOrPop()
    case let .history(entry):
      onOpenURL?(entry.url, false)
      dismissOrPop()
    }
  }

  func tableView(
    _ tableView: UITableView,
    contextMenuConfigurationForRowAt indexPath: IndexPath,
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    let row = sections[indexPath.section].rows[indexPath.row]
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
      [weak self] _ in
      switch row {
      case let .bookmark(bookmark):
        return UIMenu(children: [
          UIAction(
            title: "在新标签页打开",
            image: UIImage(systemName: "plus.square.on.square")
          ) { _ in self?.onOpenURL?(bookmark.url, true) },
          UIAction(
            title: "编辑",
            image: UIImage(systemName: "pencil")
          ) { _ in self?.promptToEdit(bookmark) },
          UIAction(
            title: "删除",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
          ) { _ in self?.removeBookmark(bookmark.id) },
        ])
      case let .history(entry):
        return UIMenu(children: [
          UIAction(
            title: "在新标签页打开",
            image: UIImage(systemName: "plus.square.on.square")
          ) { _ in self?.onOpenURL?(entry.url, true) },
          UIAction(
            title: "删除",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
          ) { _ in self?.removeHistory(entry.id) },
        ])
      case let .folder(folder, _):
        return UIMenu(children: [
          UIAction(
            title: "重命名",
            image: UIImage(systemName: "pencil")
          ) { _ in self?.promptToRename(folder) },
          UIAction(
            title: "删除",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
          ) { _ in self?.confirmRemoveFolder(folder) },
        ])
      }
    }
  }

  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    let row = sections[indexPath.section].rows[indexPath.row]
    let action = UIContextualAction(
      style: .destructive,
      title: "删除"
    ) { [weak self] _, _, completion in
      switch row {
      case let .bookmark(bookmark):
        self?.removeBookmark(bookmark.id)
      case let .history(entry):
        self?.removeHistory(entry.id)
      case let .folder(folder, _):
        self?.confirmRemoveFolder(folder)
      }
      completion(true)
    }
    return UISwipeActionsConfiguration(actions: [action])
  }

  private func promptForNewFolder() {
    let alert = UIAlertController(
      title: "新建书签文件夹",
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField { $0.placeholder = "文件夹名称" }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "新建", style: .default) {
      [weak self, weak alert] _ in
      let name = alert?.textFields?.first?.text ?? ""
      Task {
        _ = try? await self?.bookmarkManager.addFolder(name: name)
        self?.reloadData()
      }
    })
    present(alert, animated: true)
  }

  private func promptToEdit(_ bookmark: Bookmark) {
    let alert = UIAlertController(
      title: "编辑书签",
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField {
      $0.placeholder = "名称"
      $0.text = bookmark.title
    }
    alert.addTextField {
      $0.placeholder = "网址"
      $0.text = bookmark.url.absoluteString
      $0.keyboardType = .URL
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default) {
      [weak self, weak alert] _ in
      guard let title = alert?.textFields?.first?.text,
            let rawURL = alert?.textFields?.last?.text,
            let url = BrowserURLResolver.resolve(rawURL)
      else {
        return
      }
      var updated = bookmark
      updated.title = title
      updated.url = url
      Task {
        try? await self?.bookmarkManager.update(updated)
        self?.reloadData()
      }
    })
    present(alert, animated: true)
  }

  private func promptToRename(_ folder: BookmarkFolder) {
    let alert = UIAlertController(
      title: "重命名文件夹",
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField { $0.text = folder.name }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default) {
      [weak self, weak alert] _ in
      guard let name = alert?.textFields?.first?.text?
              .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
      else {
        return
      }
      var updated = folder
      updated.name = name
      Task {
        try? await self?.bookmarkManager.updateFolder(updated)
        self?.reloadData()
      }
    })
    present(alert, animated: true)
  }

  private func confirmRemoveFolder(_ folder: BookmarkFolder) {
    let alert = UIAlertController(
      title: "删除“\(folder.name)”？",
      message: "文件夹中的书签可以移到顶层，也可以一起删除。",
      preferredStyle: .actionSheet
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保留书签", style: .default) {
      [weak self] _ in
      self?.removeFolder(folder.id, deleteBookmarks: false)
    })
    alert.addAction(UIAlertAction(title: "全部删除", style: .destructive) {
      [weak self] _ in
      self?.removeFolder(folder.id, deleteBookmarks: true)
    })
    alert.popoverPresentationController?.sourceView = tableView
    present(alert, animated: true)
  }

  private func showClearHistoryOptions() {
    let alert = UIAlertController(
      title: "清除历史记录",
      message: nil,
      preferredStyle: .actionSheet
    )
    let ranges: [(String, TimeInterval?)] = [
      ("过去一小时", 3_600),
      ("今天", 86_400),
      ("过去七天", 604_800),
      ("全部时间", nil),
    ]
    for (title, interval) in ranges {
      alert.addAction(UIAlertAction(title: title, style: .destructive) {
        [weak self] _ in
        Task {
          let start = interval.map { Date().addingTimeInterval(-$0) }
          try? await self?.historyManager.clear(from: start)
          self?.reloadData()
        }
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.sourceView = view
    present(alert, animated: true)
  }

  private func removeBookmark(_ id: UUID) {
    Task {
      try? await bookmarkManager.remove(id: id)
      reloadData()
    }
  }

  private func removeHistory(_ id: UUID) {
    Task {
      try? await historyManager.remove(id: id)
      reloadData()
    }
  }

  private func removeFolder(_ id: UUID, deleteBookmarks: Bool) {
    Task {
      try? await bookmarkManager.removeFolder(
        id: id,
        deleteBookmarks: deleteBookmarks
      )
      reloadData()
    }
  }

  private func showMessage(title: String, message: String) {
    let alert = UIAlertController(
      title: title,
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  private func dismissOrPop() {
    if presentingViewController != nil,
       navigationController?.viewControllers.first === self {
      dismiss(animated: true)
    } else {
      navigationController?.popViewController(animated: true)
    }
  }
}
