import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/download_task.dart';
import '../models/video_resource.dart';
import 'file_utils.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager();

  static const MethodChannel _backgroundChannel = MethodChannel('web_video_downloader/background_task');

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
    followRedirects: true,
  ));
  final List<DownloadTask> tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, FFmpegSession> _ffmpegSessions = {};
  final Map<String, File> _partFiles = {};

  DownloadTask createTask(VideoResource resource) {
    return DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      resource: resource,
      message: '准备中',
    );
  }

  void addTask(DownloadTask task) {
    tasks.removeWhere((item) => item.id == task.id);
    tasks.insert(0, task);
    notifyListeners();
  }

  DownloadTask enqueue(VideoResource resource) {
    final task = createTask(resource);
    addTask(task);
    unawaited(start(task.id));
    return task;
  }

  Future<void> start(String taskId) async {
    final task = _taskById(taskId);
    if (task == null) {
      return;
    }
    debugPrint('[download] start task=${task.id}');
    task.status = DownloadStatus.preparing;
    task.message = '准备中';
    task.errorMessage = '';
    notifyListeners();

    final backgroundId = await _beginBackgroundTask();
    try {
      task.status = DownloadStatus.downloading;
      task.message = task.resource.isMergeRequired ? '正在合并为 mp4' : '正在下载';
      notifyListeners();

      if (task.resource.isMergeRequired) {
        await _downloadWithFFmpeg(task);
      } else {
        await _downloadDirect(task);
      }
      if (task.status == DownloadStatus.paused || task.status == DownloadStatus.canceled) {
        return;
      }

      final file = File(task.localPath);
      final size = await file.length();
      debugPrint('[download] completed file=${file.path} size=$size');
      task.status = DownloadStatus.completed;
      task.progress = 1;
      task.receivedBytes = size;
      task.totalBytes = size;
      task.speed = '完成';
      task.remaining = '00:00';
      task.message = '下载完成';
      notifyListeners();
    } catch (error) {
      debugPrint('[download] failed error=$error');
      if (task.status != DownloadStatus.paused && task.status != DownloadStatus.canceled) {
        task.status = DownloadStatus.failed;
      }
      task.errorMessage = '$error';
      task.message = task.status == DownloadStatus.paused ? '已暂停' : (task.status == DownloadStatus.canceled ? '已取消' : '下载失败');
      notifyListeners();
    } finally {
      _cancelTokens.remove(task.id);
      _ffmpegSessions.remove(task.id);
      await _endBackgroundTask(backgroundId);
    }
  }

  Future<void> retry(DownloadTask task) async {
    if (!task.canRetry) {
      return;
    }
    task.progress = 0;
    task.status = DownloadStatus.preparing;
    task.message = '准备重试';
    task.errorMessage = '';
    task.receivedBytes = 0;
    task.totalBytes = 0;
    task.speed = '--';
    task.remaining = '--';
    notifyListeners();
    await start(task.id);
  }

  Future<void> pause(DownloadTask task) async {
    if (!task.isActive) {
      return;
    }
    _cancelTokens[task.id]?.cancel('paused');
    if (_ffmpegSessions[task.id] != null) {
      await FFmpegKit.cancel();
    }
    task.status = DownloadStatus.paused;
    task.message = '已暂停，可继续';
    notifyListeners();
  }

  Future<void> cancel(DownloadTask task) async {
    task.status = DownloadStatus.canceled;
    task.message = '已取消';
    _cancelTokens[task.id]?.cancel('canceled');
    if (_ffmpegSessions[task.id] != null) {
      await FFmpegKit.cancel();
    }
    final partFile = _partFiles.remove(task.id);
    if (partFile != null && await partFile.exists()) {
      await partFile.delete().catchError((_) => partFile);
    }
    tasks.removeWhere((item) => item.id == task.id);
    notifyListeners();
  }

  Future<void> _downloadDirect(DownloadTask task) async {
    final dir = await FileUtils.videosDirectory();
    final extension = FileUtils.extensionFromUrl(task.resource.url);
    final finalFile = File(p.join(dir.path, _targetName(task.resource, extension == 'm3u8' ? 'mp4' : extension)));
    final partFile = File('${finalFile.path}.part');
    _partFiles[task.id] = partFile;

    if (!await partFile.parent.exists()) {
      await partFile.parent.create(recursive: true);
    }

    final resumeFrom = await partFile.exists() ? await partFile.length() : 0;
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;
    final startedAt = DateTime.now();

    debugPrint('[download] request url=${task.resource.url}');
    debugPrint('[download] save path=${finalFile.path}');

    final response = await _dio.get<ResponseBody>(
      task.resource.url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          ..._headersFor(task.resource),
          if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
        },
      ),
    );
    final statusCode = response.statusCode ?? 0;
    if (resumeFrom > 0 && statusCode != 206) {
      await partFile.delete().catchError((_) => partFile);
      return _downloadDirect(task);
    }

    final sink = partFile.openWrite(mode: resumeFrom > 0 ? FileMode.append : FileMode.write);
    try {
      final contentLength = _contentLength(response.headers) + resumeFrom;
      var received = resumeFrom;
      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) {
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        _updateProgress(task, received, contentLength, startedAt);
      }
    } finally {
      await sink.close();
    }

    if (task.status == DownloadStatus.paused || task.status == DownloadStatus.canceled) {
      return;
    }
    if (await FileUtils.looksLikeHtml(partFile)) {
      await partFile.delete().catchError((_) => partFile);
      throw StateError('解析到的是网页，不是视频文件');
    }
    if (!await partFile.exists() || await partFile.length() <= 0) {
      throw StateError('没有写入有效视频文件');
    }
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await partFile.rename(finalFile.path);
    task.localPath = finalFile.path;
  }

  Future<void> _downloadWithFFmpeg(DownloadTask task) async {
    final dir = await FileUtils.videosDirectory();
    final output = File(p.join(dir.path, _targetName(task.resource, 'mp4')));
    if (await output.exists()) {
      await output.delete();
    }
    debugPrint('[download] request url=${task.resource.url}');
    debugPrint('[download] save path=${output.path}');

    final command = [
      '-y',
      '-headers ${_shellQuote(_ffmpegHeaders(task.resource))}',
      '-i ${_shellQuote(task.resource.url)}',
      '-c copy',
      '-movflags +faststart',
      _shellQuote(output.path),
    ].join(' ');

    final logs = StringBuffer();
    final completer = Completer<void>();
    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          completer.complete();
        } else {
          completer.completeError(StateError('ffmpeg 合并失败：${logs.toString().trim()}'));
        }
      },
      (log) {
        final message = log.getMessage().trim();
        if (message.isEmpty) {
          return;
        }
        logs.writeln(message);
        task.message = '合并中';
        notifyListeners();
      },
      (statistics) {
        final timeMs = statistics.getTime();
        if (timeMs > 0) {
          task.progress = (task.progress + 0.01).clamp(0.02, 0.95).toDouble();
          task.message = '合并中 ${(timeMs / 1000).toStringAsFixed(0)}s';
          notifyListeners();
        }
      },
    );
    _ffmpegSessions[task.id] = session;
    await completer.future;

    if (task.status == DownloadStatus.paused || task.status == DownloadStatus.canceled) {
      return;
    }
    if (!await output.exists() || await output.length() <= 0) {
      throw StateError('m3u8 没有合并出有效 mp4 文件');
    }
    if (await FileUtils.looksLikeHtml(output)) {
      await output.delete().catchError((_) => output);
      throw StateError('解析到的是网页，不是视频文件');
    }
    task.localPath = output.path;
  }

  void _updateProgress(DownloadTask task, int received, int total, DateTime startedAt) {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds / 1000;
    final speedBytes = elapsed <= 0 ? 0 : received / elapsed;
    task.receivedBytes = received;
    task.totalBytes = total;
    task.progress = total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;
    task.speed = speedBytes <= 0 ? '--' : '${_formatBytes(speedBytes.round())}/s';
    task.remaining = total > 0 && speedBytes > 0 ? _formatDuration(Duration(seconds: ((total - received) / speedBytes).ceil())) : '--';
    task.message = total > 0 ? '${_formatBytes(received)} / ${_formatBytes(total)}' : _formatBytes(received);
    debugPrint('[download] progress=$received/$total');
    notifyListeners();
  }

  int _contentLength(Headers headers) {
    final value = headers.value(HttpHeaders.contentLengthHeader);
    return int.tryParse(value ?? '') ?? 0;
  }

  DownloadTask? _taskById(String id) {
    for (final task in tasks) {
      if (task.id == id) {
        return task;
      }
    }
    return null;
  }

  String _targetName(VideoResource resource, String extension) {
    final base = FileUtils.safeFileName(resource.title, fallback: 'video');
    return '$base-${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Map<String, String> _headersFor(VideoResource resource) {
    return {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      if (resource.pageUrl.isNotEmpty) 'Referer': resource.pageUrl,
    };
  }

  String _ffmpegHeaders(VideoResource resource) {
    return _headersFor(resource).entries.map((entry) => '${entry.key}: ${entry.value}\\r\\n').join();
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<int?> _beginBackgroundTask() async {
    try {
      return await _backgroundChannel.invokeMethod<int>('begin');
    } catch (_) {
      return null;
    }
  }

  Future<void> _endBackgroundTask(int? id) async {
    if (id == null) return;
    try {
      await _backgroundChannel.invokeMethod<void>('end', id);
    } catch (_) {}
  }
}
