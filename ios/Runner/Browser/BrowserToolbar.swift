import UIKit

final class BrowserToolbar: UIVisualEffectView {
  let backButton = UIButton(type: .system)
  let forwardButton = UIButton(type: .system)
  let tabsButton = UIButton(type: .system)
  let moreButton = UIButton(type: .system)

  var onBack: (() -> Void)?
  var onForward: (() -> Void)?
  var onTabs: (() -> Void)?
  var onBackHistory: (() -> Void)?
  var onForwardHistory: (() -> Void)?
  var pageMenu: UIMenu? {
    didSet { moreButton.menu = pageMenu }
  }

  private let tabCountLabel = UILabel()

  init() {
    super.init(effect: UIBlurEffect(style: .systemChromeMaterial))
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    effect = UIBlurEffect(style: .systemChromeMaterial)
    configure()
  }

  func update(canGoBack: Bool, canGoForward: Bool, tabCount: Int) {
    backButton.isEnabled = canGoBack
    forwardButton.isEnabled = canGoForward
    tabsButton.accessibilityLabel = "标签页，共 \(tabCount) 个"
    tabCountLabel.text = tabCount > 99 ? "99+" : String(tabCount)
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = 26
    layer.cornerCurve = .continuous
    clipsToBounds = true

    let items: [(UIButton, String, Selector, String)] = [
      (backButton, "chevron.backward", #selector(backPressed), "browser.back"),
      (forwardButton, "chevron.forward", #selector(forwardPressed), "browser.forward"),
      (tabsButton, "square.on.square", #selector(tabsPressed), "browser.tabs"),
      (moreButton, "ellipsis", #selector(noop), "browser.more"),
    ]
    for (button, imageName, selector, identifier) in items {
      button.setImage(UIImage(systemName: imageName), for: .normal)
      button.tintColor = .label
      button.accessibilityIdentifier = identifier
      button.addTarget(self, action: selector, for: .touchUpInside)
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }
    moreButton.showsMenuAsPrimaryAction = true
    moreButton.accessibilityLabel = "更多"

    backButton.addGestureRecognizer(
      UILongPressGestureRecognizer(target: self, action: #selector(backLongPressed))
    )
    forwardButton.addGestureRecognizer(
      UILongPressGestureRecognizer(target: self, action: #selector(forwardLongPressed))
    )

    tabCountLabel.translatesAutoresizingMaskIntoConstraints = false
    tabCountLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    tabCountLabel.textAlignment = .center
    tabCountLabel.textColor = .label
    tabCountLabel.backgroundColor = .secondarySystemBackground
    tabCountLabel.layer.cornerRadius = 7
    tabCountLabel.layer.cornerCurve = .continuous
    tabCountLabel.clipsToBounds = true
    tabsButton.addSubview(tabCountLabel)
    NSLayoutConstraint.activate([
      tabCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
      tabCountLabel.heightAnchor.constraint(equalToConstant: 14),
      tabCountLabel.trailingAnchor.constraint(equalTo: tabsButton.trailingAnchor, constant: -5),
      tabCountLabel.topAnchor.constraint(equalTo: tabsButton.topAnchor, constant: 5),
    ])

    let stack = UIStackView(arrangedSubviews: items.map(\.0))
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.distribution = .equalSpacing
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
    ])
  }

  @objc private func backPressed() { onBack?() }
  @objc private func forwardPressed() { onForward?() }
  @objc private func tabsPressed() { onTabs?() }
  @objc private func noop() {}

  @objc private func backLongPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    onBackHistory?()
  }

  @objc private func forwardLongPressed(
    _ recognizer: UILongPressGestureRecognizer
  ) {
    guard recognizer.state == .began else { return }
    onForwardHistory?()
  }
}
