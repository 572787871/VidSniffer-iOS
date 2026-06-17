import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class VideoResource {
  const VideoResource({
    required this.title,
    required this.quality,
    required this.size,
    required this.url,
    this.source = '网页解析',
  });

  final String title;
  final String quality;
  final String size;
  final String url;
  final String source;
}

class DownloadTask {
  DownloadTask({
    required this.title,
    required this.quality,
    required this.size,
    required this.speed,
    required this.progress,
    this.paused = false,
  });

  final String title;
  final String quality;
  final String size;
  String speed;
  double progress;
  bool paused;
}

class LocalVideo {
  const LocalVideo({
    required this.title,
    required this.duration,
    required this.size,
    required this.thumbnail,
  });

  final String title;
  final String duration;
  final String size;
  final String thumbnail;
}

class AppState extends ChangeNotifier {
  final List<VideoResource> parseResults = [];
  final List<VideoResource> sniffedResources = [
    const VideoResource(
      title: 'index_1080p.m3u8',
      quality: '1080P HLS',
      size: '预计 812 MB',
      url: 'https://media.example.com/index_1080p.m3u8',
      source: '自动嗅探',
    ),
  ];
  final List<DownloadTask> downloads = [
    DownloadTask(
      title: '城市夜景纪录片',
      quality: '1080P MP4',
      size: '1.24 GB',
      speed: '4.8 MB/s',
      progress: 0.72,
    ),
    DownloadTask(
      title: '演示视频片段',
      quality: '720P HLS',
      size: '386 MB',
      speed: '已暂停',
      progress: 0.34,
      paused: true,
    ),
  ];
  final List<LocalVideo> files = [
    const LocalVideo(
      title: '城市夜景纪录片.mp4',
      duration: '24:18',
      size: '1.24 GB',
      thumbnail: 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?w=600',
    ),
    const LocalVideo(
      title: '产品发布会回放.m3u8',
      duration: '58:42',
      size: '2.8 GB',
      thumbnail: 'https://images.unsplash.com/photo-1492724441997-5dc865305da7?w=600',
    ),
  ];

  bool parsing = false;
  bool browserLoading = false;
  String browserUrl = 'https://example.com/video';

  Future<void> parse(String url) async {
    if (url.trim().isEmpty) {
      return;
    }
    parsing = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 850));
    parseResults
      ..clear()
      ..addAll([
        VideoResource(
          title: _titleFromUrl(url),
          quality: '1080P MP4',
          size: '748 MB',
          url: url,
        ),
        VideoResource(
          title: '${_titleFromUrl(url)} · 备用线路',
          quality: '720P HLS',
          size: '412 MB',
          url: '$url?format=m3u8',
        ),
      ]);
    parsing = false;
    notifyListeners();
  }

  Future<void> loadBrowserUrl(String url) async {
    browserUrl = url.trim().isEmpty ? browserUrl : url.trim();
    browserLoading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    sniffedResources.insert(
      0,
      VideoResource(
        title: 'video_${sniffedResources.length + 1}_auto.m3u8',
        quality: 'HLS 自适应',
        size: '预计 540 MB',
        url: '$browserUrl/stream.m3u8',
        source: '自动嗅探',
      ),
    );
    browserLoading = false;
    notifyListeners();
  }

  void addDownload(VideoResource resource) {
    downloads.insert(
      0,
      DownloadTask(
        title: resource.title,
        quality: resource.quality,
        size: resource.size,
        speed: '等待中',
        progress: 0.02,
      ),
    );
    notifyListeners();
  }

  void toggleDownload(DownloadTask task) {
    task.paused = !task.paused;
    task.speed = task.paused ? '已暂停' : '3.6 MB/s';
    notifyListeners();
  }

  void deleteDownload(DownloadTask task) {
    downloads.remove(task);
    notifyListeners();
  }

  void deleteFile(LocalVideo file) {
    files.remove(file);
    notifyListeners();
  }

  String _titleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.isNotEmpty == true ? uri!.host : '网页视频';
    return '$host 视频资源';
  }
}

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({required AppState notifier, required super.child, super.key}) : super(notifier: notifier);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found');
    return scope!.notifier!;
  }
}
