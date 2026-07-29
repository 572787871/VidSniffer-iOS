import UIKit

final class AddressBarView: UIView, UITextFieldDelegate {
  let textField = UITextField()
  let progressView = UIProgressView(progressViewStyle: .bar)
  private let securityImageView = UIImageView()
  private let clearButton = UIButton(type: .system)

  var onSubmit: ((String) -> Void)?
  var onLongPress: (() -> Void)?

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
    textField.adjustsFontForContentSizeCategory = true
    textField.font = .preferredFont(forTextStyle: .body)
    textField.addTarget(
      self,
      action: #selector(textDidChange),
      for: .editingChanged
    )

    clearButton.translatesAutoresizingMaskIntoConstraints = false
    clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    clearButton.tintColor = .tertiaryLabel
    clearButton.addTarget(self, action: #selector(clearText), for: .touchUpInside)

    progressView.translatesAutoresizingMaskIntoConstraints = false
    progressView.tintColor = .systemBlue
    progressView.trackTintColor = .clear
    progressView.isHidden = true

    addSubview(securityImageView)
    addSubview(textField)
    addSubview(clearButton)
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
      clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      clearButton.widthAnchor.constraint(equalToConstant: 30),
      clearButton.heightAnchor.constraint(equalToConstant: 30),
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
}
