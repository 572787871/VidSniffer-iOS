import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/file_utils.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.title, this.filePath, super.key});

  final String title;
  final String? filePath;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? controller;
  double speed = 1;
  String? error;

  @override
  void initState() {
    super.initState();
    final filePath = widget.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      _openFile(filePath);
    }
  }

  @override
  void dispose() {
    controller?.removeListener(_onPlayerChanged);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Center(child: _videoView())),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: Column(
                children: [
                  Slider(
                    value: _positionFraction(),
                    onChanged: (value) {
                      final duration = controller?.value.duration;
                      if (duration == null) return;
                      controller?.seekTo(Duration(milliseconds: (duration.inMilliseconds * value).round()));
                    },
                  ),
                  Row(
                    children: [
                      IconButton.filled(
                        onPressed: () {
                          final player = controller;
                          if (player == null) return;
                          player.value.isPlaying ? player.pause() : player.play();
                          setState(() {});
                        },
                        icon: Icon(controller?.value.isPlaying ?? false ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      ),
                      IconButton(onPressed: () {}, icon: const Icon(Icons.replay_10_rounded, color: Colors.white)),
                      IconButton(onPressed: () {}, icon: const Icon(Icons.forward_10_rounded, color: Colors.white)),
                      const Spacer(),
                      DropdownButton<double>(
                        value: speed,
                        dropdownColor: const Color(0xff222222),
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                          DropdownMenuItem(value: 1, child: Text('1.0x')),
                          DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                          DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                          DropdownMenuItem(value: 2, child: Text('2.0x')),
                        ],
                        onChanged: (value) {
                          setState(() => speed = value ?? 1);
                          controller?.setPlaybackSpeed(speed);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    return AspectRatio(aspectRatio: player.value.aspectRatio, child: VideoPlayer(player));
  }

  Widget _placeholder(String text) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: const Color(0xff111111),
        child: Center(
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  double _positionFraction() {
    final value = controller?.value;
    if (value == null || !value.isInitialized || value.duration.inMilliseconds <= 0) {
      return 0;
    }
    return (value.position.inMilliseconds / value.duration.inMilliseconds).clamp(0, 1).toDouble();
  }

  void _onPlayerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openFile(String path) async {
    try {
      final file = File(path);
      final lower = path.toLowerCase();
      if (!await file.exists()) {
        throw StateError('文件不存在');
      }
      if (await file.length() <= 0) {
        throw StateError('文件大小为 0');
      }
      if (!lower.endsWith('.mp4') && !lower.endsWith('.mov') && !lower.endsWith('.m4v')) {
        throw StateError('不是支持的视频文件后缀');
      }
      if (await FileUtils.looksLikeHtml(file)) {
        throw StateError('文件内容是 HTML，不是视频');
      }
      controller = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          controller?.play();
        })
        ..addListener(_onPlayerChanged);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }
}
