import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/download_task.dart';
import '../models/video_resource.dart';
import 'file_utils.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager();

  static const MethodChannel _backgroundChannel = MethodChannel('web_video_downloader/background_task');

  final Dio _dio = Dio(BaseOptions(followRedirects: true, receiveTimeout: const Duration(minutes: 5)));
  final List<DownloadTask> tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, FFmpegSession> _ffmpegSessions = {};

  DownloadTask enqueue(VideoResource resource) {
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      resource: resource,
      message: resource.isMergeRequired ? '等待合并为 mp4' : '等待下载',
    );
    tasks.insert(0, task);
    notifyListeners();
    unawaited(_run(task));
    return task;
  }

  Future<void> retry(DownloadTask task) async {
    if (!task.canRetry) {
      return;
    }
    task.progress = 0;
    task.status = DownloadStatus.queued;
    task.message = '重新开始';
    task.localPath = '';
    notifyListeners();
    await _run(task);
  }

  Future<void> pause(DownloadTask task) async {
    if (!task.isActive) {
      return;
    }
    _cancelTokens[task.id]?.cancel('paused');
    final session = _ffmpegSessions[task.id];
    if (session != null) {
      await FFmpegKit.cancel();
    }
    task.status = DownloadStatus.paused;
    task.message = '已暂停，可重试继续';
    notifyListeners();
  }

  Future<void> cancel(DownloadTask task) async {
    _cancelTokens[task.id]?.cancel('canceled');
    final session = _ffmpegSessions[task.id];
    if (session != null) {
      await FFmpegKit.cancel();
    }
    task.status = DownloadStatus.canceled;
    task.message = '已取消';
    notifyListeners();
  }

  Future<void> _run(DownloadTask task) async {
    task.status = DownloadStatus.running;
    task.message = task.resource.isMergeRequired ? '正在合并为 mp4' : '正在下载';
    notifyListeners();

    final backgroundId = await _beginBackgroundTask();
    try {
      if (task.resource.isMergeRequired) {
        await _downloadWithFFmpeg(task);
      } else {
        await _downloadDirect(task);
      }
      task.status = DownloadStatus.completed;
      task.progress = 1;
      task.message = '完成';
      notifyListeners();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        if (task.status != DownloadStatus.paused && task.status != DownloadStatus.canceled) {
          task.status = DownloadStatus.canceled;
          task.message = '已取消';
        }
      } else {
        task.status = DownloadStatus.failed;
        task.message = '下载失败：${error.message ?? error.type.name}';
      }
      notifyListeners();
    } catch (error) {
      if (task.status != DownloadStatus.paused && task.status != DownloadStatus.canceled) {
        task.status = DownloadStatus.failed;
        task.message = '失败：$error';
        notifyListeners();
      }
    } finally {
      _cancelTokens.remove(task.id);
      _ffmpegSessions.remove(task.id);
      await _endBackgroundTask(backgroundId);
    }
  }

  Future<void> _downloadDirect(DownloadTask task) async {
    final dir = await FileUtils.videosDirectory();
    final ext = FileUtils.extensionFromUrl(task.resource.url);
    final name = _targetName(task.resource, ext == 'm3u8' ? 'mp4' : ext);
    final target = File(p.join(dir.path, name));
    final token = CancelToken();
    _cancelTokens[task.id] = token;

    await _dio.download(
      task.resource.url,
      target.path,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.bytes,
        headers: _headersFor(task.resource),
      ),
      onReceiveProgress: (received, total) {
        if (total > 0) {
          task.progress = (received / total).clamp(0, 1);
          task.message = '${_formatBytes(received)} / ${_formatBytes(total)}';
          notifyListeners();
        }
      },
    );

    if (await FileUtils.looksLikeHtml(target)) {
      await target.delete().catchError((_) => target);
      throw StateError('下载地址返回 HTML 页面，不是视频文件');
    }
    if (!await target.exists() || await target.length() == 0) {
      throw StateError('没有保存到有效视频数据');
    }
    task.localPath = target.path;
  }

  Future<void> _downloadWithFFmpeg(DownloadTask task) async {
    final dir = await FileUtils.videosDirectory();
    final target = File(p.join(dir.path, _targetName(task.resource, 'mp4')));
    if (await target.exists()) {
      await target.delete();
    }

    final command = [
      '-y',
      '-hide_banner',
      '-loglevel warning',
      '-headers ${_shellQuote(_ffmpegHeaders(task.resource))}',
      '-i ${_shellQuote(task.resource.url)}',
      '-map 0:v:0?',
      '-map 0:a:0?',
      '-c copy',
      '-bsf:a aac_adtstoasc',
      '-movflags +faststart',
      _shellQuote(target.path),
    ].join(' ');

    final completer = Completer<void>();
    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          completer.complete();
        } else {
          completer.completeError(StateError('ffmpeg 合并失败，可能是加密 HLS、DRM 或不可访问资源'));
        }
      },
      (log) {
        final line = log.getMessage().trim();
        if (line.isNotEmpty) {
          task.message = '合并中：$line';
          notifyListeners();
        }
      },
      (statistics) {
        final time = statistics.getTime();
        if (time > 0) {
          task.progress = (task.progress + 0.015).clamp(0.05, 0.95);
          task.message = '合并中 ${(time / 1000).toStringAsFixed(0)}s';
          notifyListeners();
        }
      },
    );
    _ffmpegSessions[task.id] = session;
    await completer.future;

    if (!await target.exists() || await target.length() == 0) {
      throw StateError('m3u8 没有合并出有效 mp4 文件');
    }
    if (await FileUtils.looksLikeHtml(target)) {
      await target.delete().catchError((_) => target);
      throw StateError('合并结果不是视频文件');
    }
    task.localPath = target.path;
  }

  String _targetName(VideoResource resource, String extension) {
    final base = FileUtils.safeFileName(resource.title, fallback: 'video');
    return '$base-${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Map<String, String> _headersFor(VideoResource resource) {
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
    };
    if (resource.pageUrl.isNotEmpty) {
      headers['Referer'] = resource.pageUrl;
    }
    return headers;
  }

  String _ffmpegHeaders(VideoResource resource) {
    final headers = _headersFor(resource);
    return headers.entries.map((entry) => '${entry.key}: ${entry.value}\\r\\n').join();
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  String _formatBytes(int value) {
    if (value < 1024) {
      return '$value B';
    }
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  Future<int?> _beginBackgroundTask() async {
    try {
      return await _backgroundChannel.invokeMethod<int>('begin');
    } catch (_) {
      return null;
    }
  }

  Future<void> _endBackgroundTask(int? id) async {
    if (id == null) {
      return;
    }
    try {
      await _backgroundChannel.invokeMethod<void>('end', id);
    } catch (_) {}
  }
}
