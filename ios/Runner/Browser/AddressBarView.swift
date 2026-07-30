import UIKit

final class AddressBarView: UIView, UITextFieldDelegate {
  let textField = UITextField()
  let progressView = UIProgressView(progressViewStyle: .bar)
  let detectButton = UIButton(type: .system)
  let userButton = UIButton(type: .system)

  private let addressMaterial = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemChromeMaterial)
  )
  private let detectMaterial = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemChromeMaterial)
  )
  private let userMaterial = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemChromeMaterial)
  )
  private let securityImageView = UIImageView()
  private let trailingButton = UIButton(type: .system)
  private let countLabel = UILabel()

  var onSubmit: ((String) -> Void)?
  var onLongPress: (() -> Void)?
  var onPaste: (() -> Void)?
  var onReloadOrStop: (() -> Void)?
  var onUser: (() -> Void)?
  var onFocus: (() -> Void)?
  var pageMenu: UIMenu? {
    didSet { detectButton.menu = pageMenu }
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
      systemName: isSecure ? "lock.fill" : "magnifyingglass"
    )
    progressView.setProgress(Float(progress), animated: true)
    progressView.isHidden = !isLoading || progress >= 1
    updateTrailingButton(isLoading: isLoading)
  }

  func updateDetectedResourceCount(_ count: Int, isLoading: Bool) {
    countLabel.isHidden = true
  }

  func setCollapseProgress(_ progress: CGFloat) {
    let value = min(1, max(0, progress))
    detectMaterial.alpha = 1 - value
    userMaterial.alpha = 1 - value
    detectMaterial.transform = CGAffineTransform(
      translationX: -12 * value,
      y: -3 * value
    ).scaledBy(x: 1 - 0.18 * value, y: 1 - 0.18 * value)
    userMaterial.transform = CGAffineTransform(
      translationX: 12 * value,
      y: -3 * value
    ).scaledBy(x: 1 - 0.18 * value, y: 1 - 0.18 * value)
    addressMaterial.transform = CGAffineTransform(
      translationX: 0,
      y: -5 * value
    ).scaledBy(x: 1 - 0.34 * value, y: 1 - 0.18 * value)
    addressMaterial.layer.cornerRadius = 18 - (3 * value)
    detectMaterial.isUserInteractionEnabled = value < 0.9
    userMaterial.isUserInteractionEnabled = value < 0.9
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .clear

    [addressMaterial, detectMaterial, userMaterial].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      $0.layer.cornerCurve = .continuous
      $0.clipsToBounds = true
      addSubview($0)
    }
    addressMaterial.layer.cornerRadius = 18
    detectMaterial.layer.cornerRadius = 22
    userMaterial.layer.cornerRadius = 22

    detectButton.translatesAutoresizingMaskIntoConstraints = false
    detectButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
    detectButton.tintColor = .label
    detectButton.accessibilityIdentifier = "browser.more"
    detectButton.accessibilityLabel = "更多"
    detectButton.showsMenuAsPrimaryAction = true
    detectMaterial.contentView.addSubview(detectButton)

    countLabel.translatesAutoresizingMaskIntoConstraints = false
    countLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    countLabel.textColor = .white
    countLabel.textAlignment = .center
    countLabel.backgroundColor = .systemBlue
    countLabel.layer.cornerRadius = 7
    countLabel.layer.cornerCurve = .continuous
    countLabel.clipsToBounds = true
    countLabel.isHidden = true
    detectMaterial.contentView.addSubview(countLabel)

    securityImageView.translatesAutoresizingMaskIntoConstraints = false
    securityImageView.tintColor = .secondaryLabel
    securityImageView.contentMode = .scaleAspectFit
    addressMaterial.contentView.addSubview(securityImageView)

    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.delegate = self
    textField.autocapitalizationType = .none
    textField.autocorrectionType = .no
    textField.keyboardType = .webSearch
    textField.returnKeyType = .go
    textField.placeholder = "搜索或输入网址"
    textField.accessibilityIdentifier = "browser.addressField"
    textField.adjustsFontForContentSizeCategory = true
    textField.font = .preferredFont(forTextStyle: .body)
    textField.clearButtonMode = .never
    textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
    addressMaterial.contentView.addSubview(textField)

    trailingButton.translatesAutoresizingMaskIntoConstraints = false
    trailingButton.tintColor = .secondaryLabel
    trailingButton.addTarget(
      self,
      action: #selector(trailingPressed),
      for: .touchUpInside
    )
    addressMaterial.contentView.addSubview(trailingButton)

    progressView.translatesAutoresizingMaskIntoConstraints = false
    progressView.tintColor = .systemBlue
    progressView.trackTintColor = .clear
    progressView.isHidden = true
    addressMaterial.contentView.addSubview(progressView)

    userButton.translatesAutoresizingMaskIntoConstraints = false
    userButton.setImage(UIImage(systemName: "person.crop.circle.fill"), for: .normal)
    userButton.tintColor = .label
    userButton.accessibilityLabel = "用户中心"
    userButton.accessibilityIdentifier = "browser.user"
    userButton.addTarget(self, action: #selector(userPressed), for: .touchUpInside)
    userMaterial.contentView.addSubview(userButton)

    addressMaterial.addGestureRecognizer(
      UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
    )

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 48),
      detectMaterial.leadingAnchor.constraint(equalTo: leadingAnchor),
      detectMaterial.centerYAnchor.constraint(equalTo: centerYAnchor),
      detectMaterial.widthAnchor.constraint(equalToConstant: 44),
      detectMaterial.heightAnchor.constraint(equalToConstant: 44),
      detectButton.leadingAnchor.constraint(equalTo: detectMaterial.contentView.leadingAnchor),
      detectButton.trailingAnchor.constraint(equalTo: detectMaterial.contentView.trailingAnchor),
      detectButton.topAnchor.constraint(equalTo: detectMaterial.contentView.topAnchor),
      detectButton.bottomAnchor.constraint(equalTo: detectMaterial.contentView.bottomAnchor),
      countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
      countLabel.heightAnchor.constraint(equalToConstant: 14),
      countLabel.trailingAnchor.constraint(equalTo: detectMaterial.trailingAnchor, constant: -1),
      countLabel.topAnchor.constraint(equalTo: detectMaterial.topAnchor, constant: 1),

      addressMaterial.leadingAnchor.constraint(
        equalTo: detectMaterial.trailingAnchor,
        constant: 8
      ),
      addressMaterial.centerYAnchor.constraint(equalTo: centerYAnchor),
      addressMaterial.heightAnchor.constraint(equalToConstant: 44),
      addressMaterial.trailingAnchor.constraint(
        equalTo: userMaterial.leadingAnchor,
        constant: -8
      ),
      securityImageView.leadingAnchor.constraint(
        equalTo: addressMaterial.contentView.leadingAnchor,
        constant: 13
      ),
      securityImageView.centerYAnchor.constraint(
        equalTo: addressMaterial.contentView.centerYAnchor
      ),
      securityImageView.widthAnchor.constraint(equalToConstant: 16),
      securityImageView.heightAnchor.constraint(equalToConstant: 16),
      textField.leadingAnchor.constraint(
        equalTo: securityImageView.trailingAnchor,
        constant: 8
      ),
      textField.trailingAnchor.constraint(
        equalTo: trailingButton.leadingAnchor,
        constant: -4
      ),
      textField.topAnchor.constraint(equalTo: addressMaterial.contentView.topAnchor),
      textField.bottomAnchor.constraint(equalTo: addressMaterial.contentView.bottomAnchor),
      trailingButton.trailingAnchor.constraint(
        equalTo: addressMaterial.contentView.trailingAnchor,
        constant: -5
      ),
      trailingButton.centerYAnchor.constraint(
        equalTo: addressMaterial.contentView.centerYAnchor
      ),
      trailingButton.widthAnchor.constraint(equalToConstant: 34),
      trailingButton.heightAnchor.constraint(equalToConstant: 34),
      progressView.leadingAnchor.constraint(
        equalTo: addressMaterial.contentView.leadingAnchor,
        constant: 14
      ),
      progressView.trailingAnchor.constraint(
        equalTo: addressMaterial.contentView.trailingAnchor,
        constant: -14
      ),
      progressView.bottomAnchor.constraint(equalTo: addressMaterial.contentView.bottomAnchor),

      userMaterial.trailingAnchor.constraint(equalTo: trailingAnchor),
      userMaterial.centerYAnchor.constraint(equalTo: centerYAnchor),
      userMaterial.widthAnchor.constraint(equalToConstant: 44),
      userMaterial.heightAnchor.constraint(equalToConstant: 44),
      userButton.leadingAnchor.constraint(equalTo: userMaterial.contentView.leadingAnchor),
      userButton.trailingAnchor.constraint(equalTo: userMaterial.contentView.trailingAnchor),
      userButton.topAnchor.constraint(equalTo: userMaterial.contentView.topAnchor),
      userButton.bottomAnchor.constraint(equalTo: userMaterial.contentView.bottomAnchor),
    ])
    updateTrailingButton(isLoading: false)
  }

  private func updateTrailingButton(isLoading: Bool) {
    let isEditingWithText = textField.isFirstResponder
      && textField.text?.isEmpty == false
    let symbol = isEditingWithText
      ? "xmark.circle.fill"
      : (isLoading ? "xmark" : "arrow.clockwise")
    trailingButton.setImage(UIImage(systemName: symbol), for: .normal)
    trailingButton.accessibilityLabel = isEditingWithText
      ? "清除地址"
      : (isLoading ? "停止载入" : "重新载入")
    trailingButton.accessibilityIdentifier = isEditingWithText
      ? "browser.clearAddress"
      : "browser.reload"
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    onSubmit?(textField.text ?? "")
    textField.resignFirstResponder()
    updateTrailingButton(isLoading: false)
    return true
  }

  func textFieldDidBeginEditing(_ textField: UITextField) {
    onFocus?()
    textField.selectAll(nil)
    updateTrailingButton(isLoading: false)
  }

  func textFieldDidEndEditing(_ textField: UITextField) {
    updateTrailingButton(isLoading: false)
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
    ) { [weak self] _ in self?.onPaste?() }
    return UIMenu(children: [pasteAndGo] + suggestedActions)
  }

  @objc private func textDidChange() {
    updateTrailingButton(isLoading: false)
  }

  @objc private func trailingPressed() {
    if textField.isFirstResponder, textField.text?.isEmpty == false {
      textField.text = ""
      updateTrailingButton(isLoading: false)
      return
    }
    onReloadOrStop?()
  }

  @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    onLongPress?()
  }

  @objc private func userPressed() { onUser?() }
}
