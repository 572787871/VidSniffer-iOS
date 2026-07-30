import UIKit

@MainActor
final class BrowserTabSwitcherViewController: UIViewController {
  private enum Section: Int, CaseIterable {
    case normal
    case privateTabs

    var title: String {
      switch self {
      case .normal: "标签页"
      case .privateTabs: "无痕标签页"
      }
    }

    var isPrivate: Bool {
      self == .privateTabs
    }
  }

  private let manager: BrowserTabManager
  private var isSelectingTabs = false
  private lazy var collectionView = UICollectionView(
    frame: .zero,
    collectionViewLayout: makeLayout()
  )

  var onSelectTab: ((UUID) -> Void)?

  init(manager: BrowserTabManager) {
    self.manager = manager
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "标签页"
    view.backgroundColor = .systemGroupedBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
    )
    navigationItem.rightBarButtonItems = makeToolbarItems()

    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.backgroundColor = .clear
    collectionView.alwaysBounceVertical = true
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.dragDelegate = self
    collectionView.dropDelegate = self
    collectionView.dragInteractionEnabled = true
    collectionView.register(
      BrowserTabCell.self,
      forCellWithReuseIdentifier: BrowserTabCell.reuseIdentifier
    )
    collectionView.register(
      BrowserTabSectionHeader.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: BrowserTabSectionHeader.reuseIdentifier
    )
    view.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func makeToolbarItems() -> [UIBarButtonItem] {
    let management = UIBarButtonItem(
      image: UIImage(systemName: "ellipsis.circle"),
      menu: makeManagementMenu()
    )
    management.accessibilityIdentifier = "tabs.management"
    management.accessibilityLabel = "标签页管理"
    let newTab = UIBarButtonItem(
      image: UIImage(systemName: "plus"),
      menu: makeNewTabMenu()
    )
    newTab.accessibilityIdentifier = "tabs.new"
    newTab.accessibilityLabel = "新建标签页"
    return [management, newTab]
  }

  private func makeNewTabMenu() -> UIMenu {
    UIMenu(children: [
      UIAction(
        title: "新建标签页",
        image: UIImage(systemName: "plus.square")
      ) { [weak self] _ in
        self?.createTab(isPrivate: false)
      },
      UIAction(
        title: "新建无痕标签页",
        image: UIImage(systemName: "eye.slash")
      ) { [weak self] _ in
        self?.createTab(isPrivate: true)
      },
    ])
  }

  private func makeManagementMenu() -> UIMenu {
    UIMenu(children: [
      UIAction(
        title: "恢复最近关闭的标签页",
        image: UIImage(systemName: "clock.arrow.circlepath"),
        attributes: manager.recentlyClosed.isEmpty ? [.disabled] : []
      ) { [weak self] _ in
        guard let self,
              let tab = self.manager.restoreMostRecentlyClosed()
        else {
          return
        }
        self.collectionView.reloadData()
        self.onSelectTab?(tab.id)
      },
      UIAction(
        title: "关闭所有普通标签页",
        image: UIImage(systemName: "rectangle.stack.badge.minus"),
        attributes: [.destructive]
      ) { [weak self] _ in
        self?.confirmCloseAll(isPrivate: false)
      },
      UIAction(
        title: "关闭所有无痕标签页",
        image: UIImage(systemName: "eye.slash"),
        attributes: [.destructive]
      ) { [weak self] _ in
        self?.confirmCloseAll(isPrivate: true)
      },
    ])
  }

  private func createTab(isPrivate: Bool) {
    let tab = manager.createTab(isPrivate: isPrivate)
    collectionView.reloadData()
    onSelectTab?(tab.id)
  }

