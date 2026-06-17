import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';

import '../theme/app_theme.dart';
import 'app_state.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({required this.file, super.key});

  final LocalVideo file;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  Future<void>? _initializeFuture;

  @override
  void initState() {
    super.initState();
    final localPath = widget.file.localPath.trim();
    final localFile = localPath.isEmpty ? null : File(localPath);
    final hasLocalFile = localFile != null && localFile.existsSync();
    if (!hasLocalFile) {
      return;
    }

    final controller = VideoPlayerController.file(localFile!);
    _videoController = controller;
    _initializeFuture = controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        deviceOrientationsOnEnterFullScreen: const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
        deviceOrientationsAfterFullScreen: const [DeviceOrientation.portraitUp],
        showControlsOnInitialize: true,
        playbackSpeeds: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        materialProgressColors: ChewieProgressColors(
          playedColor: AppTheme.electricBlue,
          handleColor: Colors.white,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white12,
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: AppTheme.electricBlue,
          handleColor: Colors.white,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white12,
        ),
        errorBuilder: (context, errorMessage) => _PlayerError(message: errorMessage),
      );
      setState(() {});
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localPath = widget.file.localPath.trim();
    final hasLocalFile = localPath.isNotEmpty && File(localPath).existsSync();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _PlayerHeader(title: widget.file.title),
            Expanded(
              child: Center(
                child: !hasLocalFile
                    ? const _PlayerError(message: '这个视频没有可播放的本地文件，请重新下载到 Documents/videos。')
                    : FutureBuilder<void>(
                        future: _initializeFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done || _chewieController == null) {
                            return const CupertinoActivityIndicator(radius: 16);
                          }
                          return AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio == 0 ? 16 / 9 : _videoController!.value.aspectRatio,
                            child: Chewie(controller: _chewieController!),
                          );
                        },
                      ),
              ),
            ),
            if (hasLocalFile && _videoController != null) _TransportBar(controller: _videoController!),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.file.duration} · ${widget.file.size}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.chevronRight, size: 18),
                    label: const Text('完成'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 14, 8),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 44,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TransportButton(label: '-10s', icon: Icons.replay_10_rounded, onTap: () => _seekBy(const Duration(seconds: -10))),
              const SizedBox(width: 14),
              _TransportButton(label: value.isPlaying ? '暂停' : '播放', icon: value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, onTap: _toggle),
              const SizedBox(width: 14),
              _TransportButton(label: '+10s', icon: Icons.forward_10_rounded, onTap: () => _seekBy(const Duration(seconds: 10))),
            ],
          ),
        );
      },
    );
  }

  void _toggle() {
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  void _seekBy(Duration offset) {
    final value = controller.value;
    final duration = value.duration;
    final next = value.position + offset;
    if (next < Duration.zero) {
      controller.seekTo(Duration.zero);
      return;
    }
    if (duration != Duration.zero && next > duration) {
      controller.seekTo(duration);
      return;
    }
    controller.seekTo(next);
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      color: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(999),
      minSize: 0,
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.video, color: Colors.white54, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
