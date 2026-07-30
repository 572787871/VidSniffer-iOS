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
  var onDownloads: (() -> Void)?
  var onFocus: (() -> Void)?
  var onBlur: (() -> Void)?
  private var expandedText = ""
  private var compactText = ""
  private var collapseProgress: CGFloat = 0

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
      expandedText = text
      compactText = URL(string: text)?.host ?? text
      textField.text = collapseProgress > 0.72 ? compactText : expandedText
    }
    securityImageView.image = UIImage(
      systemName: isSecure ? "lock.fill" : "magnifyingglass"
    )
    progressView.setProgress(Float(progress), animated: true)
    progressView.isHidden = !isLoading || progress >= 1
    updateTrailingButton(isLoading: isLoading)
  }

  func updateDetectedResourceCount(_ count: Int, isLoading: Bool) {
    // Video resources are surfaced from the bottom detection control.
  }

  func updateDownloadCount(_ count: Int) {
    countLabel.text = count > 99 ? "99+" : "\(count)"
    countLabel.isHidden = count == 0
    userButton.accessibilityValue = count == 0 ? nil : "\(count) 个进行中的任务"
  }

  func setCollapseProgress(_ progress: CGFloat) {
    // The address rail remains visible while the page scrolls. Only the
    // bottom browsing controls collapse so the current URL and downloads
    // are always reachable.
    collapseProgress = 0
    if !textField.isFirstResponder {
      textField.text = expandedText
      textField.textAlignment = .left
    }
    [detectMaterial, userMaterial, addressMaterial].forEach {
      $0.alpha = 1
      $0.transform = .identity
      $0.isUserInteractionEnabled = true
    }
  }

  func setPageThemeColor(_ color: UIColor?, collapseProgress: CGFloat) {
    addressMaterial.contentView.backgroundColor = .secondarySystemBackground
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
    addressMaterial.layer.cornerRadius = 15
    detectMaterial.layer.cornerRadius = 15
    userMaterial.layer.cornerRadius = 15
    [addressMaterial, detectMaterial, userMaterial].forEach {
      $0.layer.borderWidth = 0.75
      $0.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.16).cgColor
    }
    detectMaterial.contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.10)
    addressMaterial.contentView.backgroundColor = .secondarySystemBackground
    userMaterial.contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.10)

    detectButton.translatesAutoresizingMaskIntoConstraints = false
    detectButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
    detectButton.tintColor = .systemBlue
    detectButton.accessibilityIdentifier = "browser.user"
    detectButton.accessibilityLabel = "用户中心"
    detectButton.addTarget(self, action: #selector(userPressed), for: .touchUpInside)
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
    userMaterial.contentView.addSubview(countLabel)

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
    userButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
    userButton.tintColor = .systemBlue
    userButton.accessibilityLabel = "下载中心"
    userButton.accessibilityIdentifier = "browser.downloadCenter"
    userButton.addTarget(self, action: #selector(downloadsPressed), for: .touchUpInside)
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
      countLabel.trailingAnchor.constraint(equalTo: userMaterial.trailingAnchor, constant: 2),
      countLabel.topAnchor.constraint(equalTo: userMaterial.topAnchor, constant: -2),

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
    onBlur?()
    textField.textAlignment = collapseProgress > 0.72 ? .center : .left
    textField.text = collapseProgress > 0.72 ? compactText : expandedText
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

  @objc private func downloadsPressed() { onDownloads?() }
}
