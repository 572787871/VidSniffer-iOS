import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class LibraryViewController: UIViewController {
  private enum Scope {
    case root
    case files(folderID: UUID?, title: String)
  }

  private enum Row {
    case allFiles(Int)
    case folder(LibraryFolder, Int)
    case file(LibraryFile)
  }

  private let manager: LibraryManager
  private let scope: Scope
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private lazy var collectionView = UICollectionView(
    frame: .zero,
    collectionViewLayout: makeGridLayout()
  )
  private let searchController = UISearchController(searchResultsController: nil)
  private let emptyLabel = UILabel()
  private var rows: [Row] = []
  private var sort: LibrarySort = .date
  private var isCompact = false
  private var usesGrid = false
  private var pendingCoverFile: LibraryFile?
  private var observer: NSObjectProtocol?

  init(
    manager: LibraryManager = .shared,
    folderID: UUID? = nil,
    folderTitle: String? = nil,
    showsFiles: Bool = false
  ) {
    self.manager = manager
    scope = showsFiles
      ? .files(folderID: folderID, title: folderTitle ?? "全部视频")
      : .root
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    navigationController?.navigationBar.prefersLargeTitles = true
    switch scope {
    case .root:
      title = "已下载"
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        systemItem: .close,
        primaryAction: UIAction { [weak self] _ in
          self?.dismiss(animated: true)
        }
      )
    case let .files(_, title):
      self.title = title
    }
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        primaryAction: UIAction { [weak self] _ in
          self?.promptForNewFolder()
        }
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "ellipsis.circle"),
        menu: makeMenu()
      ),
    ]

    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "搜索文件或文件夹"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.backgroundColor = .clear
    tableView.register(
      UITableViewCell.self,
      forCellReuseIdentifier: "LibraryCell"
    )
    tableView.allowsMultipleSelectionDuringEditing = true

    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.backgroundColor = .clear
    collectionView.isHidden = true
    collectionView.allowsMultipleSelection = true
    collectionView.register(
      LibraryGridCell.self,
      forCellWithReuseIdentifier: LibraryGridCell.reuseIdentifier
    )

    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.text = "暂无内容"
    emptyLabel.font = .preferredFont(forTextStyle: .title2)
    emptyLabel.textColor = .tertiaryLabel
    emptyLabel.adjustsFontForContentSizeCategory = true

    view.addSubview(tableView)
    view.addSubview(collectionView)
    view.addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    observer = NotificationCenter.default.addObserver(
      forName: .libraryDidChange,
      object: manager,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reload() }
    }
    reload()
  }

  private func makeMenu() -> UIMenu {
    let sortMenu = UIMenu(
      title: "排序",
      children: LibrarySort.allCases.map { value in
        UIAction(
          title: value.title,
          state: value == sort ? .on : .off
        ) { [weak self] _ in
          self?.sort = value
          self?.refreshMenu()
          self?.reload()
        }
      }
    )
    let densityMenu = UIMenu(title: "显示大小", children: [
      UIAction(title: "标准", state: isCompact ? .off : .on) {
        [weak self] _ in self?.setCompact(false)
      },
      UIAction(title: "紧凑", state: isCompact ? .on : .off) {
        [weak self] _ in self?.setCompact(true)
      },
    ])
    let layoutMenu = UIMenu(title: "显示方式", children: [
      UIAction(
        title: "列表",
        image: UIImage(systemName: "list.bullet"),
        state: usesGrid ? .off : .on
      ) { [weak self] _ in self?.setGrid(false) },
      UIAction(
        title: "网格",
        image: UIImage(systemName: "square.grid.2x2"),
        state: usesGrid ? .on : .off
      ) { [weak self] _ in self?.setGrid(true) },
    ])
    let selection = UIAction(
      title: "选择多个项目",
      image: UIImage(systemName: "checkmark.circle")
    ) { [weak self] _ in self?.beginSelection() }
    return UIMenu(children: [sortMenu, layoutMenu, densityMenu, selection])
  }

  private func refreshMenu() {
    navigationItem.rightBarButtonItems?.last?.menu = makeMenu()
  }

  private func setCompact(_ value: Bool) {
    isCompact = value
    refreshMenu()
    tableView.reloadData()
  }

  private func setGrid(_ value: Bool) {
    guard case .files = scope else { return }
    usesGrid = value
    tableView.isHidden = value
    collectionView.isHidden = !value
    refreshMenu()
    collectionView.reloadData()
  }

  private func makeGridLayout() -> UICollectionViewLayout {
    let item = NSCollectionLayoutItem(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(0.5),
        heightDimension: .estimated(210)
      )
    )
    item.contentInsets = NSDirectionalEdgeInsets(
      top: 6,
      leading: 6,
      bottom: 6,
      trailing: 6
    )
    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1),
        heightDimension: .estimated(210)
      ),
      subitems: [item]
    )
    let section = NSCollectionLayoutSection(group: group)
    section.contentInsets = NSDirectionalEdgeInsets(
      top: 8,
      leading: 10,
      bottom: 24,
      trailing: 10
    )
    return UICollectionViewCompositionalLayout(section: section)
  }

  private func reload() {
    let query = searchController.searchBar.text ?? ""
    switch scope {
    case .root:
      let folders = manager.folders
        .filter {
          query.isEmpty
            || $0.name.localizedCaseInsensitiveContains(query)
        }
      rows = []
      if query.isEmpty {
        rows.append(.allFiles(manager.files.count))
      }
      rows.append(contentsOf: folders.map { folder in
        .folder(
          folder,
          manager.files.filter { $0.folderID == folder.id }.count
        )
      })
    case let .files(folderID, _):
      rows = manager.files(in: folderID, query: query, sort: sort).map(Row.file)
    }
    emptyLabel.isHidden = !rows.isEmpty
    tableView.reloadData()
    collectionView.reloadData()
  }

  private func openFiles(folderID: UUID?, title: String) {
    navigationController?.pushViewController(
      LibraryViewController(
        manager: manager,
        folderID: folderID,
        folderTitle: title,
        showsFiles: true
      ),
      animated: true
    )
  }

  private func promptForNewFolder() {
    let alert = UIAlertController(
      title: "新建文件夹",
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField { $0.placeholder = "文件夹名称" }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "新建", style: .default) {
      [weak self, weak alert] _ in
      self?.manager.addFolder(name: alert?.textFields?.first?.text ?? "")
    })
    present(alert, animated: true)
  }

  private func promptRename(folder: LibraryFolder) {
    let alert = UIAlertController(
      title: "重命名文件夹",
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField { $0.text = folder.name }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default) {
      [weak self, weak alert] _ in
      self?.manager.renameFolder(
        folder,
        name: alert?.textFields?.first?.text ?? folder.name
      )
    })
    present(alert, animated: true)
  }

  private func confirmDelete(folder: LibraryFolder) {
    let alert = UIAlertController(
      title: "删除“\(folder.name)”？",
      message: "文件会保留并移回全部视频。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "删除文件夹", style: .destructive) {
      [weak self] _ in self?.manager.deleteFolder(folder)
    })
    present(alert, animated: true)
  }

  private func promptRename(file: LibraryFile) {
    let alert = UIAlertController(
      title: "重命名文件",
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField { $0.text = file.displayName }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default) {
      [weak self, weak alert] _ in
      do {
        try self?.manager.renameFile(
          file,
          name: alert?.textFields?.first?.text ?? file.displayName
        )
      } catch {
        self?.showError("文件正在使用或名称已存在。")
      }
    })
    present(alert, animated: true)
  }

  private func showMoveMenu(file: LibraryFile) {
    let alert = UIAlertController(
      title: "移动到",
      message: nil,
      preferredStyle: .actionSheet
    )
    alert.addAction(UIAlertAction(title: "全部视频", style: .default) {
      [weak self] _ in self?.manager.moveFile(file, to: nil)
    })
    for folder in manager.folders {
      alert.addAction(UIAlertAction(title: folder.name, style: .default) {
        [weak self] _ in self?.manager.moveFile(file, to: folder.id)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.sourceView = view
    present(alert, animated: true)
  }

  private func share(file: LibraryFile) {
    let controller = UIActivityViewController(
      activityItems: [manager.url(for: file)],
      applicationActivities: nil
    )
    controller.popoverPresentationController?.sourceView = view
    present(controller, animated: true)
  }

  private func chooseCustomCover(for file: LibraryFile) {
    pendingCoverFile = file
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    present(picker, animated: true)
  }

  private func beginSelection() {
    guard case .files = scope else { return }
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        systemItem: .done,
        primaryAction: UIAction { [weak self] _ in self?.endSelection() }
      ),
    ]
    tableView.setEditing(true, animated: true)
    collectionView.allowsMultipleSelection = true
    navigationController?.setToolbarHidden(false, animated: true)
    toolbarItems = [
      UIBarButtonItem(
        title: "分享",
        primaryAction: UIAction { [weak self] _ in self?.shareSelected() }
      ),
      UIBarButtonItem(systemItem: .flexibleSpace),
      UIBarButtonItem(
        title: "移动",
        primaryAction: UIAction { [weak self] _ in self?.moveSelected() }
      ),
      UIBarButtonItem(systemItem: .flexibleSpace),
      UIBarButtonItem(
        title: "删除",
        primaryAction: UIAction { [weak self] _ in self?.deleteSelected() }
      ),
    ]
  }

  private func endSelection() {
    tableView.setEditing(false, animated: true)
    tableView.indexPathsForSelectedRows?.forEach {
      tableView.deselectRow(at: $0, animated: false)
    }
    collectionView.indexPathsForSelectedItems?.forEach {
      collectionView.deselectItem(at: $0, animated: false)
    }
    navigationController?.setToolbarHidden(true, animated: true)
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        primaryAction: UIAction { [weak self] _ in
          self?.promptForNewFolder()
        }
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "ellipsis.circle"),
        menu: makeMenu()
      ),
    ]
  }

  private func selectedFiles() -> [LibraryFile] {
    let paths = usesGrid
      ? collectionView.indexPathsForSelectedItems ?? []
      : tableView.indexPathsForSelectedRows ?? []
    return paths.compactMap {
      guard rows.indices.contains($0.row),
            case let .file(file) = rows[$0.row]
      else {
        return nil
      }
      return file
    }
  }

  private func shareSelected() {
    let urls = selectedFiles().map(manager.url(for:))
    guard !urls.isEmpty else { return }
    let controller = UIActivityViewController(
      activityItems: urls,
      applicationActivities: nil
    )
    controller.popoverPresentationController?.sourceView = view
    present(controller, animated: true)
  }

  private func moveSelected() {
    let files = selectedFiles()
    guard !files.isEmpty else { return }
    let alert = UIAlertController(
      title: "移动 \(files.count) 个项目",
      message: nil,
      preferredStyle: .actionSheet
    )
    let destinations: [(String, UUID?)] = [("全部视频", nil)]
      + manager.folders.map { ($0.name, Optional($0.id)) }
    for destination in destinations {
      alert.addAction(UIAlertAction(title: destination.0, style: .default) {
        [weak self] _ in
        files.forEach { self?.manager.moveFile($0, to: destination.1) }
        self?.endSelection()
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.sourceView = view
    present(alert, animated: true)
  }

  private func deleteSelected() {
    let files = selectedFiles()
    guard !files.isEmpty else { return }
    let alert = UIAlertController(
      title: "删除 \(files.count) 个文件？",
      message: "此操作无法撤销。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "删除", style: .destructive) {
      [weak self] _ in
      files.forEach { try? self?.manager.deleteFile($0) }
      self?.endSelection()
    })
    present(alert, animated: true)
  }

  private func confirmDelete(file: LibraryFile) {
    let alert = UIAlertController(
      title: "删除文件？",
      message: "此操作会同时删除设备上的视频，无法撤销。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "删除", style: .destructive) {
      [weak self] _ in
      do {
        try self?.manager.deleteFile(file)
      } catch {
        self?.showError("文件暂时无法删除，请稍后重试。")
      }
    })
    present(alert, animated: true)
  }

  private func showDetails(file: LibraryFile) {
    let size = ByteCountFormatter.string(
      fromByteCount: file.size,
      countStyle: .file
    )
    let message = [
      "名称：\(file.displayName)",
      "大小：\(size)",
      "位置：\(file.relativePath)",
      "类型：\(file.mimeType ?? "未知")",
    ].joined(separator: "\n")
    let alert = UIAlertController(
      title: "文件详情",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  private func showError(_ message: String) {
    let alert = UIAlertController(
      title: "操作未完成",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }
}

extension LibraryViewController:
  UISearchResultsUpdating,
  UITableViewDataSource,
  UITableViewDelegate
{
  func updateSearchResults(for searchController: UISearchController) {
    reload()
  }

  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    rows.count
  }

  func tableView(
    _ tableView: UITableView,
    heightForRowAt indexPath: IndexPath
  ) -> CGFloat {
    isCompact ? 62 : 82
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(
      withIdentifier: "LibraryCell",
      for: indexPath
    )
    var content = cell.defaultContentConfiguration()
    content.textProperties.font = .preferredFont(forTextStyle: .headline)
    content.secondaryTextProperties.font =
      .preferredFont(forTextStyle: .subheadline)
    switch rows[indexPath.row] {
    case let .allFiles(count):
      content.text = "全部视频"
      content.secondaryText = "\(count) 个视频"
      content.image = UIImage(systemName: "play.square.stack.fill")
      content.imageProperties.tintColor = .systemBlue
      cell.accessoryType = .disclosureIndicator
    case let .folder(folder, count):
      content.text = folder.name
      content.secondaryText = "\(count) 个视频"
      content.image = UIImage(systemName: "folder.fill")
      content.imageProperties.tintColor = .systemBlue
      cell.accessoryType = .disclosureIndicator
    case let .file(file):
      content.text = file.displayName
      content.secondaryText = ByteCountFormatter.string(
        fromByteCount: file.size,
        countStyle: .file
      )
      content.image = manager.coverURL(for: file)
        .flatMap(UIImage.init(contentsOfFile:))
        ?? UIImage(systemName: file.isFavorite ? "star.fill" : "film")
      content.imageProperties.tintColor =
        file.isFavorite ? .systemYellow : .systemBlue
      cell.accessoryType = .none
    }
    cell.contentConfiguration = content
    return cell
  }

  func tableView(
    _ tableView: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch rows[indexPath.row] {
    case .allFiles:
      openFiles(folderID: nil, title: "全部视频")
    case let .folder(folder, _):
      openFiles(folderID: folder.id, title: folder.name)
    case let .file(file):
      present(
        VideoPlayerViewController(file: file, queue: visibleFiles()),
        animated: true
      )
    }
  }

  func tableView(
    _ tableView: UITableView,
    contextMenuConfigurationForRowAt indexPath: IndexPath,
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    switch rows[indexPath.row] {
    case .allFiles:
      return nil
    case let .folder(folder, _):
      return UIContextMenuConfiguration(
        identifier: nil,
        previewProvider: nil
      ) { [weak self] _ in
        UIMenu(children: [
          UIAction(title: "重命名", image: UIImage(systemName: "pencil")) {
            _ in self?.promptRename(folder: folder)
          },
          UIAction(
            title: "删除文件夹",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
          ) { _ in self?.confirmDelete(folder: folder) },
        ])
      }
    case let .file(file):
      return UIContextMenuConfiguration(
        identifier: nil,
        previewProvider: nil
      ) { [weak self] _ in
        let favoriteTitle = file.isFavorite ? "取消收藏" : "收藏"
        return UIMenu(children: [
          UIAction(title: "播放", image: UIImage(systemName: "play.fill")) {
            _ in
            self?.present(
              VideoPlayerViewController(
                file: file,
                queue: self?.visibleFiles() ?? [file]
              ),
              animated: true
            )
          },
          UIAction(title: "分享与导出", image: UIImage(systemName: "square.and.arrow.up")) {
            _ in self?.share(file: file)
          },
          UIAction(title: "重命名", image: UIImage(systemName: "pencil")) {
            _ in self?.promptRename(file: file)
          },
          UIAction(title: "移动", image: UIImage(systemName: "folder")) {
            _ in self?.showMoveMenu(file: file)
          },
          UIAction(title: "制作副本", image: UIImage(systemName: "plus.square.on.square")) {
            _ in
            do {
              try self?.manager.copyFile(file)
            } catch {
              self?.showError("暂时无法复制此文件。")
            }
          },
          UIAction(title: "自定义封面", image: UIImage(systemName: "photo")) {
            _ in self?.chooseCustomCover(for: file)
          },
          UIAction(title: favoriteTitle, image: UIImage(systemName: "star")) {
            _ in
            var value = file
            value.isFavorite.toggle()
            self?.manager.updateFile(value)
          },
          UIAction(title: "查看详情", image: UIImage(systemName: "info.circle")) {
            _ in self?.showDetails(file: file)
          },
          UIAction(
            title: "删除",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
          ) { _ in self?.confirmDelete(file: file) },
        ])
      }
    }
  }

  private func visibleFiles() -> [LibraryFile] {
    rows.compactMap {
      guard case let .file(file) = $0 else { return nil }
      return file
    }
  }
}

extension LibraryViewController:
  UICollectionViewDataSource,
  UICollectionViewDelegate
{
  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    rows.count
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    guard let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: LibraryGridCell.reuseIdentifier,
      for: indexPath
    ) as? LibraryGridCell,
          case let .file(file) = rows[indexPath.item]
    else {
      return UICollectionViewCell()
    }
    let cover = manager.coverURL(for: file)
      .flatMap { UIImage(contentsOfFile: $0.path) }
    cell.configure(file: file, cover: cover)
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard !tableView.isEditing,
          case let .file(file) = rows[indexPath.item]
    else {
      return
    }
    collectionView.deselectItem(at: indexPath, animated: false)
    present(
      VideoPlayerViewController(file: file, queue: visibleFiles()),
      animated: true
    )
  }
}

