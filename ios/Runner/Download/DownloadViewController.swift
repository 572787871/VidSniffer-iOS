import UIKit

@MainActor
final class DownloadViewController: UIViewController {
  private let manager: DownloadManager
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let emptyLabel = UILabel()
  private var tasks: [DownloadTaskModel] = []
  private var observer: NSObjectProtocol?

  init(manager: DownloadManager = .shared) {
    self.manager = manager
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
    title = "下载中"
    navigationItem.largeTitleDisplayMode = .always
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in
        self?.dismiss(animated: true)
      }
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "ellipsis.circle"),
      menu: makeMenu()
    )

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.backgroundColor = .clear
    tableView.rowHeight = 174
    tableView.register(
      DownloadTaskCell.self,
      forCellReuseIdentifier: DownloadTaskCell.reuseIdentifier
    )

    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.text = "暂无下载任务"
    emptyLabel.font = .preferredFont(forTextStyle: .title2)
    emptyLabel.textColor = .tertiaryLabel
    emptyLabel.adjustsFontForContentSizeCategory = true

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
      forName: .downloadTasksDidChange,
      object: manager,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reload() }
    }
    reload()
  }

  private func makeMenu() -> UIMenu {
    UIMenu(children: [
      UIAction(
        title: "全部暂停",
        image: UIImage(systemName: "pause.fill")
      ) { [weak self] _ in self?.manager.pauseAll() },
      UIAction(
        title: "全部继续",
        image: UIImage(systemName: "play.fill")
      ) { [weak self] _ in self?.manager.resumeAll() },
      UIAction(
        title: "清理失败记录",
        image: UIImage(systemName: "trash"),
        attributes: [.destructive]
      ) { [weak self] _ in
        guard let self else { return }
        manager.tasks
          .filter { [.failed, .cancelled].contains($0.state) }
          .forEach { manager.removeRecord(id: $0.id) }
      },
    ])
  }

  private func reload() {
    tasks = manager.tasks.filter { $0.state != .completed }
    emptyLabel.isHidden = !tasks.isEmpty
    tableView.reloadData()
  }

  private func confirmCancel(_ task: DownloadTaskModel) {
    let alert = UIAlertController(
      title: "取消下载？",
      message: "任务记录会保留，之后仍可重试。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "继续下载", style: .cancel))
    alert.addAction(UIAlertAction(title: "取消下载", style: .destructive) {
      [weak self] _ in self?.manager.cancel(id: task.id)
    })
    present(alert, animated: true)
  }
}

extension DownloadViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    tasks.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    guard let cell = tableView.dequeueReusableCell(
      withIdentifier: DownloadTaskCell.reuseIdentifier,
      for: indexPath
    ) as? DownloadTaskCell else {
      return UITableViewCell()
    }
    let task = tasks[indexPath.row]
    cell.configure(with: task)
    cell.onPrimaryAction = { [weak self] in
      if task.state.canPause {
        self?.manager.pause(id: task.id)
      } else if task.state.canResume {
        self?.manager.resume(id: task.id)
      } else if task.state == .cancelled {
        self?.manager.retry(id: task.id)
      }
    }
    cell.onCancel = { [weak self] in self?.confirmCancel(task) }
    return cell
  }

  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    let task = tasks[indexPath.row]
    let delete = UIContextualAction(
      style: .destructive,
      title: "删除记录"
    ) { [weak self] _, _, completion in
      self?.manager.removeRecord(id: task.id)
      completion(true)
    }
    let primary = UIContextualAction(
      style: .normal,
      title: task.state.canPause ? "暂停" : "继续"
    ) { [weak self] _, _, completion in
      if task.state.canPause {
        self?.manager.pause(id: task.id)
      } else {
        self?.manager.resume(id: task.id)
      }
      completion(true)
    }
    primary.backgroundColor = .systemBlue
    let configuration = UISwipeActionsConfiguration(actions: [delete, primary])
    configuration.performsFirstActionWithFullSwipe = false
    return configuration
  }
}

private final class DownloadTaskCell: UITableViewCell {
  static let reuseIdentifier = "DownloadTaskCell"

