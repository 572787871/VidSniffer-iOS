import UIKit

final class AddressBarView: UIView, UITextFieldDelegate {
  let textField = UITextField()
  let progressView = UIProgressView(progressViewStyle: .bar)
  private let securityImageView = UIImageView()
  private let clearButton = UIButton(type: .system)
  private let scanButton = UIButton(type: .system)
  private let reloadButton = UIButton(type: .system)
  private let tabButton = UIButton(type: .system)
  private let moreButton = UIButton(type: .system)

  var onSubmit: ((String) -> Void)?
  var onLongPress: (() -> Void)?
  var onPaste: (() -> Void)?
  var onScan: (() -> Void)?
  var onReloadOrStop: (() -> Void)?
  var onTabs: (() -> Void)?
  var pageMenu: UIMenu? {
    didSet { moreButton.menu = pageMenu }
  }

  func updateTabCount(_ count: Int, isPrivate: Bool) {
    tabButton.setTitle("\(count)", for: .normal)
    tabButton.tintColor = isPrivate ? .systemPurple : .label
    tabButton.accessibilityValue = "\(count) 个标签页"
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  func update(
    text: String,
    isSecure: Bool,
    progress: Double,
    isLoading: Bool
  ) {
    if !textField.isFirstResponder {
      textField.text = text
    }
    securityImageView.image = UIImage(
      systemName: isSecure ? "lock.fill" : "globe"
    )
    progressView.setProgress(Float(progress), animated: true)
    progressView.isHidden = !isLoading || progress >= 1
    clearButton.isHidden = textField.text?.isEmpty != false
    reloadButton.setImage(
      UIImage(systemName: isLoading ? "xmark" : "arrow.clockwise"),
      for: .normal
    )
    reloadButton.accessibilityLabel = isLoading ? "停止载入" : "重新载入"
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .secondarySystemGroupedBackground
    layer.cornerRadius = 16
    layer.cornerCurve = .continuous

    securityImageView.translatesAutoresizingMaskIntoConstraints = false
    securityImageView.tintColor = .secondaryLabel
    securityImageView.contentMode = .scaleAspectFit

    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.delegate = self
    textField.autocapitalizationType = .none
    textField.autocorrectionType = .no
    textField.clearButtonMode = .never
    textField.keyboardType = .webSearch
    textField.returnKeyType = .go
    textField.placeholder = "搜索或输入网址"
    textField.accessibilityIdentifier = "browser.addressField"
    textField.adjustsFontForContentSizeCategory = true
    textField.font = .preferredFont(forTextStyle: .body)
    textField.addTarget(
      self,
      action: #selector(textDidChange),
      for: .editingChanged
    )

    clearButton.translatesAutoresizingMaskIntoConstraints = false
    clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    clearButton.accessibilityIdentifier = "browser.clearAddress"
    clearButton.tintColor = .tertiaryLabel
    clearButton.addTarget(self, action: #selector(clearText), for: .touchUpInside)

    scanButton.translatesAutoresizingMaskIntoConstraints = false
    scanButton.setImage(UIImage(systemName: "qrcode.viewfinder"), for: .normal)
    scanButton.tintColor = .secondaryLabel
    scanButton.accessibilityLabel = "扫描二维码"
    scanButton.accessibilityIdentifier = "browser.scanQRCode"
    scanButton.addTarget(self, action: #selector(scanPressed), for: .touchUpInside)

    reloadButton.translatesAutoresizingMaskIntoConstraints = false
    reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
    reloadButton.tintColor = .secondaryLabel
    reloadButton.accessibilityLabel = "重新载入"
    reloadButton.accessibilityIdentifier = "browser.reload"
    reloadButton.addTarget(
      self,
      action: #selector(reloadPressed),
      for: .touchUpInside
    )

    tabButton.translatesAutoresizingMaskIntoConstraints = false
    tabButton.titleLabel?.font = .monospacedDigitSystemFont(
      ofSize: 14,
      weight: .semibold
    )
    tabButton.setTitleColor(.label, for: .normal)
    tabButton.layer.borderWidth = 1.5
    tabButton.layer.borderColor = UIColor.secondaryLabel.cgColor
    tabButton.layer.cornerRadius = 7
    tabButton.accessibilityLabel = "打开标签页"
    tabButton.accessibilityIdentifier = "browser.tabCount"
    tabButton.addTarget(self, action: #selector(tabsPressed), for: .touchUpInside)

    moreButton.translatesAutoresizingMaskIntoConstraints = false
    moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
    moreButton.tintColor = .label
    moreButton.showsMenuAsPrimaryAction = true
    moreButton.accessibilityLabel = "更多"
    moreButton.accessibilityIdentifier = "browser.more"

    progressView.translatesAutoresizingMaskIntoConstraints = false
    progressView.tintColor = .systemBlue
    progressView.trackTintColor = .clear
    progressView.isHidden = true

    addSubview(securityImageView)
    addSubview(textField)
    addSubview(clearButton)
    addSubview(scanButton)
    addSubview(reloadButton)
    addSubview(tabButton)
    addSubview(moreButton)
    addSubview(progressView)
    addGestureRecognizer(
      UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
    )

    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
      securityImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      securityImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      securityImageView.widthAnchor.constraint(equalToConstant: 18),
      securityImageView.heightAnchor.constraint(equalToConstant: 18),
      textField.leadingAnchor.constraint(equalTo: securityImageView.trailingAnchor, constant: 10),
      textField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6),
      textField.topAnchor.constraint(equalTo: topAnchor, constant: 7),
      textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
      clearButton.trailingAnchor.constraint(equalTo: scanButton.leadingAnchor, constant: -2),
      clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      clearButton.widthAnchor.constraint(equalToConstant: 30),
      clearButton.heightAnchor.constraint(equalToConstant: 30),
      scanButton.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -2),
      scanButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      scanButton.widthAnchor.constraint(equalToConstant: 34),
      scanButton.heightAnchor.constraint(equalToConstant: 34),
      reloadButton.trailingAnchor.constraint(equalTo: tabButton.leadingAnchor, constant: -2),
      reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      reloadButton.widthAnchor.constraint(equalToConstant: 34),
      reloadButton.heightAnchor.constraint(equalToConstant: 34),
      tabButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
      tabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      tabButton.widthAnchor.constraint(equalToConstant: 28),
      tabButton.heightAnchor.constraint(equalToConstant: 28),
      moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      moreButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      moreButton.widthAnchor.constraint(equalToConstant: 34),
      moreButton.heightAnchor.constraint(equalToConstant: 34),
      progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      progressView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    onSubmit?(textField.text ?? "")
    textField.resignFirstResponder()
    return true
  }

  func textFieldDidBeginEditing(_ textField: UITextField) {
    textField.selectAll(nil)
  }

  @available(iOS 16.0, *)
  func textField(
    _ textField: UITextField,
    editMenuForCharactersIn range: NSRange,
    suggestedActions: [UIMenuElement]
  ) -> UIMenu? {
    let pasteAndGo = UIAction(
      title: "粘贴并访问",
      image: UIImage(systemName: "doc.on.clipboard")
    ) { [weak self] _ in
      self?.onPaste?()
    }
    return UIMenu(children: [pasteAndGo] + suggestedActions)
  }

  @objc private func clearText() {
    textField.text = ""
    textDidChange()
    textField.becomeFirstResponder()
  }

  @objc private func textDidChange() {
    clearButton.isHidden = textField.text?.isEmpty != false
  }

  @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    onLongPress?()
  }

  @objc private func scanPressed() {
    onScan?()
  }

  @objc private func reloadPressed() {
    onReloadOrStop?()
  }

  @objc private func tabsPressed() {
    onTabs?()
  }
}
