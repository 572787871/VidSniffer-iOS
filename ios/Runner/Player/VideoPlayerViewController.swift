import AVFoundation
import AVKit
import MediaPlayer
import UIKit

@MainActor
final class VideoPlayerViewController: UIViewController {
  private let libraryManager: LibraryManager
  private var file: LibraryFile
  private let player: AVPlayer
  private let playerView = PlayerSurfaceView()
  private let controlsView = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
  )
  private let titleLabel = UILabel()
  private let currentLabel = UILabel()
  private let durationLabel = UILabel()
  private let slider = UISlider()
  private let playButton = UIButton(type: .system)
  private let backwardButton = UIButton(type: .system)
  private let forwardButton = UIButton(type: .system)
  private let speedButton = UIButton(type: .system)
  private let pipButton = UIButton(type: .system)
  private let routePicker = AVRoutePickerView()
  private let volumeView = MPVolumeView(frame: .zero)
  private var timeObserver: Any?
  private var pictureInPictureController: AVPictureInPictureController?
  private var isSeeking = false
  private var gestureStartBrightness: CGFloat = 0
  private var gestureStartVolume: Float = 0

  init(
    file: LibraryFile,
    libraryManager: LibraryManager = .shared
  ) {
    self.file = file
    self.libraryManager = libraryManager
    player = AVPlayer(url: libraryManager.url(for: file))
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureAudioSession()
    configurePlayer()
    configureControls()
    configureGestures()
    UIApplication.shared.isIdleTimerDisabled = true
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if file.playbackPosition > 0 {
      player.seek(
        to: CMTime(seconds: file.playbackPosition, preferredTimescale: 600)
      )
    }
    player.play()
    updatePlayButton()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    savePlaybackPosition()
    if isBeingDismissed || navigationController?.isBeingDismissed == true {
      player.pause()
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }

  private func configureAudioSession() {
    try? AVAudioSession.sharedInstance().setCategory(
      .playback,
      mode: .moviePlayback,
      options: [.allowAirPlay, .allowBluetooth]
    )
    try? AVAudioSession.sharedInstance().setActive(true)
  }

  private func configurePlayer() {
    playerView.translatesAutoresizingMaskIntoConstraints = false
    playerView.playerLayer.player = player
    playerView.playerLayer.videoGravity = .resizeAspect
    view.addSubview(playerView)
    NSLayoutConstraint.activate([
      playerView.topAnchor.constraint(equalTo: view.topAnchor),
      playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    if AVPictureInPictureController.isPictureInPictureSupported() {
      pictureInPictureController = AVPictureInPictureController(
        playerLayer: playerView.playerLayer
      )
    }
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      self?.updateTime(time)
    }
  }

  private func configureControls() {
    controlsView.translatesAutoresizingMaskIntoConstraints = false
    controlsView.layer.cornerRadius = 20
    controlsView.clipsToBounds = true
    controlsView.accessibilityViewIsModal = false

    titleLabel.text = file.displayName
    titleLabel.textColor = .white
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 1

    [currentLabel, durationLabel].forEach {
      $0.textColor = .white.withAlphaComponent(0.82)
      $0.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    }
    currentLabel.text = "00:00"
    durationLabel.text = "--:--"
    durationLabel.textAlignment = .right

    slider.minimumTrackTintColor = .systemBlue
    slider.maximumTrackTintColor = .white.withAlphaComponent(0.28)
    slider.addTarget(self, action: #selector(seekStarted), for: .touchDown)
    slider.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
    slider.addTarget(
      self,
      action: #selector(seekEnded),
      for: [.touchUpInside, .touchUpOutside, .touchCancel]
    )

    configureButton(playButton, symbol: "pause.fill", label: "暂停")
    configureButton(backwardButton, symbol: "gobackward.15", label: "后退 15 秒")
    configureButton(forwardButton, symbol: "goforward.15", label: "快进 15 秒")
    configureButton(pipButton, symbol: "pip.enter", label: "画中画")
    speedButton.configuration = .plain()
    speedButton.configuration?.title = "1.0×"
    speedButton.configuration?.baseForegroundColor = .white
    speedButton.accessibilityLabel = "播放速度"
    speedButton.showsMenuAsPrimaryAction = true
    speedButton.menu = makeSpeedMenu()

    playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() },
                         for: .touchUpInside)
    backwardButton.addAction(UIAction { [weak self] _ in self?.skip(-15) },
                             for: .touchUpInside)
    forwardButton.addAction(UIAction { [weak self] _ in self?.skip(15) },
                            for: .touchUpInside)
    pipButton.addAction(UIAction { [weak self] _ in self?.togglePictureInPicture() },
                        for: .touchUpInside)

    routePicker.tintColor = .white
    routePicker.activeTintColor = .systemBlue
    routePicker.accessibilityLabel = "AirPlay"

    let closeButton = UIButton(type: .system)
    configureButton(closeButton, symbol: "xmark", label: "关闭播放器")
    closeButton.addAction(UIAction { [weak self] _ in
      self?.dismiss(animated: true)
    }, for: .touchUpInside)

    let topRow = UIStackView(arrangedSubviews: [closeButton, titleLabel, pipButton])
    topRow.axis = .horizontal
    topRow.alignment = .center
    topRow.spacing = 12
    closeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
    pipButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

    let timeRow = UIStackView(arrangedSubviews: [currentLabel, durationLabel])
    timeRow.axis = .horizontal
    timeRow.distribution = .fillEqually

    let actionRow = UIStackView(arrangedSubviews: [
      backwardButton,
      playButton,
      forwardButton,
      speedButton,
      routePicker,
    ])
    actionRow.axis = .horizontal
    actionRow.distribution = .equalCentering
    actionRow.alignment = .center
    actionRow.heightAnchor.constraint(equalToConstant: 48).isActive = true
    routePicker.widthAnchor.constraint(equalToConstant: 44).isActive = true
    routePicker.heightAnchor.constraint(equalToConstant: 44).isActive = true

    let stack = UIStackView(arrangedSubviews: [
      topRow,
      slider,
      timeRow,
      actionRow,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 8
    controlsView.contentView.addSubview(stack)
    view.addSubview(controlsView)
    NSLayoutConstraint.activate([
      controlsView.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor,
        constant: 16
      ),
      controlsView.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -16
      ),
      controlsView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -12
      ),
      stack.topAnchor.constraint(
        equalTo: controlsView.contentView.topAnchor,
        constant: 12
      ),
      stack.leadingAnchor.constraint(
        equalTo: controlsView.contentView.leadingAnchor,
        constant: 12
      ),
      stack.trailingAnchor.constraint(
        equalTo: controlsView.contentView.trailingAnchor,
        constant: -12
      ),
      stack.bottomAnchor.constraint(
        equalTo: controlsView.contentView.bottomAnchor,
        constant: -12
      ),
    ])
    volumeView.isHidden = true
    view.addSubview(volumeView)
  }

  private func configureButton(
    _ button: UIButton,
    symbol: String,
    label: String
  ) {
    button.configuration = .plain()
    button.configuration?.image = UIImage(systemName: symbol)
    button.configuration?.baseForegroundColor = .white
    button.accessibilityLabel = label
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
  }

  private func makeSpeedMenu() -> UIMenu {
    UIMenu(children: [0.5, 1, 1.25, 1.5, 2].map { speed in
      UIAction(
        title: String(format: "%.2g×", speed),
        state: abs(player.rate - Float(speed)) < 0.01 ? .on : .off
      ) { [weak self] _ in
        self?.player.rate = Float(speed)
        self?.speedButton.configuration?.title =
          String(format: "%.2g×", speed)
        self?.speedButton.menu = self?.makeSpeedMenu()
      }
    })
  }

  private func configureGestures() {
    let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
    playerView.addGestureRecognizer(tap)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    playerView.addGestureRecognizer(pan)
    let longPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(handleLongPress)
    )
    longPress.minimumPressDuration = 0.35
    playerView.addGestureRecognizer(longPress)
  }

  @objc private func togglePlayback() {
    if player.timeControlStatus == .playing {
      player.pause()
    } else {
      player.play()
    }
    updatePlayButton()
  }

  private func updatePlayButton() {
    let playing = player.timeControlStatus == .playing
    playButton.configuration?.image = UIImage(
      systemName: playing ? "pause.fill" : "play.fill"
    )
    playButton.accessibilityLabel = playing ? "暂停" : "播放"
  }

  private func skip(_ seconds: TimeInterval) {
    let current = player.currentTime().seconds
    let duration = player.currentItem?.duration.seconds ?? .infinity
    let target = min(max(0, current + seconds), duration)
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
  }

  @objc private func seekStarted() {
    isSeeking = true
  }

  @objc private func seekChanged() {
    let duration = player.currentItem?.duration.seconds ?? 0
    currentLabel.text = formatTime(Double(slider.value) * duration)
  }

  @objc private func seekEnded() {
    let duration = player.currentItem?.duration.seconds ?? 0
    player.seek(
      to: CMTime(
        seconds: Double(slider.value) * duration,
        preferredTimescale: 600
      )
    )
    isSeeking = false
  }

  private func updateTime(_ time: CMTime) {
    let current = time.seconds
    let duration = player.currentItem?.duration.seconds ?? 0
    guard current.isFinite else { return }
    currentLabel.text = formatTime(current)
    if duration.isFinite, duration > 0 {
      durationLabel.text = formatTime(duration)
      if !isSeeking {
        slider.value = Float(current / duration)
      }
      if file.duration != duration {
        file.duration = duration
      }
    }
    updatePlayButton()
  }

  private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "--:--" }
    let value = max(0, Int(seconds))
    if value >= 3_600 {
      return String(
        format: "%d:%02d:%02d",
        value / 3_600,
        value % 3_600 / 60,
        value % 60
      )
    }
    return String(format: "%02d:%02d", value / 60, value % 60)
  }

  @objc private func toggleControls() {
    let hidden = controlsView.alpha > 0.5
    let changes = { self.controlsView.alpha = hidden ? 0 : 1 }
    if UIAccessibility.isReduceMotionEnabled {
      changes()
    } else {
      UIView.animate(
        withDuration: 0.22,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction],
        animations: changes
      )
    }
  }

  @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      player.rate = 2
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .ended, .cancelled, .failed:
      player.rate = 1
    default:
      break
    }
  }

  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let location = gesture.location(in: playerView)
    let translation = gesture.translation(in: playerView)
    if gesture.state == .began {
      gestureStartBrightness = UIScreen.main.brightness
      gestureStartVolume = currentVolume()
    }
    guard abs(translation.y) > abs(translation.x) else { return }
    let delta = Float(-translation.y / max(1, playerView.bounds.height))
    if location.x < playerView.bounds.midX {
      UIScreen.main.brightness = min(
        1,
        max(0, gestureStartBrightness + CGFloat(delta))
      )
    } else {
      setVolume(min(1, max(0, gestureStartVolume + delta)))
    }
  }

  private func currentVolume() -> Float {
    volumeSlider()?.value ?? AVAudioSession.sharedInstance().outputVolume
  }

  private func setVolume(_ value: Float) {
    volumeSlider()?.setValue(value, animated: false)
  }

  private func volumeSlider() -> UISlider? {
    volumeView.subviews.compactMap { $0 as? UISlider }.first
  }

  private func togglePictureInPicture() {
    guard let controller = pictureInPictureController else { return }
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
    } else {
      controller.startPictureInPicture()
    }
  }

  private func savePlaybackPosition() {
    let seconds = player.currentTime().seconds
    if seconds.isFinite {
      file.playbackPosition = max(0, seconds)
    }
    file.updatedAt = Date()
    libraryManager.updateFile(file)
  }
}

private final class PlayerSurfaceView: UIView {
  override class var layerClass: AnyClass {
    AVPlayerLayer.self
  }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }
}