  var onPrimaryAction: (() -> Void)?
  var onCancel: (() -> Void)?

  private let titleLabel = UILabel()
  private let statusLabel = UILabel()
  private let sizeLabel = UILabel()
  private let timeLabel = UILabel()
  private let progressView = UIProgressView(progressViewStyle: .default)
  private let primaryButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .secondarySystemGroupedBackground

    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 2
    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.textColor = .secondaryLabel
    sizeLabel.font = .preferredFont(forTextStyle: .subheadline)
    sizeLabel.textColor = .secondaryLabel
    timeLabel.font = .preferredFont(forTextStyle: .subheadline)
    timeLabel.textColor = .secondaryLabel
    timeLabel.textAlignment = .right
    progressView.progressTintColor = .systemBlue

    primaryButton.configuration = .tinted()
    cancelButton.configuration = .plain()
    cancelButton.configuration?.baseForegroundColor = .systemRed
    primaryButton.addAction(UIAction { [weak self] _ in
      self?.onPrimaryAction?()
    }, for: .touchUpInside)
    cancelButton.addAction(UIAction { [weak self] _ in
      self?.onCancel?()
    }, for: .touchUpInside)

    let details = UIStackView(arrangedSubviews: [sizeLabel, timeLabel])
    details.axis = .horizontal
    details.distribution = .fillEqually
    let actions = UIStackView(arrangedSubviews: [primaryButton, cancelButton])
    actions.axis = .horizontal
    actions.spacing = 12
    actions.distribution = .fillEqually
    let stack = UIStackView(arrangedSubviews: [
      titleLabel,
      statusLabel,
      progressView,
      details,
      actions,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 9
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
      stack.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor,
        constant: 16
      ),
      stack.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -16
      ),
      stack.bottomAnchor.constraint(
        lessThanOrEqualTo: contentView.bottomAnchor,
        constant: -14
      ),
      progressView.heightAnchor.constraint(equalToConstant: 4),
      primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(with task: DownloadTaskModel) {
    titleLabel.text = task.filename
    statusLabel.text = statusText(for: task)
    progressView.progress = Float(task.progress)
    sizeLabel.text = sizeText(for: task)
    timeLabel.text = remainingText(for: task)
    let primaryTitle: String
    let primaryImage: String
    if task.state.canPause {
      primaryTitle = "暂停"
      primaryImage = "pause.fill"
    } else if task.state.canResume {
      primaryTitle = "继续"
      primaryImage = "play.fill"
    } else {
      primaryTitle = "重试"
      primaryImage = "arrow.clockwise"
    }
    primaryButton.configuration?.title = primaryTitle
    primaryButton.configuration?.image = UIImage(systemName: primaryImage)
    primaryButton.configuration?.imagePadding = 6
    cancelButton.configuration?.title = "取消"
    cancelButton.configuration?.image = UIImage(systemName: "xmark")
    cancelButton.configuration?.imagePadding = 6
  }

  private func statusText(for task: DownloadTaskModel) -> String {
    guard task.state == .downloading, task.speed > 0 else {
      return task.errorMessage ?? task.state.displayName
    }
    return "\(task.state.displayName) · \(ByteCountFormatter.string(
      fromByteCount: Int64(task.speed),
      countStyle: .file
    ))/秒"
  }

  private func sizeText(for task: DownloadTaskModel) -> String {
    let downloaded = ByteCountFormatter.string(
      fromByteCount: task.downloadedSize,
      countStyle: .file
    )
    guard task.expectedSize > 0 else { return downloaded }
    let expected = ByteCountFormatter.string(
      fromByteCount: task.expectedSize,
      countStyle: .file
    )
    return "\(downloaded) / \(expected)"
  }

  private func remainingText(for task: DownloadTaskModel) -> String {
    guard let remaining = task.remainingTime, remaining.isFinite else {
      return "剩余时间未知"
    }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = remaining >= 3_600
      ? [.hour, .minute]
      : [.minute, .second]
    formatter.unitsStyle = .abbreviated
    return "剩余 \(formatter.string(from: remaining) ?? "--")"
  }
}
