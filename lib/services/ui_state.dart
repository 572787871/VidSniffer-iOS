import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/local_video.dart';
import '../models/video_resource.dart';
import 'download_manager.dart';
import 'local_library.dart';
import 'video_sniffer.dart';

class UiState extends ChangeNotifier {
  UiState() {
    downloadManager.addListener(_onDownloadsChanged);
    refreshLibrary();
  }

  final DownloadManager downloadManager = DownloadManager();
  final VideoSniffer sniffer = VideoSniffer();
  final LocalLibrary library = LocalLibrary();

  final List<String> recentUrls = [];
  final List<VideoResource> resources = [];
  List<LocalVideo> videos = [];
  bool _enrichingLibrary = false;

  int selectedTab = 0;
  bool onlyWifi = false;
  bool parsing = false;
  String status = '准备就绪';

  void addRecent(String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    recentUrls.remove(value);
    recentUrls.insert(0, value);
    notifyListeners();
  }

  Future<void> parseUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) {
      status = '请输入网页 URL';
      notifyListeners();
      return;
    }
    parsing = true;
    status = '正在解析网页';
    resources.clear();
    notifyListeners();
    try {
      final parsed = await sniffer.parsePage(value);
      _replaceResources(parsed);
      status = parsed.isEmpty ? '未发现视频资源' : '发现 ${parsed.length} 个视频资源';
    } catch (error) {
      status = '解析失败：$error';
    } finally {
      parsing = false;
      notifyListeners();
    }
  }

  void setResources(List<VideoResource> values) {
    _replaceResources(values);
    status = resources.isEmpty ? '未发现视频资源' : '发现 ${resources.length} 个视频资源';
    notifyListeners();
  }

  void clearResources({String message = '正在嗅探网页视频'}) {
    resources.clear();
    status = message;
    notifyListeners();
  }

  void addResource(VideoResource resource) {
    if (_shouldSkip(resource.url)) return;
    final normalized = resource.normalizedUrl;
    if (resources.any((item) => item.normalizedUrl == normalized)) return;
    resources.insert(0, resource);
    status = '发现 ${resources.length} 个视频资源';
    notifyListeners();
  }

  void downloadResource(VideoResource resource) {
    debugPrint('[download] click url=${resource.url} type=${resource.label}');
    if (resource.url.startsWith('blob:')) {
      status = 'blob 不是可下载地址，请播放视频后重新嗅探真实地址';
      notifyListeners();
      return;
    }
    final task = downloadManager.createTask(resource);
    downloadManager.addTask(task);
    unawaited(downloadManager.start(task.id));
    selectedTab = 1;
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    videos = await library.scan();
    notifyListeners();
    unawaited(_ensureLibraryDetails(videos));
  }

  Future<void> deleteVideo(LocalVideo video) async {
    await library.delete(video);
    await refreshLibrary();
  }

  Future<void> toggleFavorite(LocalVideo video) async {
    await library.setFavorite(video, !video.isFavorite);
    await refreshLibrary();
  }

  void toggleWifi(bool value) {
    onlyWifi = value;
    notifyListeners();
  }

  void selectTab(int index) {
    selectedTab = index;
    notifyListeners();
  }

  void _replaceResources(List<VideoResource> values) {
    resources
      ..clear()
      ..addAll(
        sniffer.prioritizeResources(
          _dedupe(values.where((item) => !_shouldSkip(item.url))),
        ),
      );
  }

  List<VideoResource> _dedupe(Iterable<VideoResource> values) {
    final seen = <String>{};
    final out = <VideoResource>[];
    for (final item in values) {
      if (seen.add(item.normalizedUrl)) {
        out.add(item);
      }
    }
    return out;
  }

  bool _shouldSkip(String value) {
    final lower = value.toLowerCase().trim();
    return lower.isEmpty ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:') ||
        lower.startsWith('about:');
  }

  void _onDownloadsChanged() {
    if (downloadManager.tasks.any((task) => task.localPath.isNotEmpty)) {
      unawaited(refreshLibrary());
    }
    notifyListeners();
  }

  Future<void> _ensureLibraryDetails(List<LocalVideo> snapshot) async {
    if (_enrichingLibrary || snapshot.isEmpty) return;
    _enrichingLibrary = true;
    var changed = false;
    try {
      for (final video in snapshot) {
        if (video.thumbnailPath.isEmpty ||
            video.duration == Duration.zero ||
            video.width <= 0 ||
            video.height <= 0) {
          changed = await library.ensureDetails(video) || changed;
        }
      }
      if (changed) {
        videos = await library.scan();
        notifyListeners();
      }
    } finally {
      _enrichingLibrary = false;
    }
  }

  @override
  void dispose() {
    downloadManager.removeListener(_onDownloadsChanged);
    downloadManager.dispose();
    super.dispose();
  }
}

class UiStateScope extends InheritedNotifier<UiState> {
  const UiStateScope({required UiState state, required super.child, super.key})
      : super(notifier: state);

  static UiState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiStateScope>();
    assert(scope != null, 'UiStateScope not found');
    return scope!.notifier!;
  }
}