  private func confirmCloseAll(isPrivate: Bool) {
    let kind = isPrivate ? "无痕" : "普通"
    let alert = UIAlertController(
      title: "关闭所有\(kind)标签页？",
      message: isPrivate ? "无痕标签页关闭后无法恢复。" : nil,
      preferredStyle: .actionSheet
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "全部关闭", style: .destructive) {
      [weak self] _ in
      self?.manager.closeAllTabs(isPrivate: isPrivate)
      self?.collectionView.reloadData()
    })
    present(alert, animated: true)
  }

  private func enterSelection(selecting tabID: UUID) {
    isSelectingTabs = true
    collectionView.allowsMultipleSelection = true
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "取消",
      primaryAction: UIAction { [weak self] _ in
        self?.leaveSelection()
      }
    )
    updateSelectionControls()
    guard let indexPath = indexPath(for: tabID) else { return }
    collectionView.selectItem(
      at: indexPath,
      animated: true,
      scrollPosition: []
    )
    updateSelectionControls()
  }

  private func leaveSelection() {
    isSelectingTabs = false
    collectionView.indexPathsForSelectedItems?.forEach {
      collectionView.deselectItem(at: $0, animated: true)
    }
    collectionView.allowsMultipleSelection = false
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
    )
    navigationItem.rightBarButtonItems = makeToolbarItems()
    title = "标签页"
  }

  private func updateSelectionControls() {
    let count = collectionView.indexPathsForSelectedItems?.count ?? 0
    title = count == 0 ? "选择标签页" : "已选择 \(count) 个"
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        title: "关闭",
        image: UIImage(systemName: "trash"),
        primaryAction: UIAction(
          attributes: count == 0 ? [.disabled] : [.destructive]
        ) { [weak self] _ in
          self?.closeSelectedTabs()
        }
      ),
    ]
  }

  private func closeSelectedTabs() {
    let ids = (collectionView.indexPathsForSelectedItems ?? []).compactMap {
      path -> UUID? in
      let sectionTabs = tabs(in: path.section)
      guard sectionTabs.indices.contains(path.item) else { return nil }
      return sectionTabs[path.item].id
    }
    ids.forEach(manager.closeTab(id:))
    collectionView.reloadData()
    leaveSelection()
  }

  private func indexPath(for tabID: UUID) -> IndexPath? {
    for section in Section.allCases {
      if let item = tabs(in: section.rawValue)
        .firstIndex(where: { $0.id == tabID }) {
        return IndexPath(item: item, section: section.rawValue)
      }
    }
    return nil
  }

  private func tabs(in section: Int) -> [BrowserTab] {
    guard let section = Section(rawValue: section) else { return [] }
    return manager.tabs(isPrivate: section.isPrivate)
  }

  private func makeLayout() -> UICollectionViewLayout {
    UICollectionViewCompositionalLayout { _, environment in
      let columns = environment.container.effectiveContentSize.width > 700
        ? 3
        : 2
      let item = NSCollectionLayoutItem(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
          heightDimension: .fractionalHeight(1)
        )
      )
      item.contentInsets = NSDirectionalEdgeInsets(
        top: 7,
        leading: 7,
        bottom: 7,
        trailing: 7
      )
      let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .fractionalWidth(1),
          heightDimension: .estimated(250)
        ),
        subitems: [item]
      )
      let section = NSCollectionLayoutSection(group: group)
      section.contentInsets = NSDirectionalEdgeInsets(
        top: 4,
        leading: 11,
        bottom: 24,
        trailing: 11
      )
      section.boundarySupplementaryItems = [
        NSCollectionLayoutBoundarySupplementaryItem(
          layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(42)
          ),
          elementKind: UICollectionView.elementKindSectionHeader,
          alignment: .top
        ),
      ]
      return section
    }
  }
}

