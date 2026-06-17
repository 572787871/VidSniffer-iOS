import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    required this.id,
    required this.title,
    required this.quality,
    required this.size,
    required this.url,
    required this.speed,
    required this.progress,
    this.paused = false,
    this.completed = false,
  });

  final String id;
  final String title;
  final String quality;
  final String size;
  final String url;
  String speed;
  double progress;
  bool paused;
  bool completed;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'quality': quality,
        'size': size,
        'url': url,
        'speed': speed,
        'progress': progress,
        'paused': paused,
        'completed': completed,
      };

  static DownloadTask fromJson(Map<String, Object?> json) => DownloadTask(
        id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? '未命名视频',
        quality: json['quality'] as String? ?? '自动',
        size: json['size'] as String? ?? '未知大小',
        url: json['url'] as String? ?? '',
        speed: json['speed'] as String? ?? '等待中',
        progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0).toDouble(),
        paused: json['paused'] as bool? ?? false,
        completed: json['completed'] as bool? ?? false,
      );
}

class LocalVideo {
  const LocalVideo({
    required this.title,
    required this.duration,
    required this.size,
    required this.thumbnail,
    this.sourceUrl = '',
  });

  final String title;
  final String duration;
  final String size;
  final String thumbnail;
  final String sourceUrl;

  Map<String, Object?> toJson() => {
        'title': title,
        'duration': duration,
        'size': size,
        'thumbnail': thumbnail,
        'sourceUrl': sourceUrl,
      };

  static LocalVideo fromJson(Map<String, Object?> json) => LocalVideo(
        title: json['title'] as String? ?? '未命名视频',
        duration: json['duration'] as String? ?? '--:--',
        size: json['size'] as String? ?? '未知大小',
        thumbnail: json['thumbnail'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
      );
}

class AppState extends ChangeNotifier {
  AppState() {
    _restore();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tickDownloads());
  }

  static const _downloadsKey = 'vidsniffer.downloads.v1';
  static const _filesKey = 'vidsniffer.files.v1';
  static const _settingsKey = 'vidsniffer.settings.v1';

  final List<VideoResource> parseResults = [];
  final List<VideoResource> sniffedResources = [];
  final List<DownloadTask> downloads = [];
  final List<LocalVideo> files = [];

  Timer? _ticker;
  bool _restored = false;
  bool darkMode = true;
  String downloadDirectory = 'VidSniffer Pro / Downloads';
  String cacheSize = '128 MB';
  bool parsing = false;
  bool browserLoading = false;
  String browserUrl = 'https://example.com/video';

  bool get restored => _restored;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

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
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: resource.title,
      quality: resource.quality,
      size: resource.size,
      url: resource.url,
      speed: '连接中',
      progress: 0.01,
    );
    downloads.insert(0, task);
    _saveDownloads();
    notifyListeners();
  }

  void toggleDownload(DownloadTask task) {
    if (task.completed) {
      return;
    }
    task.paused = !task.paused;
    task.speed = task.paused ? '已暂停' : '3.6 MB/s';
    _saveDownloads();
    notifyListeners();
  }

  void deleteDownload(DownloadTask task) {
    downloads.remove(task);
    _saveDownloads();
    notifyListeners();
  }

  void deleteFile(LocalVideo file) {
    files.remove(file);
    _saveFiles();
    notifyListeners();
  }

  void setDarkMode(bool value) {
    darkMode = value;
    _saveSettings();
    notifyListeners();
  }

  void setDownloadDirectory(String value) {
    downloadDirectory = value;
    _saveSettings();
    notifyListeners();
  }

  void clearCache() {
    cacheSize = '0 MB';
    _saveSettings();
    notifyListeners();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDownloads = prefs.getString(_downloadsKey);
    final savedFiles = prefs.getString(_filesKey);
    final savedSettings = prefs.getString(_settingsKey);

    if (savedDownloads != null) {
      final list = jsonDecode(savedDownloads) as List<dynamic>;
      downloads
        ..clear()
        ..addAll(list.map((item) => DownloadTask.fromJson(Map<String, Object?>.from(item as Map))));
    }
    if (savedFiles != null) {
      final list = jsonDecode(savedFiles) as List<dynamic>;
      files
        ..clear()
        ..addAll(list.map((item) => LocalVideo.fromJson(Map<String, Object?>.from(item as Map))));
    }
    if (savedSettings != null) {
      final settings = Map<String, Object?>.from(jsonDecode(savedSettings) as Map);
      darkMode = settings['darkMode'] as bool? ?? true;
      downloadDirectory = settings['downloadDirectory'] as String? ?? downloadDirectory;
      cacheSize = settings['cacheSize'] as String? ?? cacheSize;
    }

    _restored = true;
    notifyListeners();
  }

  void _tickDownloads() {
    var changed = false;
    for (final task in downloads) {
      if (task.paused || task.completed) {
        continue;
      }
      final next = (task.progress + 0.018).clamp(0.0, 1.0).toDouble();
      task.progress = next;
      if (next >= 1) {
        task.completed = true;
        task.speed = '已完成';
        files.insert(
          0,
          LocalVideo(
            title: _fileNameFor(task),
            duration: '00:00',
            size: task.size,
            thumbnail: 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?w=600',
            sourceUrl: task.url,
          ),
        );
      } else {
        final speed = 2.4 + (next * 3.2);
        task.speed = '${speed.toStringAsFixed(1)} MB/s';
      }
      changed = true;
    }
    if (!changed) {
      return;
    }
    _saveDownloads();
    _saveFiles();
    notifyListeners();
  }

  Future<void> _saveDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadsKey, jsonEncode(downloads.map((task) => task.toJson()).toList()));
  }

  Future<void> _saveFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filesKey, jsonEncode(files.map((file) => file.toJson()).toList()));
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _settingsKey,
      jsonEncode({
        'darkMode': darkMode,
        'downloadDirectory': downloadDirectory,
        'cacheSize': cacheSize,
      }),
    );
  }

  String _fileNameFor(DownloadTask task) {
    final ext = task.quality.toLowerCase().contains('m3u8') ? 'm3u8' : 'mp4';
    return '${task.title}.$ext';
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
