import UIKit
import WebKit

@MainActor
final class SettingsViewController: UITableViewController {
  private enum Section: Int, CaseIterable {
    case browser
    case download
    case privacy
    case storage
    case about

    var title: String {
      switch self {
      case .browser: return "浏览设置"
      case .download: return "下载设置"
      case .privacy: return "隐私设置"
      case .storage: return "存储"
      case .about: return "关于"
      }
    }
  }

  private var settings: BrowserSettings {
    get { BrowserSettingsStore.shared.value }
    set {
      BrowserSettingsStore.shared.value = newValue
      tableView.reloadData()
    }
  }

  init() {
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "设置"
    navigationItem.largeTitleDisplayMode = .always
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
    )
    tableView.register(
      UITableViewCell.self,
      forCellReuseIdentifier: "SettingsCell"
    )
  }

  override func numberOfSections(in tableView: UITableView) -> Int {
    Section.allCases.count
  }

  override func tableView(
    _ tableView: UITableView,
    titleForHeaderInSection section: Int
  ) -> String? {
    Section(rawValue: section)?.title
  }

  override func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    switch Section(rawValue: section)! {
    case .browser: return 5
    case .download: return 1
    case .privacy: return 6
    case .storage: return 2
    case .about: return 3
    }
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(
      withIdentifier: "SettingsCell",
      for: indexPath
    )
    var content = cell.defaultContentConfiguration()
    content.textProperties.font = .preferredFont(forTextStyle: .body)
    cell.accessoryView = nil
    cell.accessoryType = .none
    let section = Section(rawValue: indexPath.section)!
    switch (section, indexPath.row) {
    case (.browser, 0):
      content.text = "默认搜索引擎"
      content.secondaryText = settings.searchEngine.title
      cell.accessoryType = .disclosureIndicator
    case (.browser, 1):
      content.text = "恢复上次标签页"
      cell.accessoryView = toggle(
        isOn: settings.restoresTabs,
        action: #selector(toggleRestore(_:))
      )
    case (.browser, 2):
      content.text = "默认请求桌面网站"
      cell.accessoryView = toggle(
        isOn: settings.requestsDesktopSite,
        action: #selector(toggleDesktop(_:))
      )
    case (.browser, 3):
      content.text = "下拉刷新"
      cell.accessoryView = toggle(
        isOn: settings.pullToRefresh,
        action: #selector(togglePullToRefresh(_:))
      )
    case (.browser, 4):
      content.text = "外观"
      content.secondaryText = settings.appearance.title
      cell.accessoryType = .disclosureIndicator
    case (.download, 0):
      content.text = "下载偏好"
      content.secondaryText = "并发数量、Wi-Fi、通知与保存位置"
      cell.accessoryType = .disclosureIndicator
    case (.privacy, 0):
      content.text = "内容过滤"
      cell.accessoryView = toggle(
        isOn: settings.contentBlockingEnabled,
        action: #selector(toggleContentBlocking(_:))
      )
    case (.privacy, 1):
      content.text = "广告与跟踪器过滤"
      content.secondaryText = "使用系统内容拦截器"
      cell.accessoryType = .disclosureIndicator
    case (.privacy, 2):
      content.text = "网站白名单"
      content.secondaryText = "\(settings.contentBlockerWhitelist.count) 个网站"
      cell.accessoryType = .disclosureIndicator
    case (.privacy, 3):
      content.text = "网站权限"
      content.secondaryText = "摄像头、麦克风和定位均需询问"
      cell.accessoryType = .disclosureIndicator
    case (.privacy, 4):
      content.text = "网站数据"
      content.secondaryText = "Cookie、缓存和本地存储"
      cell.accessoryType = .disclosureIndicator
    case (.privacy, 5):
      content.text = "清除浏览数据"
      content.textProperties.color = .systemRed
    case (.storage, 0):
      content.text = "管理下载目录"
      cell.accessoryType = .disclosureIndicator
    case (.storage, 1):
      content.text = "清理网页缓存"
      content.textProperties.color = .systemRed
    case (.about, 0):
      content.text = "版本"
      content.secondaryText =
        Bundle.main.object(
          forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    case (.about, 1):
      content.text = "隐私政策与使用条款"
      cell.accessoryType = .disclosureIndicator
    case (.about, 2):
      content.text = "开源许可证"
      cell.accessoryType = .disclosureIndicator
    default:
      break
    }
    cell.contentConfiguration = content
    return cell
  }

  override func tableView(
    _ tableView: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch (Section(rawValue: indexPath.section)!, indexPath.row) {
    case (.browser, 0): chooseSearchEngine()
    case (.browser, 4): chooseAppearance()
    case (.download, 0): showDownloadPreferences()
    case (.privacy, 1): showFilterOptions()
    case (.privacy, 2): showWhitelist()
    case (.privacy, 3):
      showText(
        title: "网站权限",
        text: "网站请求摄像头或麦克风时，浏览器会显示网站域名并逐次询问，不会静默授权。系统权限仍可在 iOS 设置中撤销。"
      )
    case (.privacy, 4): showWebsiteData()
    case (.privacy, 5): confirmClearAllData()
    case (.storage, 0):
      navigationController?.pushViewController(
        LibraryViewController(),
        animated: true
      )
    case (.storage, 1): clearCache()
    case (.about, 1):
      showText(
        title: "隐私与条款",
        text: "浏览记录和下载元数据仅保存在设备上。无痕标签不会写入浏览历史。下载前请确认你有权保存相关文件。"
      )
    case (.about, 2):
      showText(
        title: "开源许可证",
        text: "本应用使用 Apple 系统框架。第三方规则仅可在确认许可证后导入，本版本未打包来源不明的过滤列表。"
      )
    default: break
    }
  }

  private func toggle(isOn: Bool, action: Selector) -> UISwitch {
    let control = UISwitch()
    control.isOn = isOn
    control.addTarget(self, action: action, for: .valueChanged)
    return control
  }

  @objc private func toggleRestore(_ sender: UISwitch) {
    var value = settings
    value.restoresTabs = sender.isOn
    settings = value
  }

  @objc private func toggleDesktop(_ sender: UISwitch) {
    var value = settings
    value.requestsDesktopSite = sender.isOn
    settings = value
  }

  @objc private func togglePullToRefresh(_ sender: UISwitch) {
    var value = settings
    value.pullToRefresh = sender.isOn
    settings = value
  }

  @objc private func toggleContentBlocking(_ sender: UISwitch) {
    var value = settings
    value.contentBlockingEnabled = sender.isOn
    settings = value
    ContentBlockerManager.shared.invalidate()
  }

  private func chooseSearchEngine() {
    let alert = actionSheet(title: "默认搜索引擎")
    for engine in BrowserSearchEngine.allCases {
      alert.addAction(UIAlertAction(title: engine.title, style: .default) {
        [weak self] _ in
        guard var value = self?.settings else { return }
        value.searchEngine = engine
        self?.settings = value
      })
    }
    presentSheet(alert)
  }

  private func chooseAppearance() {
    let alert = actionSheet(title: "外观")
    for appearance in BrowserAppearance.allCases {
      alert.addAction(UIAlertAction(title: appearance.title, style: .default) {
        [weak self] _ in
        guard var value = self?.settings else { return }
        value.appearance = appearance
        self?.settings = value
      })
    }
    presentSheet(alert)
  }

  private func showDownloadPreferences() {
    let controller = DownloadPreferencesViewController()
    navigationController?.pushViewController(controller, animated: true)
  }

  private func showFilterOptions() {
    let alert = actionSheet(title: "过滤项目")
    let options: [(String, KeyPath<BrowserSettings, Bool>)] = [
      ("基础广告", \.blocksAds),
      ("隐私跟踪器", \.blocksTrackers),
      ("弹窗", \.blocksPopups),
      ("跨站跟踪", \.preventsCrossSiteTracking),
    ]
    for option in options {
      let enabled = settings[keyPath: option.1]
      alert.addAction(UIAlertAction(
        title: "\(enabled ? "✓ " : "")\(option.0)",
        style: .default
      ) { [weak self] _ in
        guard var value = self?.settings else { return }
        switch option.0 {
        case "基础广告": value.blocksAds.toggle()
        case "隐私跟踪器": value.blocksTrackers.toggle()
        case "弹窗": value.blocksPopups.toggle()
        default: value.preventsCrossSiteTracking.toggle()
        }
        self?.settings = value
        ContentBlockerManager.shared.invalidate()
      })
    }
    presentSheet(alert)
  }

  private func showWhitelist() {
    let alert = UIAlertController(
      title: "添加白名单网站",
      message: "输入域名，例如 example.com。该网站将不使用内容过滤。",
      preferredStyle: .alert
    )
    alert.addTextField {
      $0.placeholder = "example.com"
      $0.keyboardType = .URL
      $0.autocapitalizationType = .none
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "添加", style: .default) {
      [weak self, weak alert] _ in
      guard let host = alert?.textFields?.first?.text?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !host.isEmpty,
        var value = self?.settings
      else {
        return
      }
      if !value.contentBlockerWhitelist.contains(host.lowercased()) {
        value.contentBlockerWhitelist.append(host.lowercased())
      }
      self?.settings = value
    })
    present(alert, animated: true)
  }

  private func showWebsiteData() {
    navigationController?.pushViewController(
      WebsiteDataViewController(),
      animated: true
    )
  }

  private func confirmClearAllData() {
    let alert = UIAlertController(
      title: "清除全部浏览数据？",
      message: "Cookie、缓存、本地存储和网站登录状态将被删除。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "清除", style: .destructive) {
      [weak self] _ in
      Task {
        await WebsiteDataManager.shared.removeAll(since: .distantPast)
        self?.showText(title: "已清除", text: "浏览数据已从设备移除。")
      }
    })
    present(alert, animated: true)
  }

  private func clearCache() {
    Task {
      await WebsiteDataManager.shared.removeAll(
        since: .distantPast,
        dataTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
      )
      showText(title: "缓存已清理", text: "网站登录信息未被删除。")
    }
  }

  private func actionSheet(title: String) -> UIAlertController {
    let alert = UIAlertController(
      title: title,
      message: nil,
      preferredStyle: .actionSheet
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    return alert
  }

  private func presentSheet(_ alert: UIAlertController) {
    alert.popoverPresentationController?.sourceView = view
    present(alert, animated: true)
  }

  private func showText(title: String, text: String) {
    let alert = UIAlertController(
      title: title,
      message: text,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }
}

@MainActor
private final class WebsiteDataViewController: UITableViewController {
  private var records: [WKWebsiteDataRecord] = []

  init() {
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "网站数据"
    refreshControl = UIRefreshControl()
    refreshControl?.addAction(UIAction { [weak self] _ in
      self?.loadRecords()
    }, for: .valueChanged)
    loadRecords()
  }

  private func loadRecords() {
    Task {
      records = await WebsiteDataManager.shared.records()
        .sorted {
          $0.displayName.localizedStandardCompare($1.displayName)
            == .orderedAscending
        }
      tableView.reloadData()
      refreshControl?.endRefreshing()
    }
  }

  override func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    records.count
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.textLabel?.text = records[indexPath.row].displayName
    cell.detailTextLabel?.text = records[indexPath.row].dataTypes
      .sorted()
      .joined(separator: " · ")
    cell.detailTextLabel?.numberOfLines = 2
    return cell
  }

  override func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    let record = records[indexPath.row]
    let delete = UIContextualAction(style: .destructive, title: "删除") {
      [weak self] _, _, completion in
      Task {
        await WebsiteDataManager.shared.remove(records: [record])
        self?.loadRecords()
        completion(true)
      }
    }
    return UISwipeActionsConfiguration(actions: [delete])
  }
}

