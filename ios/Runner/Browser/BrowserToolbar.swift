import UIKit

final class BrowserToolbar: UIVisualEffectView {
  let backButton = UIButton(type: .system)
  let forwardButton = UIButton(type: .system)
  let tabsButton = UIButton(type: .system)
  let moreButton = UIButton(type: .system)

  var onBack: (() -> Void)?
  var onForward: (() -> Void)?
  var onTabs: (() -> Void)?
  var onDetect: (() -> Void)?
  var onBackHistory: (() -> Void)?
  var onForwardHistory: (() -> Void)?
  private let tabCountLabel = UILabel()
  private let resourceCountLabel = UILabel()

  init() {
    super.init(effect: UIBlurEffect(style: .systemThinMaterial))
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    effect = UIBlurEffect(style: .systemThinMaterial)
    configure()
  }

  func update(
    canGoBack: Bool,
    canGoForward: Bool,
    tabCount: Int,
    resourceCount: Int,
    isDetecting: Bool
  ) {
    backButton.isEnabled = canGoBack
    forwardButton.isEnabled = canGoForward
    tabsButton.accessibilityLabel = "标签页，共 \(tabCount) 个"
    tabCountLabel.text = tabCount > 99 ? "99+" : String(tabCount)
    resourceCountLabel.text = resourceCount > 99
      ? "99+"
      : String(resourceCount)
    resourceCountLabel.isHidden = resourceCount == 0
    moreButton.tintColor = resourceCount > 0 ? .systemBlue : .label
    moreButton.accessibilityLabel = resourceCount > 0
      ? "检测到 \(resourceCount) 个视频资源"
      : (isDetecting ? "正在检测视频" : "视频检测")
    moreButton.accessibilityValue = resourceCount > 0
      ? String(resourceCount)
      : nil
  }

  func setCollapseProgress(_ progress: CGFloat) {
    let value = min(1, max(0, progress))
    transform = CGAffineTransform(translationX: 0, y: 112 * value)
      .scaledBy(x: 1 - 0.04 * value, y: 1 - 0.04 * value)
    alpha = 1 - value
    isUserInteractionEnabled = value < 0.9
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = 18
    layer.cornerCurve = .continuous
    layer.borderWidth = 0.75
    layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.16).cgColor
    clipsToBounds = true
    contentView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.72)

    let items: [(UIButton, String, Selector, String)] = [
      (backButton, "chevron.backward", #selector(backPressed), "browser.back"),
      (forwardButton, "chevron.forward", #selector(forwardPressed), "browser.forward"),
      (tabsButton, "square.on.square", #selector(tabsPressed), "browser.tabs"),
      (moreButton, "sparkles", #selector(detectPressed), "browser.videoDetect"),
    ]
    for (button, imageName, selector, identifier) in items {
      button.setImage(UIImage(systemName: imageName), for: .normal)
      button.tintColor = .label
      button.accessibilityIdentifier = identifier
      button.addTarget(self, action: selector, for: .touchUpInside)
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }
    moreButton.accessibilityLabel = "视频检测"
    moreButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.11)
    moreButton.layer.cornerRadius = 12
    moreButton.layer.cornerCurve = .continuous

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
    resourceCountLabel.translatesAutoresizingMaskIntoConstraints = false
    resourceCountLabel.font = .monospacedDigitSystemFont(
      ofSize: 9,
      weight: .bold
    )
    resourceCountLabel.textAlignment = .center
    resourceCountLabel.textColor = .white
    resourceCountLabel.backgroundColor = .systemBlue
    resourceCountLabel.layer.cornerRadius = 7
    resourceCountLabel.layer.cornerCurve = .continuous
    resourceCountLabel.clipsToBounds = true
    resourceCountLabel.isHidden = true
    moreButton.addSubview(resourceCountLabel)
    NSLayoutConstraint.activate([
      tabCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
      tabCountLabel.heightAnchor.constraint(equalToConstant: 14),
      tabCountLabel.trailingAnchor.constraint(equalTo: tabsButton.trailingAnchor, constant: -5),
      tabCountLabel.topAnchor.constraint(equalTo: tabsButton.topAnchor, constant: 5),
      resourceCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
      resourceCountLabel.heightAnchor.constraint(equalToConstant: 14),
      resourceCountLabel.trailingAnchor.constraint(
        equalTo: moreButton.trailingAnchor,
        constant: -5
      ),
      resourceCountLabel.topAnchor.constraint(
        equalTo: moreButton.topAnchor,
        constant: 5
      ),
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
  @objc private func detectPressed() { onDetect?() }

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