extension BrowserTabSwitcherViewController:
  UICollectionViewDataSource,
  UICollectionViewDelegate
{
  func numberOfSections(in collectionView: UICollectionView) -> Int {
    Section.allCases.count
  }

  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    tabs(in: section).count
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    guard let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: BrowserTabCell.reuseIdentifier,
      for: indexPath
    ) as? BrowserTabCell else {
      return UICollectionViewCell()
    }
    let tab = tabs(in: indexPath.section)[indexPath.item]
    cell.configure(
      tab: tab,
      isSelectedTab: tab.id == manager.selectedTabID
    ) { [weak self, weak collectionView] in
      self?.manager.closeTab(id: tab.id)
      collectionView?.reloadData()
    }
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    viewForSupplementaryElementOfKind kind: String,
    at indexPath: IndexPath
  ) -> UICollectionReusableView {
    guard let header = collectionView.dequeueReusableSupplementaryView(
      ofKind: kind,
      withReuseIdentifier: BrowserTabSectionHeader.reuseIdentifier,
      for: indexPath
    ) as? BrowserTabSectionHeader,
      let section = Section(rawValue: indexPath.section)
    else {
      return UICollectionReusableView()
    }
    header.configure(
      title: section.title,
      count: tabs(in: indexPath.section).count,
      isPrivate: section.isPrivate
    )
    return header
  }

  func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    if isSelectingTabs {
      updateSelectionControls()
      return
    }
    onSelectTab?(tabs(in: indexPath.section)[indexPath.item].id)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    didDeselectItemAt indexPath: IndexPath
  ) {
    if isSelectingTabs {
      updateSelectionControls()
    }
  }

  func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    let tab = tabs(in: indexPath.section)[indexPath.item]
    return UIContextMenuConfiguration(
      identifier: tab.id.uuidString as NSString,
      previewProvider: nil
    ) { [weak self] _ in
      UIMenu(children: [
        UIAction(
          title: "选择标签页",
          image: UIImage(systemName: "checkmark.circle")
        ) { _ in
          self?.enterSelection(selecting: tab.id)
        },
        UIAction(
          title: "复制网址",
          image: UIImage(systemName: "doc.on.doc"),
          attributes: tab.url == nil ? [.disabled] : []
        ) { _ in
          UIPasteboard.general.url = tab.url
        },
        UIAction(
          title: "关闭其他标签页",
          image: UIImage(systemName: "rectangle.stack.badge.minus")
        ) { _ in
          self?.manager.closeOtherTabs(keeping: tab.id)
          self?.collectionView.reloadData()
        },
        UIAction(
          title: "关闭标签页",
          image: UIImage(systemName: "xmark"),
          attributes: [.destructive]
        ) { _ in
          self?.manager.closeTab(id: tab.id)
          self?.collectionView.reloadData()
        },
      ])
    }
  }
}

extension BrowserTabSwitcherViewController:
  UICollectionViewDragDelegate,
  UICollectionViewDropDelegate
{
  func collectionView(
    _ collectionView: UICollectionView,
    itemsForBeginning session: UIDragSession,
    at indexPath: IndexPath
  ) -> [UIDragItem] {
    let tab = tabs(in: indexPath.section)[indexPath.item]
    let provider = NSItemProvider(object: tab.id.uuidString as NSString)
    let item = UIDragItem(itemProvider: provider)
    item.localObject = tab.id
    return [item]
  }

  func collectionView(
    _ collectionView: UICollectionView,
    dropSessionDidUpdate session: UIDropSession,
    withDestinationIndexPath destinationIndexPath: IndexPath?
  ) -> UICollectionViewDropProposal {
    guard session.localDragSession != nil else {
      return UICollectionViewDropProposal(operation: .forbidden)
    }
    return UICollectionViewDropProposal(
      operation: .move,
      intent: .insertAtDestinationIndexPath
    )
  }

  func collectionView(
    _ collectionView: UICollectionView,
    performDropWith coordinator: UICollectionViewDropCoordinator
  ) {
    guard let item = coordinator.items.first,
          let sourcePath = item.sourceIndexPath,
          let destinationPath = coordinator.destinationIndexPath,
          sourcePath.section == destinationPath.section,
          let sourceID = item.dragItem.localObject as? UUID
    else {
      return
    }
    let destinationTabs = tabs(in: destinationPath.section)
    guard !destinationTabs.isEmpty else { return }
    let destinationIndex = min(
      destinationPath.item,
      destinationTabs.count - 1
    )
    manager.moveTab(
      id: sourceID,
      before: destinationTabs[destinationIndex].id
    )
    collectionView.reloadData()
  }
}

