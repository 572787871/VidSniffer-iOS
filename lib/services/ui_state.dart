import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/mock_models.dart';
import '../models/video_resource.dart';
import 'download_manager.dart';

class UiState extends ChangeNotifier {
  UiState() {
    downloadManager.addListener(notifyListeners);
  }

  final DownloadManager downloadManager = DownloadManager();
  int selectedTab = 0;

  final List<String> recentUrls = [
    'https://example.com/course/video-page',
    'https://example.com/live/replay',
  ];

  final List<VideoResource> resources = [
    const VideoResource(
      title: '网页视频主线路',
      url: 'https://media.example.com/video-1080.mp4',
      type: VideoResourceType.mp4,
      source: 'mock · 1080p · 128 MB',
      pageUrl: 'https://example.com/course/video-page',
    ),
    const VideoResource(
      title: 'HLS 清晰线路',
      url: 'https://media.example.com/master.m3u8',
      type: VideoResourceType.hls,
      source: 'mock · 自适应码率 · 将合并为 mp4',
      pageUrl: 'https://example.com/course/video-page',
    ),
    const VideoResource(
      title: '未知媒体请求',
      url: 'https://media.example.com/stream?id=demo',
      type: VideoResourceType.mp4,
      source: 'mock · unknown · 需要进一步识别',
      pageUrl: 'https://example.com/course/video-page',
    ),
  ];

  final List<MockLocalVideo> videos = [
    const MockLocalVideo(title: '课程回放-已完成.mp4', size: '246 MB', date: '今天 12:10', path: ''),
    const MockLocalVideo(title: '演示视频.mp4', size: '86 MB', date: '昨天 20:32', path: ''),
  ];

  bool onlyWifi = false;

  void addRecent(String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    recentUrls.remove(value);
    recentUrls.insert(0, value);
    notifyListeners();
  }

  void downloadResource(VideoResource resource) {
    debugPrint('[download] click url=${resource.url} type=${resource.label}');
    final task = downloadManager.createTask(resource);
    downloadManager.addTask(task);
    unawaited(downloadManager.start(task.id));
    selectedTab = 1;
    notifyListeners();
  }

  void selectTab(int index) {
    selectedTab = index;
    notifyListeners();
  }

  void toggleWifi(bool value) {
    onlyWifi = value;
    notifyListeners();
  }

  @override
  void dispose() {
    downloadManager.removeListener(notifyListeners);
    downloadManager.dispose();
    super.dispose();
  }
}

class UiStateScope extends InheritedNotifier<UiState> {
  const UiStateScope({required UiState state, required super.child, super.key}) : super(notifier: state);

  static UiState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiStateScope>();
    assert(scope != null, 'UiStateScope not found');
    return scope!.notifier!;
  }
}
