import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/mock_models.dart';

class UiState extends ChangeNotifier {
  final List<String> recentUrls = [
    'https://example.com/course/video-page',
    'https://example.com/live/replay',
  ];

  final List<MockVideoResource> resources = [
    const MockVideoResource(
      title: '网页视频主线路',
      url: 'https://media.example.com/video-1080.mp4',
      type: MockVideoType.mp4,
      meta: '1080p · 128 MB',
    ),
    const MockVideoResource(
      title: 'HLS 清晰线路',
      url: 'https://media.example.com/master.m3u8',
      type: MockVideoType.m3u8,
      meta: '自适应码率 · 将合并为 mp4',
    ),
    const MockVideoResource(
      title: '未知媒体请求',
      url: 'https://media.example.com/stream?id=demo',
      type: MockVideoType.unknown,
      meta: '需要进一步识别',
    ),
  ];

  final List<MockDownloadTask> downloads = [
    MockDownloadTask(title: '网页视频主线路.mp4', type: 'mp4', progress: 0.68, speed: '3.2 MB/s', remaining: '00:42', completed: false),
    MockDownloadTask(title: '课程回放-已完成.mp4', type: 'mp4', progress: 1, speed: '完成', remaining: '00:00', completed: true),
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

  void enqueue(MockVideoResource resource) {
    downloads.insert(
      0,
      MockDownloadTask(
        title: '${resource.title}.${resource.type == MockVideoType.m3u8 ? 'mp4' : resource.typeLabel}',
        type: resource.typeLabel,
        progress: 0.04,
        speed: '准备中',
        remaining: '--:--',
        completed: false,
      ),
    );
    notifyListeners();
  }

  void toggleWifi(bool value) {
    onlyWifi = value;
    notifyListeners();
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