@MainActor
private final class DownloadPreferencesViewController: UITableViewController {
  private let manager = DownloadManager.shared

  init() {
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "下载偏好"
  }

  override func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    4
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.accessoryView = nil
    switch indexPath.row {
    case 0:
      cell.textLabel?.text = "同时下载任务数"
      cell.detailTextLabel?.text =
        "\(manager.preferences.maximumConcurrentDownloads)"
      let stepper = UIStepper()
      stepper.minimumValue = 1
      stepper.maximumValue = 6
      stepper.value = Double(manager.preferences.maximumConcurrentDownloads)
      stepper.addAction(UIAction { [weak self, weak cell] _ in
        guard let self, let stepper = cell?.accessoryView as? UIStepper else {
          return
        }
        var value = self.manager.preferences
        value.maximumConcurrentDownloads = Int(stepper.value)
        self.manager.updatePreferences(value)
        cell?.detailTextLabel?.text = "\(Int(stepper.value))"
      }, for: .valueChanged)
      cell.accessoryView = stepper
    case 1:
      cell.textLabel?.text = "仅使用 Wi-Fi 下载"
      cell.accessoryView = preferenceSwitch(
        isOn: manager.preferences.wifiOnly,
        keyPath: \.wifiOnly
      )
    case 2:
      cell.textLabel?.text = "下载前询问保存位置"
      cell.accessoryView = preferenceSwitch(
        isOn: manager.preferences.asksForDestination,
        keyPath: \.asksForDestination
      )
    default:
      cell.textLabel?.text = "下载完成通知"
      cell.accessoryView = preferenceSwitch(
        isOn: manager.preferences.notifiesOnCompletion,
        keyPath: \.notifiesOnCompletion
      )
    }
    return cell
  }

  private func preferenceSwitch(
    isOn: Bool,
    keyPath: WritableKeyPath<DownloadPreferences, Bool>
  ) -> UISwitch {
    let control = UISwitch()
    control.isOn = isOn
    control.addAction(UIAction { [weak self, weak control] _ in
      guard let self, let control else { return }
      var value = self.manager.preferences
      value[keyPath: keyPath] = control.isOn
      self.manager.updatePreferences(value)
    }, for: .valueChanged)
    return control
  }
}
