import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
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
    this.localPath = '',
    this.error = '',
    this.paused = false,
    this.completed = false,
  });

  final String id;
  final String title;
  final String quality;
  String size;
  final String url;
  String speed;
  double progress;
  String localPath;
  String error;
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
        'localPath': localPath,
        'error': error,
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
        localPath: json['localPath'] as String? ?? '',
        error: json['error'] as String? ?? '',
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
    this.localPath = '',
  });

  final String title;
  final String duration;
  final String size;
  final String thumbnail;
  final String sourceUrl;
  final String localPath;

  Map<String, Object?> toJson() => {
        'title': title,
        'duration': duration,
        'size': size,
        'thumbnail': thumbnail,
        'sourceUrl': sourceUrl,
        'localPath': localPath,
      };

  static LocalVideo fromJson(Map<String, Object?> json) => LocalVideo(
        title: json['title'] as String? ?? '未命名视频',
        duration: json['duration'] as String? ?? '--:--',
        size: json['size'] as String? ?? '未知大小',
        thumbnail: json['thumbnail'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        localPath: json['localPath'] as String? ?? '',
      );
}

class AppState extends ChangeNotifier {
  AppState() {
    _restore();
  }

  static const _downloadsKey = 'vidsniffer.downloads.v1';
  static const _filesKey = 'vidsniffer.files.v1';
  static const _settingsKey = 'vidsniffer.settings.v1';

  final List<VideoResource> parseResults = [];
  final List<VideoResource> sniffedResources = [];
  final List<DownloadTask> downloads = [];
  final List<LocalVideo> files = [];

  bool _restored = false;
  String downloadDirectory = '文件 App / VidSniffer Pro / videos';
  String cacheSize = '128 MB';
  bool parsing = false;
  bool browserLoading = false;
  String browserUrl = 'https://example.com/video';

