import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/download_task.dart';
import '../models/video_resource.dart';
import '../services/download_manager.dart';
import '../services/file_utils.dart';
import '../services/playback_store.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.title,
    this.filePath,
    this.allowPartial = false,
    this.downloadTask,
    this.downloadManager,
    super.key,
  });

  final String title;
  final String? filePath;
  final bool allowPartial;
  final DownloadTask? downloadTask;
  final DownloadManager? downloadManager;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? controller;
  Timer? overlayTimer;
  Timer? controlsTimer;
  Timer? partialRefreshTimer;
  double speed = 1;
  double speedBeforeHold = 1;
  double volume = 1;
  double brightness = 1;
  double horizontalDrag = 0;
  double verticalStartX = 0;
  bool coverFit = false;
  bool controlsVisible = true;
  bool locked = false;
  String? error;
  String? overlayText;
  Offset? doubleTapPosition;
  String? currentPath;
  int lastKnownLength = 0;
  bool refreshingPartial = false;
  final playbackStore = PlaybackStore();

  @override
  void initState() {
    super.initState();
    widget.downloadManager?.addListener(_onPlayerChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final filePath = widget.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      if (widget.allowPartial &&
          widget.downloadTask?.resource.isPlayable == true) {
        _openStreamingPreview(widget.downloadTask!.resource);
      } else {
        _openFile(filePath);
      }
      if (widget.allowPartial &&
          widget.downloadTask?.resource.isPlayable != true) {
        partialRefreshTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) => unawaited(_refreshGrowingFile()),
        );
      }
    }
  }

  @override
  void dispose() {
    overlayTimer?.cancel();
    controlsTimer?.cancel();
    partialRefreshTimer?.cancel();
    _savePlaybackPosition();
    controller?.setPlaybackSpeed(1);
    controller?.removeListener(_onPlayerChanged);
    controller?.dispose();
    widget.downloadManager?.removeListener(_onPlayerChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: locked
              ? null
              : () {
                  setState(() => controlsVisible = !controlsVisible);
                  if (controlsVisible) _scheduleControlsHide();
                },
          onDoubleTapDown: (details) =>
              doubleTapPosition = details.localPosition,
          onDoubleTap: locked ? null : _handleDoubleTap,
          onLongPressStart: locked ? null : _handleLongPressStart,
          onLongPressEnd: locked ? null : (_) => _handleLongPressEnd(),
          onHorizontalDragStart: locked ? null : (_) => horizontalDrag = 0,
          onHorizontalDragUpdate: locked ? null : _handleHorizontalDrag,
          onHorizontalDragEnd: locked ? null : (_) => _commitHorizontalDrag(),
          onVerticalDragStart: locked
              ? null
              : (details) => verticalStartX = details.localPosition.dx,
          onVerticalDragUpdate: locked ? null : _handleVerticalDrag,
          child: Stack(
            children: [
              Positioned.fill(child: Center(child: _videoView())),
              Positioned.fill(
                child: IgnorePointer(child: _brightnessOverlay()),
              ),
              if (overlayText != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      overlayText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _animatedChrome(_topControls(isLandscape)),
              ),
              Center(child: _animatedChrome(_centerControls(isLandscape))),
              Positioned(
                right: 14,
                top: isLandscape ? 56 : 76,
                child: IconButton.filled(
                  onPressed: () => setState(() => locked = !locked),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.48),
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    locked
                        ? CupertinoIcons.lock_fill
                        : CupertinoIcons.lock_open_fill,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _animatedChrome(_controls(isLandscape)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animatedChrome(Widget child) {
    final visible = controlsVisible && !locked;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  Widget _topControls(bool isLandscape) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 18 : 10,
        MediaQuery.paddingOf(context).top + 8,
        isLandscape ? 18 : 10,
        34,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xcc000000), Color(0x00000000)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: Navigator.of(context).pop,
            icon: const Icon(CupertinoIcons.back),
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isLandscape ? 16 : 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: coverFit ? '完整显示' : '填充画面',
            onPressed: _toggleFit,
            icon: Icon(
              coverFit
                  ? CupertinoIcons.rectangle_compress_vertical
                  : CupertinoIcons.rectangle_expand_vertical,
            ),
            color: Colors.white,
          ),
          IconButton(
            tooltip: '更多',
            onPressed: _showPlayerMenu,
            icon: const Icon(CupertinoIcons.ellipsis),
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _centerControls(bool isLandscape) {
    final diameter = isLandscape ? 70.0 : 64.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassControlButton(
          tooltip: '后退 10 秒',
          icon: CupertinoIcons.gobackward_10,
          onPressed: () => _seekBy(-10),
        ),
        SizedBox(width: isLandscape ? 28 : 18),
        SizedBox(
          width: diameter,
          height: diameter,
          child: IconButton.filled(
            tooltip: controller?.value.isPlaying == true ? '暂停' : '播放',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.56),
              foregroundColor: Colors.white,
            ),
            onPressed: _togglePlay,
            iconSize: 38,
            icon: Icon(
              controller?.value.isPlaying == true
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
            ),
          ),
        ),
        SizedBox(width: isLandscape ? 28 : 18),
        _GlassControlButton(
          tooltip: '前进 10 秒',
          icon: CupertinoIcons.goforward_10,
          onPressed: () => _seekBy(10),
        ),
      ],
    );
  }

  Widget _videoView() {
    final player = controller;
    if (error != null) {
      return _placeholder(error!);
    }
    if (player == null) {
      return _placeholder('没有可播放的本地文件');
    }
    if (!player.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final size = player.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return AspectRatio(
        aspectRatio: player.value.aspectRatio,
        child: VideoPlayer(player),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: coverFit ? BoxFit.cover : BoxFit.contain,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(player),
        ),
      ),
    );
  }

  Widget _placeholder(String text) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xff111111),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _brightnessOverlay() {
    if (brightness == 1) {
      return const SizedBox.shrink();
    }
    final color = brightness < 1 ? Colors.black : Colors.white;
    final opacity = brightness < 1
        ? (1 - brightness).clamp(0, 0.65).toDouble()
        : ((brightness - 1) * 0.28).clamp(0, 0.22).toDouble();
    return ColoredBox(color: color.withValues(alpha: opacity));
  }

  Widget _controls(bool isLandscape) {
    final player = controller;
    final value = player?.value;
    final downloaded = widget.downloadTask?.progress.clamp(0, 1).toDouble() ??
        _bufferedFraction();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.94)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isLandscape ? 34 : 18,
          isLandscape ? 58 : 50,
          isLandscape ? 34 : 18,
          MediaQuery.paddingOf(context).bottom + (isLandscape ? 12 : 18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.downloadTask != null)
              Align(
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    '已缓存 ${_formatPosition(Duration(milliseconds: (_displayDuration().inMilliseconds * downloaded).round()))}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbColor: Colors.white,
                overlayColor: const Color(0x44007aff),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: SizedBox(
                height: 32,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      height: 4,
                      child: _PreviewProgressTrack(
                        played: _positionFraction(),
                        buffered: _bufferedFraction(),
                        downloaded: downloaded,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        disabledActiveTrackColor: Colors.transparent,
                        disabledInactiveTrackColor: Colors.transparent,
                      ),
                      child: Slider(
                        value: _positionFraction(),
                        onChanged: value == null || !value.isInitialized
                            ? null
                            : (position) => _seekToFraction(position),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -4),
              child: Row(
                children: [
                  Text(
                    _formatPosition(value?.position ?? Duration.zero),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    _formatPosition(_displayDuration()),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                IconButton(
                  tooltip: volume == 0 ? '开启声音' : '静音',
                  onPressed: _toggleMute,
                  icon: Icon(
                    volume == 0
                        ? CupertinoIcons.volume_off
                        : CupertinoIcons.volume_up,
                    color: Colors.white,
                  ),
                ),
                if (isLandscape)
                  SizedBox(
                    width: 110,
                    child: Slider(
                      value: volume,
                      onChanged: (newVolume) {
                        setState(() => volume = newVolume);
                        controller?.setVolume(newVolume);
                      },
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _toggleFit,
                  child: Text(
                    _qualityLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DropdownButton<double>(
                  value: speed,
                  dropdownColor: const Color(0xff222222),
                  style: const TextStyle(color: Colors.white),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                    DropdownMenuItem(value: 1, child: Text('1.0x')),
                    DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                    DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                    DropdownMenuItem(value: 2, child: Text('2.0x')),
                  ],
                  onChanged: (selected) {
                    setState(() => speed = selected ?? 1);
                    controller?.setPlaybackSpeed(speed);
                    _scheduleControlsHide();
                  },
                ),
                IconButton(
                  tooltip: isLandscape ? '退出全屏' : '全屏',
                  onPressed: _toggleFullscreen,
                  icon: Icon(
                    isLandscape
                        ? CupertinoIcons.arrow_down_right_arrow_up_left
                        : CupertinoIcons.arrow_up_left_arrow_down_right,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _positionFraction() {
    final value = controller?.value;
    if (value == null ||
        !value.isInitialized ||
        _displayDuration().inMilliseconds <= 0) {
      return 0;
    }
    return (value.position.inMilliseconds / _displayDuration().inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  Duration _displayDuration() {
    final playlist = widget.downloadTask?.playlistDuration ?? Duration.zero;
    if (playlist > Duration.zero) return playlist;
    return controller?.value.duration ?? Duration.zero;
  }

  double _bufferedFraction() {
    final value = controller?.value;
    final duration = _displayDuration();
    if (value == null || duration.inMilliseconds <= 0 || value.buffered.isEmpty) {
      return 0;
    }
    final end = value.buffered
        .map((range) => range.end)
        .reduce((a, b) => a > b ? a : b);
    return (end.inMilliseconds / duration.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  Future<void> _seekToFraction(double fraction) async {
    final player = controller;
    if (player == null) return;
    final target = Duration(
      milliseconds: (_displayDuration().inMilliseconds * fraction).round(),
    );
    if (widget.downloadTask != null &&
        fraction > widget.downloadTask!.progress) {
      _showOverlay('正在缓冲目标片段…');
    }
    await player.seekTo(target);
    await player.play();
  }

  void _togglePlay() {
    final player = controller;
    if (player == null) return;
    player.value.isPlaying ? player.pause() : player.play();
    setState(() {});
    _scheduleControlsHide();
  }

  void _toggleFit() {
    setState(() => coverFit = !coverFit);
    _showOverlay(coverFit ? '画面填充' : '完整显示');
    _scheduleControlsHide();
  }

  void _toggleMute() {
    setState(() => volume = volume > 0 ? 0 : 1);
    controller?.setVolume(volume);
    _showOverlay(volume == 0 ? '已静音' : '音量 100%');
  }

  void _toggleFullscreen() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.portraitUp]
          : [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  String _qualityLabel() {
    final size = controller?.value.size;
    if (size == null || size.height <= 0) return '视频';
    final height = size.height.round();
    if (height >= 2160) return '4K';
    if (height >= 1440) return '1440P';
    if (height >= 1080) return '1080P';
    if (height >= 720) return '720P';
    if (height >= 480) return '480P';
    return '${height}P';
  }

  Future<void> _showPlayerMenu() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('从头播放'),
              onTap: () => Navigator.pop(context, 'restart'),
            ),
            ListTile(
              leading: Icon(
                coverFit
                    ? Icons.fit_screen_rounded
                    : Icons.aspect_ratio_rounded,
              ),
              title: Text(coverFit ? '完整显示画面' : '填充屏幕'),
              onTap: () => Navigator.pop(context, 'fit'),
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: const Text('恢复正常速度'),
              subtitle: Text('当前 ${speed.toStringAsFixed(2)}×'),
              onTap: () => Navigator.pop(context, 'speed'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text('${_qualityLabel()} · ${_formatPosition(_displayDuration())}'),
              subtitle: const Text('双击快进/后退，长按 2 倍速播放'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (selected == 'restart') {
      await controller?.seekTo(Duration.zero);
      await controller?.play();
    } else if (selected == 'fit') {
      _toggleFit();
    } else if (selected == 'speed') {
      setState(() => speed = 1);
      await controller?.setPlaybackSpeed(1);
    }
    _scheduleControlsHide();
  }

  void _handleDoubleTap() {
    final width = context.size?.width ?? 0;
    final dx = doubleTapPosition?.dx ?? width / 2;
    _seekBy(dx < width / 2 ? -10 : 10);
  }

  void _handleHorizontalDrag(DragUpdateDetails details) {
    horizontalDrag += details.delta.dx;
    final seconds = (horizontalDrag / 8).round();
    if (seconds == 0) return;
    _showOverlay(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  void _commitHorizontalDrag() {
    final seconds = (horizontalDrag / 8).round();
    horizontalDrag = 0;
    if (seconds != 0) {
      _seekBy(seconds);
    }
  }

  void _handleVerticalDrag(DragUpdateDetails details) {
    final width = context.size?.width ?? 0;
    final delta = -details.delta.dy / 320;
    if (verticalStartX < width / 2) {
      brightness = (brightness + delta).clamp(0.25, 1.45).toDouble();
      _showOverlay('亮度 ${(brightness * 100).round()}%');
    } else {
      volume = (volume + delta).clamp(0, 1).toDouble();
      controller?.setVolume(volume);
      _showOverlay('音量 ${(volume * 100).round()}%');
    }
    setState(() {});
  }

  void _seekBy(int seconds) {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    final duration = _displayDuration();
    final current = player.value.position;
    final targetMs = (current.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds)
        .toInt();
    player.seekTo(Duration(milliseconds: targetMs));
    _showOverlay(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    speedBeforeHold = speed;
    speed = 2;
    player.setPlaybackSpeed(2);
    _showOverlay('2.0x 快进中');
    setState(() {});
  }

  void _handleLongPressEnd() {
    final player = controller;
    speed = speedBeforeHold <= 0 ? 1 : speedBeforeHold;
    player?.setPlaybackSpeed(speed);
    _showOverlay('已恢复 ${speed.toStringAsFixed(2)}x');
    setState(() {});
  }

  void _scheduleControlsHide() {
    controlsTimer?.cancel();
    if (!controlsVisible) return;
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !locked) {
        setState(() => controlsVisible = false);
      }
    });
  }

  void _showOverlay(String text) {
    overlayTimer?.cancel();
    setState(() => overlayText = text);
    overlayTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) {
        setState(() => overlayText = null);
      }
    });
  }

  String _formatPosition(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _onPlayerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openFile(
    String path, {
    Duration? resumeAt,
    bool autoplay = false,
  }) async {
    try {
      final file = File(path);
      final lower = path.toLowerCase();
      if (!await file.exists()) {
        throw StateError('文件不存在');
      }
      if (await file.length() <= 0) {
        throw StateError('文件大小为 0');
      }
      if (!widget.allowPartial &&
          !lower.endsWith('.mp4') &&
          !lower.endsWith('.mov') &&
          !lower.endsWith('.m4v')) {
        throw StateError('不是支持的视频文件后缀');
      }
      if (await FileUtils.looksLikeHtml(file)) {
        throw StateError('文件内容是 HTML，不是视频');
      }
      lastKnownLength = await file.length();
      currentPath = path;
      final previous = controller;
      previous?.removeListener(_onPlayerChanged);
      await previous?.dispose();
      final player = VideoPlayerController.file(file)
        ..addListener(_onPlayerChanged);
      controller = player;
      await player.initialize();
      if (!mounted) return;
      if (resumeAt != null) {
        await player.seekTo(resumeAt);
        if (autoplay) await player.play();
        setState(() => error = null);
      } else {
        await _afterInitialized(path);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = widget.allowPartial
              ? '已下载部分暂时无法播放，请等待更多内容后重试。\n$e'
              : '$e',
        );
      }
    }
  }

  Future<void> _openStreamingPreview(VideoResource resource) async {
    try {
      final previous = controller;
      previous?.removeListener(_onPlayerChanged);
      await previous?.dispose();
      final player = VideoPlayerController.networkUrl(
        Uri.parse(resource.url),
        httpHeaders: {
          if (resource.referer.isNotEmpty || resource.pageUrl.isNotEmpty)
            'Referer': resource.referer.isNotEmpty
                ? resource.referer
                : resource.pageUrl,
          if (resource.userAgent.isNotEmpty) 'User-Agent': resource.userAgent,
          if (resource.cookie.isNotEmpty) 'Cookie': resource.cookie,
          if (resource.origin.isNotEmpty) 'Origin': resource.origin,
        },
      )..addListener(_onPlayerChanged);
      controller = player;
      await player.initialize();
      if (!mounted) return;
      setState(() => error = null);
      _scheduleControlsHide();
      await player.play();
    } catch (e) {
      if (mounted) {
        setState(() => error = '边下边播连接失败，请返回网页重新解析。\n$e');
      }
    }
  }

  Future<void> _refreshGrowingFile() async {
    if (refreshingPartial) return;
    final path = currentPath;
    final player = controller;
    if (path == null || player == null || !player.value.isInitialized) return;
    final file = File(path);
    if (!await file.exists()) return;
    final length = await file.length();
    if (length <= lastKnownLength) return;
    final remaining = player.value.duration - player.value.position;
    lastKnownLength = length;
    if (remaining > const Duration(seconds: 4)) return;
    refreshingPartial = true;
    final position = player.value.position;
    final wasPlaying = player.value.isPlaying;
    try {
      await _openFile(path, resumeAt: position, autoplay: wasPlaying);
    } finally {
      refreshingPartial = false;
    }
  }

  Future<void> _afterInitialized(String path) async {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    player.setVolume(volume);
    final resume = await playbackStore.positionFor(path);
    if (!mounted) return;
    if (resume.inSeconds > 10 &&
        resume < player.value.duration - const Duration(seconds: 10)) {
      final shouldContinue = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('继续播放？'),
          content: Text('\n上次播放到 ${_formatPosition(resume)}'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('从头播放'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续播放'),
            ),
          ],
        ),
      );
      if (shouldContinue == true) {
        await player.seekTo(resume);
      } else {
        await player.seekTo(Duration.zero);
      }
    }
    if (!mounted) return;
    setState(() {});
    _scheduleControlsHide();
    player.play();
  }

  void _savePlaybackPosition() {
    final path = currentPath;
    final value = controller?.value;
    if (path == null || value == null || !value.isInitialized) return;
    unawaited(
      playbackStore.save(
        path: path,
        position: value.position,
        duration: value.duration,
      ),
    );
  }
}

class _GlassControlButton extends StatelessWidget {
  const _GlassControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.48),
        foregroundColor: Colors.white,
        minimumSize: const Size(52, 52),
      ),
      icon: Icon(icon, size: 28),
    );
  }
}

class _PreviewProgressTrack extends StatelessWidget {
  const _PreviewProgressTrack({
    required this.played,
    required this.buffered,
    required this.downloaded,
  });

  final double played;
  final double buffered;
  final double downloaded;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0x55ffffff))),
            _bar(const Color(0xff8bbcff), downloaded, constraints.maxWidth),
            _rangeBar(
              const Color(0xffd5e1ff),
              downloaded,
              buffered,
              constraints.maxWidth,
            ),
            _bar(const Color(0xff007aff), played, constraints.maxWidth),
          ],
        ),
      ),
    );
  }

  Widget _bar(Color color, double fraction, double width) => Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: width * fraction.clamp(0, 1).toDouble(),
        child: ColoredBox(color: color),
      );

  Widget _rangeBar(
    Color color,
    double start,
    double end,
    double width,
  ) {
    final from = start.clamp(0, 1).toDouble();
    final to = end.clamp(from, 1).toDouble();
    return Positioned(
      left: width * from,
      top: 0,
      bottom: 0,
      width: width * (to - from),
      child: ColoredBox(color: color),
    );
  }
}
