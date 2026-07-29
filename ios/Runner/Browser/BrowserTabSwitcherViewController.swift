import UIKit

final class BrowserTabSwitcherViewController: UIViewController {
  private let manager: BrowserTabManager
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
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .add,
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        let tab = self.manager.createTab()
        self.collectionView.reloadData()
        self.onSelectTab?(tab.id)
      }
    )

    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.backgroundColor = .clear
    collectionView.alwaysBounceVertical = true
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.register(
      BrowserTabCell.self,
      forCellWithReuseIdentifier: BrowserTabCell.reuseIdentifier
    )
    view.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func makeLayout() -> UICollectionViewLayout {
    let layout = UICollectionViewFlowLayout()
    layout.sectionInset = UIEdgeInsets(top: 18, left: 18, bottom: 32, right: 18)
    layout.minimumInteritemSpacing = 14
    layout.minimumLineSpacing = 14
    return layout
  }
}

extension BrowserTabSwitcherViewController:
  UICollectionViewDataSource,
  UICollectionViewDelegateFlowLayout
{
  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    manager.tabs.count
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
    let tab = manager.tabs[indexPath.item]
    cell.configure(tab: tab) { [weak self, weak collectionView] in
      self?.manager.closeTab(id: tab.id)
      collectionView?.reloadData()
    }
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    onSelectTab?(manager.tabs[indexPath.item].id)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    let width = max(160, (collectionView.bounds.width - 50) / 2)
    return CGSize(width: width, height: width * 1.28)
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

  override init(frame: CGRect) {
    super.init(frame: frame)
    configureView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureView()
  }

  func configure(tab: BrowserTab, onClose: @escaping () -> Void) {
    imageView.image = tab.screenshot ?? UIImage(systemName: "globe")
    imageView.contentMode = tab.screenshot == nil ? .center : .scaleAspectFill
    titleLabel.text = tab.title
    domainLabel.text = tab.url?.host ?? "新标签页"
    privateBadge.isHidden = !tab.isPrivate
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

    privateBadge.translatesAutoresizingMaskIntoConstraints = false
    privateBadge.text = "无痕"
    privateBadge.font = .preferredFont(forTextStyle: .caption1)
    privateBadge.textColor = .systemPurple
    privateBadge.isHidden = true

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    closeButton.tintColor = .secondaryLabel
    closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)

    contentView.addSubview(imageView)
    contentView.addSubview(titleLabel)
    contentView.addSubview(domainLabel)
    contentView.addSubview(privateBadge)
    contentView.addSubview(closeButton)

    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
      imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.64),
      closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
      closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
      closeButton.widthAnchor.constraint(equalToConstant: 36),
      closeButton.heightAnchor.constraint(equalToConstant: 36),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
      domainLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      domainLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
      privateBadge.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      privateBadge.centerYAnchor.constraint(equalTo: domainLabel.centerYAnchor),
    ])
  }

  @objc private func closePressed() {
    onClose?()
  }
}