extension LibraryViewController: PHPickerViewControllerDelegate {
  func picker(
    _ picker: PHPickerViewController,
    didFinishPicking results: [PHPickerResult]
  ) {
    picker.dismiss(animated: true)
    guard let file = pendingCoverFile,
          let provider = results.first?.itemProvider,
          provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
    else {
      pendingCoverFile = nil
      return
    }
    provider.loadDataRepresentation(
      forTypeIdentifier: UTType.image.identifier
    ) { [weak self] data, _ in
      guard let data else { return }
      Task { @MainActor in
        do {
          try self?.manager.setCustomCover(data: data, for: file)
        } catch {
          self?.showError("无法保存所选封面。")
        }
        self?.pendingCoverFile = nil
      }
    }
  }
}

private final class LibraryGridCell: UICollectionViewCell {
  static let reuseIdentifier = "LibraryGridCell"

  private let imageView = UIImageView()
  private let titleLabel = UILabel()
  private let detailLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.backgroundColor = .secondarySystemGroupedBackground
    contentView.layer.cornerRadius = 16
    contentView.clipsToBounds = true

    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.backgroundColor = .tertiarySystemGroupedBackground
    imageView.tintColor = .systemBlue
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 2
    detailLabel.font = .preferredFont(forTextStyle: .caption1)
    detailLabel.textColor = .secondaryLabel

    let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, detailLabel])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 7
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentView.topAnchor),
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.bottomAnchor.constraint(
        equalTo: contentView.bottomAnchor,
        constant: -10
      ),
      imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
      titleLabel.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor,
        constant: 10
      ),
      titleLabel.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -10
      ),
      detailLabel.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor,
        constant: 10
      ),
      detailLabel.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -10
      ),
    ])
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isSelected: Bool {
    didSet {
      contentView.layer.borderWidth = isSelected ? 3 : 0
      contentView.layer.borderColor = UIColor.systemBlue.cgColor
    }
  }

  func configure(file: LibraryFile, cover: UIImage?) {
    imageView.image = cover ?? UIImage(systemName: "film.fill")
    imageView.contentMode = cover == nil ? .scaleAspectFit : .scaleAspectFill
    titleLabel.text = file.displayName
    detailLabel.text = ByteCountFormatter.string(
      fromByteCount: file.size,
      countStyle: .file
    )
    accessibilityLabel = "\(file.displayName)，\(detailLabel.text ?? "")"
  }
}
