import UIKit

@MainActor
final class MainTabBarController: UITabBarController {
  override func viewDidLoad() {
    super.viewDidLoad()
    configureAppearance()

    let browser = BrowserViewController()
    browser.tabBarItem = UITabBarItem(
      title: "浏览器",
      image: UIImage(systemName: "globe"),
      selectedImage: UIImage(systemName: "globe")
    )

    let parser = navigation(
      root: SmartParseViewController(),
      title: "智能解析",
      image: "link.badge.plus"
    )
    let downloads = navigation(
      root: DownloadViewController(),
      title: "下载中",
      image: "arrow.down.circle"
    )
    let library = navigation(
      root: LibraryLandingViewController(),
      title: "文件",
      image: "folder"
    )

    viewControllers = [browser, parser, downloads, library]
    tabBar.accessibilityIdentifier = "main.tabBar"
  }

  private func navigation(
    root: UIViewController,
    title: String,
    image: String
  ) -> UINavigationController {
    let controller = UINavigationController(rootViewController: root)
    controller.navigationBar.prefersLargeTitles = true
    controller.tabBarItem = UITabBarItem(
      title: title,
      image: UIImage(systemName: image),
      selectedImage: UIImage(systemName: image + ".fill")
        ?? UIImage(systemName: image)
    )
    return controller
  }

  private func configureAppearance() {
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()
    appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    tabBar.standardAppearance = appearance
    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }
    tabBar.tintColor = .systemBlue
  }
}

@MainActor
final class LibraryLandingViewController: UIViewController {
  private enum Row {
    case all(Int)
    case folder(LibraryFolder, Int)
  }

  private let manager = LibraryManager.shared
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let emptyLabel = UILabel()
  private var rows: [Row] = []
  private var observer: NSObjectProtocol?

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "文件"
    view.backgroundColor = .systemGroupedBackground
    view.accessibilityIdentifier = "library.root"

    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        primaryAction: UIAction { [weak self] _ in self?.createFolder() }
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "ellipsis.circle"),
        menu: UIMenu(children: [
          UIAction(
            title: "按名称整理",
            image: UIImage(systemName: "textformat")
          ) { [weak self] _ in self?.reload(sortByName: true) },
        ])
      ),
    ]

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.backgroundColor = .clear
    tableView.rowHeight = 78
    tableView.accessibilityIdentifier = "library.list"

    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.text = "暂无文件"
    emptyLabel.textColor = .secondaryLabel
    emptyLabel.font = .preferredFont(forTextStyle: .title2)

    view.addSubview(tableView)
    view.addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

  private func reload(sortByName: Bool = false) {
    var folders = manager.folders
    if sortByName {
      folders.sort {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
    }
    rows = [.all(manager.files.count)]
    rows += folders.map { folder in
      .folder(folder, manager.files.filter { $0.folderID == folder.id }.count)
    }
    emptyLabel.isHidden = !manager.files.isEmpty || !folders.isEmpty
    tableView.reloadData()
  }

  private func createFolder() {
    let alert = UIAlertController(
      title: "新建文件夹",
      message: "输入文件夹名称",
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

  private func open(folderID: UUID?, title: String) {
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
}

extension LibraryLandingViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    rows.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let identifier = "LibraryLandingCell"
    let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
    switch rows[indexPath.row] {
    case let .all(count):
      cell.textLabel?.text = "全部视频"
      cell.detailTextLabel?.text = "\(count) 个视频"
      cell.imageView?.image = UIImage(systemName: "play.square.stack.fill")
    case let .folder(folder, count):
      cell.textLabel?.text = folder.name
      cell.detailTextLabel?.text = "\(count) 个视频"
      cell.imageView?.image = UIImage(systemName: "folder.fill")
    }
    cell.imageView?.tintColor = .systemBlue
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch rows[indexPath.row] {
    case .all:
      open(folderID: nil, title: "全部视频")
    case let .folder(folder, _):
      open(folderID: folder.id, title: folder.name)
    }
  }
}
