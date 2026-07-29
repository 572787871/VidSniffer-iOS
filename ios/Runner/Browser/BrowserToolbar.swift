import UIKit

final class BrowserToolbar: UIVisualEffectView {
  let backButton = UIButton(type: .system)
  let forwardButton = UIButton(type: .system)
  let homeButton = UIButton(type: .system)
  let shareButton = UIButton(type: .system)
  let tabsButton = UIButton(type: .system)

  var onBack: (() -> Void)?
  var onForward: (() -> Void)?
  var onHome: (() -> Void)?
  var onShare: (() -> Void)?
  var onTabs: (() -> Void)?
  var onBackHistory: (() -> Void)?
  var onForwardHistory: (() -> Void)?

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
    tabCountLabel.text = String(tabCount)
    tabCountLabel.isHidden = tabCount > 99
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = 24
    layer.cornerCurve = .continuous
    clipsToBounds = true

    let items: [(UIButton, String, Selector)] = [
      (backButton, "chevron.backward", #selector(backPressed)),
      (forwardButton, "chevron.forward", #selector(forwardPressed)),
      (homeButton, "house.fill", #selector(homePressed)),
      (shareButton, "square.and.arrow.up", #selector(sharePressed)),
      (tabsButton, "square.on.square", #selector(tabsPressed)),
    ]
    for (button, imageName, selector) in items {
      button.setImage(UIImage(systemName: imageName), for: .normal)
      button.tintColor = .label
      button.addTarget(self, action: selector, for: .touchUpInside)
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
    backButton.addGestureRecognizer(
      UILongPressGestureRecognizer(
        target: self,
        action: #selector(backLongPressed)
      )
    )
    forwardButton.addGestureRecognizer(
      UILongPressGestureRecognizer(
        target: self,
        action: #selector(forwardLongPressed)
      )
    )

    tabCountLabel.translatesAutoresizingMaskIntoConstraints = false
    tabCountLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    tabCountLabel.textAlignment = .center
    tabCountLabel.textColor = .label
    tabCountLabel.backgroundColor = .systemBackground
    tabCountLabel.layer.cornerRadius = 7
    tabCountLabel.layer.cornerCurve = .continuous
    tabCountLabel.clipsToBounds = true
    tabsButton.addSubview(tabCountLabel)
    NSLayoutConstraint.activate([
      tabCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
      tabCountLabel.heightAnchor.constraint(equalToConstant: 14),
      tabCountLabel.trailingAnchor.constraint(equalTo: tabsButton.trailingAnchor, constant: -2),
      tabCountLabel.topAnchor.constraint(equalTo: tabsButton.topAnchor, constant: 2),
    ])

    let stack = UIStackView(arrangedSubviews: items.map(\.0))
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.distribution = .equalSpacing
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
    ])
  }

  @objc private func backPressed() { onBack?() }
  @objc private func forwardPressed() { onForward?() }
  @objc private func homePressed() { onHome?() }
  @objc private func sharePressed() { onShare?() }
  @objc private func tabsPressed() { onTabs?() }

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