  bool get restored => _restored;

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
          size: '原始文件',
          url: url,
        ),
        VideoResource(
          title: '${_titleFromUrl(url)} · 备用线路',
          quality: '720P HLS',
          size: '在线播放',
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
        size: '在线播放',
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
      speed: '准备下载',
      progress: 0,
    );
    downloads.insert(0, task);
    _saveDownloads();
    notifyListeners();
    unawaited(_downloadToLocal(task));
  }

  void toggleDownload(DownloadTask task) {
    if (task.completed || task.error.isNotEmpty) {
      return;
    }
    task.paused = !task.paused;
    task.speed = task.paused ? '已暂停' : '下载中';
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
    if (file.localPath.isNotEmpty) {
      unawaited(File(file.localPath).delete().catchError((_) => File(file.localPath)));
    }
    _saveFiles();
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

  Future<void> _downloadToLocal(DownloadTask task) async {
    final uri = Uri.tryParse(task.url);
    if (uri == null || !uri.hasScheme) {
      await _failTask(task, '不是可下载的视频直链');
      return;
    }

    if (_isHls(task)) {
      await _downloadHlsToMp4(task, uri);
      return;
    }

    try {
      task.speed = '连接中';
      notifyListeners();
      final dir = await _videosDirectory();
      final file = File('${dir.path}/${_safeFileName(task, _extensionFromUrl(task.url))}');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 18);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _mobileUserAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'video/*,application/octet-stream,*/*');
      request.headers.set(HttpHeaders.refererHeader, _originForUri(uri));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        client.close(force: true);
        await _failTask(task, '下载失败：HTTP ${response.statusCode}');
        return;
      }
      if (_isHtmlResponse(response)) {
        client.close(force: true);
        await _failTask(task, '下载地址返回的是网页，不是视频文件直链');
        return;
      }

      final total = response.contentLength;
      var received = 0;
      IOSink? sink;
      var checkedFirstChunk = false;
      final started = DateTime.now();
      await for (final chunk in response) {
        if (!checkedFirstChunk) {
          checkedFirstChunk = true;
          if (_looksLikeHtml(chunk)) {
            client.close(force: true);
            await _failTask(task, '下载地址返回的是网页，不是视频文件直链');
            return;
          }
          sink = file.openWrite();
        }
        while (task.paused) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        received += chunk.length;
        sink!.add(chunk);
        if (total > 0) {
          task.progress = (received / total).clamp(0.0, 1.0).toDouble();
        } else {
          task.progress = (task.progress + 0.01).clamp(0.0, 0.94).toDouble();
        }
        final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
        final mbps = seconds <= 0 ? 0 : received / seconds / 1024 / 1024;
        task.speed = '${mbps.toStringAsFixed(1)} MB/s';
        notifyListeners();
      }
      await sink?.close();
      client.close(force: true);
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      if (!fileExists || fileSize == 0) {
        await _failTask(task, '没有收到可保存的视频数据');
        return;
      }

      task.completed = true;
      task.progress = 1;
      task.speed = '已完成';
      task.localPath = file.path;
      task.size = _formatBytes(fileSize);
      _addFileForTask(task, localPath: file.path);
      await _saveDownloads();
      await _saveFiles();
      notifyListeners();
    } catch (error) {
      await _failTask(task, '下载失败：$error');
    }
  }

  Future<void> _downloadHlsToMp4(DownloadTask task, Uri uri) async {
    try {
      task.speed = '合并 m3u8';
      task.progress = 0.08;
      notifyListeners();

      final dir = await _videosDirectory();
      final output = File('${dir.path}/${_safeFileName(task, 'mp4')}');
      if (await output.exists()) {
        await output.delete();
      }

      final command = [
        '-y',
        '-user_agent',
        _ffmpegQuote(_mobileUserAgent),
        '-headers',
        _ffmpegQuote('Referer: ${_originForUri(uri)}'),
        '-i',
        _ffmpegQuote(task.url),
        '-c',
        'copy',
        '-movflags',
        '+faststart',
        _ffmpegQuote(output.path),
      ].join(' ');

      final completer = Completer<bool>();
      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode = await session.getReturnCode();
          completer.complete(ReturnCode.isSuccess(returnCode));
        },
      );

      final success = await completer.future;
      final outputExists = await output.exists();
      final outputSize = outputExists ? await output.length() : 0;
      if (!success || !outputExists || outputSize == 0) {
        if (outputExists) {
          await output.delete();
        }
        await _failTask(task, 'm3u8 合并失败，未生成 mp4 文件');
        return;
      }

      task.completed = true;
      task.progress = 1;
      task.speed = '已完成';
      task.localPath = output.path;
      task.size = _formatBytes(outputSize);
      _addFileForTask(task, localPath: output.path);
      await _saveDownloads();
      await _saveFiles();
      notifyListeners();
    } catch (error) {
      await _failTask(task, 'm3u8 合并失败：$error');
    }
  }

  Future<void> _failTask(DownloadTask task, String message) async {
    task.error = message;
    task.speed = message;
    task.paused = true;
    await _saveDownloads();
    notifyListeners();
  }

  void _addFileForTask(DownloadTask task, {required String localPath}) {
    files.removeWhere((file) => file.sourceUrl == task.url || (localPath.isNotEmpty && file.localPath == localPath));
    files.insert(
      0,
      LocalVideo(
        title: localPath.isNotEmpty ? _baseName(localPath) : _fileNameFor(task),
        duration: '00:00',
        size: task.size,
        thumbnail: 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?w=600',
        sourceUrl: task.url,
        localPath: localPath,
      ),
    );
  }

  Future<Directory> _videosDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/videos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
      downloadDirectory = settings['downloadDirectory'] as String? ?? downloadDirectory;
      cacheSize = settings['cacheSize'] as String? ?? cacheSize;
    }
    if (downloadDirectory.contains('Downloads')) {
      downloadDirectory = '文件 App / VidSniffer Pro / videos';
    }
    await _refreshFilesFromDisk();

    _restored = true;
    notifyListeners();
  }

  Future<void> _refreshFilesFromDisk() async {
    final dir = await _videosDirectory();
    await _migrateLegacyDownloads(dir);
    final knownByPath = {for (final file in files) file.localPath: file};
    final refreshed = <LocalVideo>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !_isVideoFile(entity.path)) {
        continue;
      }
      final stat = await entity.stat();
      final existing = knownByPath[entity.path];
      refreshed.add(
        LocalVideo(
          title: existing?.title ?? _baseName(entity.path),
          duration: existing?.duration ?? '00:00',
          size: _formatBytes(stat.size),
          thumbnail: existing?.thumbnail ?? 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?w=600',
          sourceUrl: existing?.sourceUrl ?? '',
          localPath: entity.path,
        ),
      );
    }

    for (final file in files) {
      if (file.localPath.isEmpty || refreshed.any((item) => item.localPath == file.localPath)) {
        continue;
      }
      if (await File(file.localPath).exists()) {
        refreshed.add(file);
      }
    }

    files
      ..clear()
      ..addAll(refreshed);
    await _saveFiles();
  }

  Future<void> _migrateLegacyDownloads(Directory videosDir) async {
    final docs = await getApplicationDocumentsDirectory();
    final legacyDir = Directory('${docs.path}/Downloads');
    if (!await legacyDir.exists()) {
      return;
    }

    await for (final entity in legacyDir.list()) {
      if (entity is! File || !_isVideoFile(entity.path)) {
        continue;
      }
      final target = File('${videosDir.path}/${_baseName(entity.path)}');
      if (!await target.exists()) {
        await entity.rename(target.path);
      }
    }
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
        'downloadDirectory': downloadDirectory,
        'cacheSize': cacheSize,
      }),
    );
  }

  bool _isHls(DownloadTask task) {
    final lower = '${task.quality} ${task.url}'.toLowerCase();
    return lower.contains('hls') || lower.contains('m3u8');
  }

  bool _isHtmlResponse(HttpClientResponse response) {
    final mimeType = response.headers.contentType?.mimeType.toLowerCase() ?? '';
    return mimeType == 'text/html' || mimeType == 'application/xhtml+xml';
  }

  bool _looksLikeHtml(List<int> bytes) {
    final sample = utf8.decode(bytes.take(512).toList(), allowMalformed: true).trimLeft().toLowerCase();
    return sample.startsWith('<!doctype html') || sample.startsWith('<html') || sample.contains('<head') || sample.contains('<body');
  }

  String _safeFileName(DownloadTask task, [String? extension]) {
    final ext = extension ?? 'mp4';
    final base = task.title.replaceAll(RegExp(r'[^a-zA-Z0-9._\-\u4e00-\u9fa5]+'), '_').replaceAll(RegExp('_+'), '_');
    final name = base.isEmpty ? 'video' : base;
    return '${name}_${task.id}.$ext';
  }

  String _fileNameFor(DownloadTask task) => _safeFileName(task);

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  bool _isVideoFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.ts');
  }

  String _extensionFromUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.webm')) {
      return 'webm';
    }
    if (path.endsWith('.mov')) {
      return 'mov';
    }
    if (path.endsWith('.mkv')) {
      return 'mkv';
    }
    if (path.endsWith('.m4v')) {
      return 'm4v';
    }
    if (path.endsWith('.ts')) {
      return 'ts';
    }
    return 'mp4';
  }

  String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  String _originForUri(Uri uri) => uri.replace(path: '/', query: '', fragment: '').toString();

  String _ffmpegQuote(String value) => '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  static const _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

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