private final class BrowserTabSectionHeader: UICollectionReusableView {
  static let reuseIdentifier = "BrowserTabSectionHeader"
  private let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .preferredFont(forTextStyle: .headline)
    label.adjustsFontForContentSizeCategory = true
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String, count: Int, isPrivate: Bool) {
    label.text = "\(title)  \(count)"
    label.textColor = isPrivate ? .systemPurple : .label
  }
}

private final class BrowserTabCell: UICollectionViewCell {
  static let reuseIdentifier = "BrowserTabCell"

  private let imageView = UIImageView()
  private let titleLabel = UILabel()
  private let domainLabel = UILabel()
  private let privateBadge = UILabel()
  private let closeButton = UIButton(type: .system)
  private var onClose: (() -> Void)?

  override var isSelected: Bool {
    didSet {
      contentView.alpha = isSelected ? 0.62 : 1
      accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    configureView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureView()
  }

  func configure(
    tab: BrowserTab,
    isSelectedTab: Bool,
    onClose: @escaping () -> Void
  ) {
    imageView.image = tab.screenshot ?? UIImage(systemName: "globe")
    imageView.contentMode = tab.screenshot == nil ? .center : .scaleAspectFill
    titleLabel.text = tab.title
    domainLabel.text = tab.url?.host ?? "新标签页"
    privateBadge.isHidden = !tab.isPrivate
    layer.borderWidth = isSelectedTab ? 2 : 0
    layer.borderColor = UIColor.systemBlue.cgColor
    accessibilityValue = isSelectedTab ? "当前标签页" : nil
    self.onClose = onClose
  }

  private func configureView() {
    backgroundColor = .secondarySystemGroupedBackground
    layer.cornerRadius = 20
    layer.cornerCurve = .continuous
    clipsToBounds = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.backgroundColor = .tertiarySystemGroupedBackground
    imageView.tintColor = .secondaryLabel
    imageView.clipsToBounds = true

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 2

    domainLabel.translatesAutoresizingMaskIntoConstraints = false
    domainLabel.font = .preferredFont(forTextStyle: .caption1)
    domainLabel.textColor = .secondaryLabel
    domainLabel.adjustsFontForContentSizeCategory = true
    domainLabel.lineBreakMode = .byTruncatingMiddle

    privateBadge.translatesAutoresizingMaskIntoConstraints = false
    privateBadge.text = "无痕"
    privateBadge.font = .preferredFont(forTextStyle: .caption1)
    privateBadge.textColor = .systemPurple
    privateBadge.isHidden = true

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    closeButton.tintColor = .secondaryLabel
    closeButton.backgroundColor = .systemBackground.withAlphaComponent(0.75)
    closeButton.layer.cornerRadius = 18
    closeButton.addTarget(
      self,
      action: #selector(closePressed),
      for: .touchUpInside
    )

    contentView.addSubview(imageView)
    contentView.addSubview(titleLabel)
    contentView.addSubview(domainLabel)
    contentView.addSubview(privateBadge)
    contentView.addSubview(closeButton)

    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
      imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.66),
      closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
      closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
      closeButton.widthAnchor.constraint(equalToConstant: 36),
      closeButton.heightAnchor.constraint(equalToConstant: 36),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
      domainLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      domainLabel.trailingAnchor.constraint(equalTo: privateBadge.leadingAnchor, constant: -6),
      domainLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
      privateBadge.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      privateBadge.centerYAnchor.constraint(equalTo: domainLabel.centerYAnchor),
    ])
  }

  @objc private func closePressed() {
    onClose?()
  }
}
