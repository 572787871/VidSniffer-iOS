import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/download_task.dart';
import '../models/video_resource.dart';
import 'download_task_store.dart';
import 'file_utils.dart';
import 'local_library.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager();

  static const MethodChannel _backgroundChannel = MethodChannel(
    'web_video_downloader/background_task',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  final List<DownloadTask> tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, FFmpegSession> _ffmpegSessions = {};
  final Map<String, File> _partFiles = {};
  final DownloadTaskStore _taskStore = DownloadTaskStore();
  Timer? _persistTimer;
  bool _restoring = false;

  @override
  void notifyListeners() {
    if (!_restoring) {
      _schedulePersist();
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    unawaited(_persistNow());
    super.dispose();
  }

  Future<void> restoreTasks() async {
    _restoring = true;
    try {
      final restored = await _taskStore.load();
      for (final task in restored) {
        if (task.isActive) {
          task.status = DownloadStatus.paused;
          task.phase = DownloadPhase.preparing;
          task.isIndeterminate = false;
          task.message = '上次下载中断，可继续';
          task.remaining = '剩余时间未知';
        }
        if (task.status == DownloadStatus.completed) {
          final file = File(task.localPath);
          if (task.localPath.isEmpty || !await file.exists()) {
            task.status = DownloadStatus.missing;
            task.phase = DownloadPhase.failed;
            task.message = '文件已不存在';
            task.errorMessage = '文件已不存在';
            task.isIndeterminate = false;
          }
        }
      }
      tasks
        ..clear()
        ..addAll(restored);
    } finally {
      _restoring = false;
    }
    notifyListeners();
    for (final task in tasks.where((item) => item.status == DownloadStatus.idle)) {
      _startNextQueuedFor(task);
    }
  }

  DownloadTask createTask(VideoResource resource) {
    return DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      resource: resource,
      message: '准备中',
      phase: DownloadPhase.preparing,
    );
  }

  void addTask(DownloadTask task) {
    tasks.removeWhere((item) => item.id == task.id);
    tasks.removeWhere(
      (item) =>
          item.resource.normalizedUrl == task.resource.normalizedUrl &&
          item.status == DownloadStatus.failed,
    );
    tasks.insert(0, task);
    notifyListeners();
  }

  DownloadTask enqueue(VideoResource resource) {
    final task = createTask(resource);
    final busy = _hasActiveDownloadFor(resource);
    if (busy) {
      task.status = DownloadStatus.idle;
      task.message = '同站点任务排队中';
      task.remaining = '等待前一个任务';
    }
    addTask(task);
    if (!busy) unawaited(start(task.id));
    return task;
  }

  String previewPathFor(DownloadTask task) {
    final file = _partFiles[task.id];
    if (file != null) return file.path;
    return task.tempPath;
  }

  Future<bool> canPreviewPartial(DownloadTask task) async {
    if (task.resource.isPlayable &&
        (task.isActive || task.status == DownloadStatus.paused)) {
      return true;
    }
    final path = previewPathFor(task);
    if (path.isEmpty) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    if (await file.length() < 256 * 1024) return false;
    if (await FileUtils.looksLikeHtml(file)) return false;
    return true;
  }

  Future<void> start(String taskId) async {
    final task = _taskById(taskId);
    if (task == null) {
      return;
    }
    debugPrint('[download] start task=${task.id}');
    final resuming = task.tempPath.isNotEmpty;
    task.status = DownloadStatus.preparing;
    task.message = '准备中';
    task.phase = DownloadPhase.preparing;
    task.errorMessage = '';
    task.errorDetails = '';
    task.isIndeterminate = false;
    task.ffmpegLog = '';
    task.ffmpegTime = '--';
    task.ffmpegSpeed = '--';
    if (!resuming) {
      task.downloadedSegments = 0;
      task.totalSegments = 0;
      task.tempPath = '';
      task.outputDirectory = '';
      task.playlistDuration = Duration.zero;
      task.elapsed = Duration.zero;
    }
    task.completedAt = null;
    notifyListeners();

    final backgroundId = await _beginBackgroundTask();
    try {
      task.status = DownloadStatus.downloading;
      task.phase = task.resource.isMergeRequired
          ? DownloadPhase.fetchingPlaylist
          : DownloadPhase.downloadingFile;
      task.message = task.resource.isMergeRequired ? '正在获取播放列表' : '正在下载';
      task.isIndeterminate = task.resource.isMergeRequired;
      notifyListeners();

      if (task.resource.isMergeRequired) {
        await _downloadWithFFmpeg(task);
      } else {
        await _downloadDirect(task);
      }
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.canceled) {
        return;
      }

      final file = File(task.localPath);
      final size = await file.length();
      debugPrint('[download] completed file=${file.path} size=$size');
      task.status = DownloadStatus.completed;
      task.phase = DownloadPhase.completed;
      task.progress = 1;
      task.isIndeterminate = false;
      task.receivedBytes = size;
      task.totalBytes = size;
      task.speed = '完成';
      task.remaining = '00:00';
      task.message = '下载完成';
      task.tempPath = '';
      task.completedAt = DateTime.now();
      unawaited(
        LocalLibrary().writeDownloadMetadata(task.localPath, task.resource),
      );
      unawaited(_writePageMetadata(task));
      notifyListeners();
    } catch (error) {
      debugPrint('[download] failed error=$error');
      if (task.status != DownloadStatus.paused &&
          task.status != DownloadStatus.canceled) {
        task.status = DownloadStatus.failed;
        task.phase = DownloadPhase.failed;
      }
      task.isIndeterminate = false;
      task.errorDetails = _errorDetails(error, task);
      task.errorMessage = _errorSummary(error);
      task.message = task.status == DownloadStatus.paused
          ? '已暂停'
          : (task.status == DownloadStatus.canceled ? '已取消' : '下载失败');
      notifyListeners();
    } finally {
      _cancelTokens.remove(task.id);
      _ffmpegSessions.remove(task.id);
      if (task.status != DownloadStatus.paused) {
        _partFiles.remove(task.id);
      }
      await _endBackgroundTask(backgroundId);
      _startNextQueuedFor(task);
    }
  }

  Future<void> retry(DownloadTask task) async {
    if (!task.canRetry) {
      return;
    }
    final resuming = task.status == DownloadStatus.paused &&
        task.tempPath.isNotEmpty;
    if (!resuming) task.progress = 0;
    task.status = DownloadStatus.preparing;
    task.phase = DownloadPhase.preparing;
    task.message = '准备重试';
    task.errorMessage = '';
    task.errorDetails = '';
    if (!resuming) {
      task.receivedBytes = 0;
      task.totalBytes = 0;
    }
    task.speed = '--';
    task.remaining = '剩余时间未知';
    task.isIndeterminate = false;
    task.ffmpegLog = '';
    task.ffmpegTime = '--';
    task.ffmpegSpeed = '--';
    if (!resuming) {
      task.downloadedSegments = 0;
      task.totalSegments = 0;
    }
    notifyListeners();
    await start(task.id);
  }

  Future<void> pause(DownloadTask task) async {
    if (!task.isActive) {
      return;
    }
    task.status = DownloadStatus.paused;
    task.isIndeterminate = false;
    task.message = '正在暂停…';
    notifyListeners();
    _cancelTokens[task.id]?.cancel('paused');
    if (_ffmpegSessions[task.id] != null) {
      await FFmpegKit.cancel();
    }
    task.message = '已暂停，可继续';
    notifyListeners();
  }

  Future<void> cancel(DownloadTask task) async {
    task.status = DownloadStatus.canceled;
    task.phase = DownloadPhase.canceled;
    task.isIndeterminate = false;
    task.message = '已取消';
    _cancelTokens[task.id]?.cancel('canceled');
    if (_ffmpegSessions[task.id] != null) {
      await FFmpegKit.cancel();
    }
    final partFile = _partFiles.remove(task.id);
    if (partFile != null && await partFile.exists()) {
      await partFile.delete().catchError((_) => partFile);
    }
    if (task.tempPath.isNotEmpty) {
      final file = File(task.tempPath);
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
      for (final prefix in ['range', 'range12-']) {
        for (var index = 0; index < 12; index++) {
          final rangeFile = File('${task.tempPath}.$prefix$index');
          if (await rangeFile.exists()) {
            await rangeFile.delete().catchError((_) => rangeFile);
          }
        }
      }
    }
    notifyListeners();
    _startNextQueuedFor(task);
  }

  bool _hasActiveDownloadFor(VideoResource resource) {
    final group = _downloadGroup(resource.url);
    return tasks.any(
      (task) =>
          task.isActive && _downloadGroup(task.resource.url) == group,
    );
  }

  void _startNextQueuedFor(DownloadTask finished) {
    final group = _downloadGroup(finished.resource.url);
    if (tasks.any(
      (task) =>
          task.isActive &&
          task.id != finished.id &&
          _downloadGroup(task.resource.url) == group,
    )) {
      return;
    }
    DownloadTask? next;
    for (final task in tasks.reversed) {
      if (task.status == DownloadStatus.idle &&
          _downloadGroup(task.resource.url) == group) {
        next = task;
        break;
      }
    }
    if (next == null) return;
    next.message = '排队结束，正在开始';
    next.remaining = '剩余时间未知';
    unawaited(start(next.id));
  }

  String _downloadGroup(String value) {
    final host = Uri.tryParse(value)?.host.toLowerCase() ?? value;
    final parts = host.split('.').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return host;
    return parts.sublist(parts.length - 2).join('.');
  }

  Future<void> removeTask(DownloadTask task) async {
    final shouldCancel =
        task.isActive || task.status == DownloadStatus.paused;
    tasks.removeWhere((item) => item.id == task.id);
    notifyListeners();
    if (shouldCancel) {
      await cancel(task);
    }
    await _persistNow();
  }

  Future<void> clearHistory() async {
    tasks.removeWhere((task) => !task.isActive);
    notifyListeners();
    await _persistNow();
  }

  Future<void> _downloadDirect(DownloadTask task) async {
    final dir = await FileUtils.videoPageDirectory(task.resource);
    task.outputDirectory = dir.path;
    final extension = FileUtils.extensionFromUrl(task.resource.url);
    final finalFile = File(
      p.join(
        dir.path,
        _targetName(task.resource, extension == 'm3u8' ? 'mp4' : extension),
      ),
    );
    final partFile = File('${finalFile.path}.part');
    _partFiles[task.id] = partFile;
    task.tempPath = partFile.path;

    if (!await partFile.parent.exists()) {
      await partFile.parent.create(recursive: true);
    }

    final resumeFrom = await partFile.exists() ? await partFile.length() : 0;
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;
    final startedAt = DateTime.now();

    task.phase = DownloadPhase.downloadingFile;
    task.isIndeterminate = false;
    notifyListeners();
    debugPrint('[download] request url=${task.resource.url}');
    debugPrint('[download] save path=${finalFile.path}');

    if (await _downloadMultipartDirect(
      task,
      finalFile,
      partFile,
      cancelToken,
      startedAt,
    )) {
      return;
    }

    late final Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        task.resource.url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            ..._headersFor(task.resource),
            'Range': 'bytes=$resumeFrom-',
          },
        ),
      );
    } on DioException catch (error) {
      if ((error.error is HandshakeException) ||
          error.message?.contains('HandshakeException') == true) {
        await _downloadWithHttpClient(
          task,
          finalFile,
          partFile,
          resumeFrom,
          startedAt,
        );
        return;
      }
      rethrow;
    }
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 400) {
      throw HttpException(
        'HTTP $statusCode，资源地址已过期或站点拒绝下载',
        uri: Uri.tryParse(task.resource.url),
      );
    }
    if (resumeFrom > 0 && statusCode != 206) {
      await partFile.delete().catchError((_) => partFile);
      return _downloadDirect(task);
    }

    final sink = partFile.openWrite(
      mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
    );
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

    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.canceled) {
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

  Future<bool> _downloadMultipartDirect(
    DownloadTask task,
    File finalFile,
    File mergedPart,
    CancelToken cancelToken,
    DateTime startedAt,
  ) async {
    var multipartStarted = false;
    try {
      var total = 0;
      var ranges = false;
      try {
        final head = await _dio.headUri(
          Uri.parse(task.resource.url),
          cancelToken: cancelToken,
          options: Options(
            headers: _headersFor(task.resource),
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        total = int.tryParse(
              head.headers.value(Headers.contentLengthHeader) ?? '',
            ) ??
            0;
        ranges = (head.headers.value(HttpHeaders.acceptRangesHeader) ?? '')
            .toLowerCase()
            .contains('bytes');
      } catch (_) {}
      if (!ranges || total <= 0) {
        final probe = await _dio.get<ResponseBody>(
          task.resource.url,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: {..._headersFor(task.resource), 'Range': 'bytes=0-0'},
            validateStatus: (status) => status == 206,
          ),
        );
        if (probe.statusCode == 206) {
          final contentRange =
              probe.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          total =
              int.tryParse(RegExp(r'/(\d+)$').firstMatch(contentRange)?.group(1) ?? '') ??
                  0;
          ranges = total > 0;
          await probe.data?.stream.drain<void>();
        }
      }
      if (!ranges || total < 20 * 1024 * 1024) return false;
      multipartStarted = true;

      const partCount = 12;
      final receivedByPart = List<int>.filled(partCount, 0);
      final files = <File>[];
      for (var index = 0; index < partCount; index++) {
        files.add(File('${mergedPart.path}.range12-$index'));
        if (await files[index].exists()) {
          receivedByPart[index] = await files[index].length();
        }
      }
      task.totalBytes = total;
      task.message = '正在多段加速下载';
      notifyListeners();

      await Future.wait(
        List.generate(partCount, (index) async {
          final start = (total * index / partCount).floor();
          final end = index == partCount - 1
              ? total - 1
              : (total * (index + 1) / partCount).floor() - 1;
          final existing = receivedByPart[index];
          if (start + existing > end) return;
          final response = await _dio.get<ResponseBody>(
            task.resource.url,
            cancelToken: cancelToken,
            options: Options(
              responseType: ResponseType.stream,
              headers: {
                ..._headersFor(task.resource),
                'Range': 'bytes=${start + existing}-$end',
              },
              validateStatus: (status) => status == 206,
            ),
          );
          if (response.statusCode != 206 || response.data == null) {
            throw StateError('站点未接受分段下载');
          }
          final sink = files[index].openWrite(
            mode: existing > 0 ? FileMode.append : FileMode.write,
          );
          try {
            await for (final chunk in response.data!.stream) {
              if (cancelToken.isCancelled) break;
              sink.add(chunk);
              receivedByPart[index] += chunk.length;
              final received = receivedByPart.fold<int>(
                0,
                (sum, value) => sum + value,
              );
              _updateProgress(task, received, total, startedAt);
            }
          } finally {
            await sink.close();
          }
        }),
      );
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.canceled) {
        return true;
      }
      for (var index = 0; index < partCount; index++) {
        final start = (total * index / partCount).floor();
        final end = index == partCount - 1
            ? total - 1
            : (total * (index + 1) / partCount).floor() - 1;
        if (!await files[index].exists() ||
            await files[index].length() != end - start + 1) {
          throw StateError('分段下载不完整');
        }
      }
      final sink = mergedPart.openWrite(mode: FileMode.write);
      try {
        for (final file in files) {
          await sink.addStream(file.openRead());
        }
      } finally {
        await sink.close();
      }
      if (await FileUtils.looksLikeHtml(mergedPart)) {
        throw StateError('解析到的是网页，不是视频文件');
      }
      if (await finalFile.exists()) await finalFile.delete();
      await mergedPart.rename(finalFile.path);
      task.localPath = finalFile.path;
      for (final file in files) {
        await file.delete().catchError((_) => file);
      }
      return true;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return true;
      if (!multipartStarted) return false;
      rethrow;
    }
  }

  Future<void> _downloadWithFFmpeg(DownloadTask task) async {
    final dir = await FileUtils.videoPageDirectory(task.resource);
    task.outputDirectory = dir.path;
    final output = File(p.join(dir.path, _targetName(task.resource, 'mp4')));
    final tempDir = Directory(p.join(dir.path, 'segments_tmp'));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    final tempOutput = File(
      task.tempPath.isNotEmpty
          ? task.tempPath
          : p.join(tempDir.path, '${task.id}.mp4'),
    );
    _partFiles[task.id] = tempOutput;
    task.tempPath = tempOutput.path;
    if (await output.exists()) {
      await output.delete();
    }
    debugPrint('[download] request url=${task.resource.url}');
    debugPrint('[download] save path=${output.path}');
    await _prefetchPlaylist(task);

    final resumeDuration = await _mediaDuration(tempOutput);
    final resumeBytes =
        await tempOutput.exists() ? await tempOutput.length() : 0;
    final isResume = resumeDuration > const Duration(seconds: 1);
    final resumeOutput = File(
      p.join(tempDir.path, '${task.id}.resume.mp4'),
    );
    final downloadOutput = isResume ? resumeOutput : tempOutput;
    if (await downloadOutput.exists()) {
      await downloadOutput.delete();
    }
    final remainingDuration = task.playlistDuration > resumeDuration
        ? task.playlistDuration - resumeDuration
        : Duration.zero;
    if (isResume) {
      task.receivedBytes = resumeBytes;
      task.progress = task.playlistDuration > Duration.zero
          ? (resumeDuration.inMilliseconds /
                  task.playlistDuration.inMilliseconds)
              .clamp(0, 0.95)
              .toDouble()
          : task.progress;
      task.message = '从 ${_formatDuration(resumeDuration)} 继续下载';
      notifyListeners();
    }
    final command = [
      '-y',
      '-headers ${_shellQuote(_ffmpegHeaders(task.resource))}',
      if (isResume) '-ss ${_ffmpegDurationSeconds(resumeDuration)}',
      '-i ${_shellQuote(task.resource.url)}',
      if (remainingDuration > Duration.zero)
        '-t ${_ffmpegDurationSeconds(remainingDuration)}'
      else if (!isResume && task.playlistDuration > Duration.zero)
        '-t ${_ffmpegDurationSeconds(task.playlistDuration)}',
      '-c copy',
      '-movflags +frag_keyframe+empty_moov+default_base_moof',
      _shellQuote(downloadOutput.path),
    ].join(' ');

    var logs = await _runFfmpeg(
      task,
      command,
      baseDuration: isResume ? resumeDuration : Duration.zero,
      baseBytes: isResume ? resumeBytes : 0,
    );
    if (task.status == DownloadStatus.paused) {
      if (isResume &&
          await resumeOutput.exists() &&
          await resumeOutput.length() > 0) {
        await _concatResumeParts(
          task,
          tempOutput,
          resumeOutput,
          allowPaused: true,
        );
      }
      return;
    }
    if (task.status == DownloadStatus.canceled) return;
    if (logs != null) {
      if (await downloadOutput.exists()) {
        await downloadOutput.delete().catchError((_) => downloadOutput);
      }
      final fallback = [
        '-y',
        '-headers ${_shellQuote(_ffmpegHeaders(task.resource))}',
        if (isResume) '-ss ${_ffmpegDurationSeconds(resumeDuration)}',
        '-i ${_shellQuote(task.resource.url)}',
        if (remainingDuration > Duration.zero)
          '-t ${_ffmpegDurationSeconds(remainingDuration)}'
        else if (!isResume && task.playlistDuration > Duration.zero)
          '-t ${_ffmpegDurationSeconds(task.playlistDuration)}',
        '-c:v copy',
        '-c:a aac',
        '-movflags +frag_keyframe+empty_moov+default_base_moof',
        _shellQuote(downloadOutput.path),
      ].join(' ');
      logs = await _runFfmpeg(
        task,
        fallback,
        baseDuration: isResume ? resumeDuration : Duration.zero,
        baseBytes: isResume ? resumeBytes : 0,
      );
    }
    if (task.status == DownloadStatus.paused) {
      if (isResume &&
          await resumeOutput.exists() &&
          await resumeOutput.length() > 0) {
        await _concatResumeParts(
          task,
          tempOutput,
          resumeOutput,
          allowPaused: true,
        );
      }
      return;
    }
    if (task.status == DownloadStatus.canceled) return;
    if (logs != null) {
      throw StateError('ffmpeg 合并失败：$logs');
    }

    if (isResume) {
      await _concatResumeParts(task, tempOutput, resumeOutput);
    }

    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.canceled) {
      return;
    }
    task.status = DownloadStatus.merging;
    task.phase = DownloadPhase.merging;
    task.message = '正在写入视频文件';
    task.isIndeterminate = true;
    task.downloadedSegments = task.totalSegments;
    task.progress = 0.99;
    task.remaining = '00:00';
    notifyListeners();
    if (!await tempOutput.exists() || await tempOutput.length() <= 0) {
      throw StateError('m3u8 没有合并出有效 mp4 文件');
    }
    if (await FileUtils.looksLikeHtml(tempOutput)) {
      await tempOutput.delete().catchError((_) => tempOutput);
      throw StateError('解析到的是网页，不是视频文件');
    }
    if (await output.exists()) {
      await output.delete();
    }
    await tempOutput.rename(output.path);
    task.localPath = output.path;
  }

  Future<String?> _runFfmpeg(
    DownloadTask task,
    String command, {
    Duration baseDuration = Duration.zero,
    int baseBytes = 0,
    bool trackProgress = true,
  }) async {
    final logs = StringBuffer();
    final completer = Completer<String?>();
    final startedAt = DateTime.now();
    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        completer.complete(
          ReturnCode.isSuccess(returnCode) ? null : logs.toString().trim(),
        );
      },
      (log) {
        if (_isTerminalOrPaused(task) || !trackProgress) return;
        final message = log.getMessage().trim();
        if (message.isEmpty) return;
        logs.writeln(message);
        _appendFfmpegLog(task, message);
        if (_looksLikeSegmentLog(message) && task.totalSegments > 0) {
          task.downloadedSegments = (task.downloadedSegments + 1).clamp(
            0,
            task.totalSegments,
          );
          task.progress = task.totalSegments > 0
              ? (task.downloadedSegments / task.totalSegments)
                  .clamp(0, 0.95)
                  .toDouble()
              : task.progress;
          task.isIndeterminate = task.totalSegments <= 0;
          task.phase = DownloadPhase.downloadingSegments;
          task.status = DownloadStatus.downloading;
          task.message =
              '正在下载分片 ${task.downloadedSegments}/${task.totalSegments}';
        }
        notifyListeners();
      },
      (statistics) {
        if (_isTerminalOrPaused(task) || !trackProgress) return;
        unawaited(_refreshPartialSize(task));
        final timeMs =
            baseDuration.inMilliseconds + statistics.getTime();
        final statisticsSize = statistics.getSize();
        if (statisticsSize > 0) {
          task.receivedBytes = baseBytes + statisticsSize;
        }
        task.elapsed = DateTime.now().difference(startedAt);
        if (timeMs > 0) {
          task.status = DownloadStatus.downloading;
          task.phase = DownloadPhase.downloadingSegments;
          task.ffmpegTime = _formatDuration(Duration(milliseconds: timeMs));
          task.ffmpegSpeed = statistics.getSpeed().toStringAsFixed(2);
          if (task.playlistDuration > Duration.zero) {
            final ratio =
                (timeMs / task.playlistDuration.inMilliseconds)
                    .clamp(0, 1)
                    .toDouble();
            task.progress = ratio
                .clamp(0, 0.95)
                .toDouble();
            if (task.totalSegments > 0) {
              task.downloadedSegments =
                  (ratio * task.totalSegments).floor().clamp(
                    task.downloadedSegments,
                    task.totalSegments,
                  );
            }
            task.isIndeterminate = false;
            final speed = statistics.getSpeed();
            final remainingMs = (task.playlistDuration.inMilliseconds - timeMs)
                .clamp(0, 1 << 31);
            task.remaining = speed > 0
                ? _formatDuration(
                    Duration(milliseconds: (remainingMs / speed).round()),
                  )
                : '剩余时间未知';
          } else {
            task.isIndeterminate = true;
            task.remaining = '剩余时间未知';
          }
          final elapsed = _formatDuration(DateTime.now().difference(startedAt));
          task.message =
              '下载/合并中 time=${task.ffmpegTime} speed=${task.ffmpegSpeed}x 已用 $elapsed';
          notifyListeners();
        }
      },
    );
    _ffmpegSessions[task.id] = session;
    return completer.future;
  }

  Future<Duration> _mediaDuration(File file) async {
    if (!await file.exists() || await file.length() <= 0) {
      return Duration.zero;
    }
    try {
      final session = await FFprobeKit.getMediaInformation(file.path);
      final seconds = double.tryParse(
            session.getMediaInformation()?.getDuration() ?? '',
          ) ??
          0;
      return seconds > 0
          ? Duration(milliseconds: (seconds * 1000).round())
          : Duration.zero;
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<void> _concatResumeParts(
    DownloadTask task,
    File original,
    File resumed,
    {bool allowPaused = false}
  ) async {
    if (!await original.exists() || !await resumed.exists()) {
      throw StateError('续传分片文件不存在');
    }
    final combined = File('${original.path}.combined.mp4');
    final listFile = File('${original.path}.concat.txt');
    if (await combined.exists()) await combined.delete();
    String concatPath(String value) =>
        value.replaceAll("'", r"'\''");
    await listFile.writeAsString(
      "file '${concatPath(original.path)}'\n"
      "file '${concatPath(resumed.path)}'\n",
      flush: true,
    );
    final logs = await _runFfmpeg(
      task,
      [
        '-y',
        '-f concat',
        '-safe 0',
        '-i ${_shellQuote(listFile.path)}',
        '-c copy',
        '-movflags +faststart',
        _shellQuote(combined.path),
      ].join(' '),
      trackProgress: false,
    );
    await listFile.delete().catchError((_) => listFile);
    if (task.status == DownloadStatus.canceled ||
        (task.status == DownloadStatus.paused && !allowPaused)) {
      return;
    }
    if (logs != null || !await combined.exists()) {
      throw StateError('续传文件拼接失败：${logs ?? '无输出文件'}');
    }
    await original.delete();
    await resumed.delete();
    await combined.rename(original.path);
  }

  Future<void> _prefetchPlaylist(DownloadTask task) async {
    task.phase = DownloadPhase.fetchingPlaylist;
    task.status = DownloadStatus.downloading;
    task.isIndeterminate = true;
    task.message = '正在获取播放列表';
    notifyListeners();
    try {
      final response = await _dio.get<String>(
        task.resource.url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _headersFor(task.resource),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final statusCode = response.statusCode ?? 0;
      final body = response.data ?? '';
      if (statusCode >= 400) {
        throw StateError(
          'm3u8 HTTP $statusCode，播放地址已过期或站点拒绝下载',
        );
      } else if (_looksLikeHtmlText(body)) {
        throw StateError('m3u8 返回了网页 HTML');
      } else {
        final count = body
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .where(
              (line) => RegExp(
                r'\.(?:ts|m4s|mp4|m4v|aac)(?:[?#]|$)',
                caseSensitive: false,
              ).hasMatch(line),
            )
            .length;
        task.totalSegments = count;
        task.downloadedSegments = 0;
        task.playlistDuration = _playlistDuration(body);
      }
    } on StateError catch (error) {
      _appendFfmpegLog(task, 'playlist prefetch failed: $error');
      rethrow;
    } catch (error) {
      // Keep FFmpeg as a fallback for transient preflight failures.
      _appendFfmpegLog(task, 'playlist prefetch failed: $error');
    }
    task.phase = DownloadPhase.downloadingSegments;
    task.status = DownloadStatus.downloading;
    task.message =
        task.totalSegments > 0 ? '正在下载分片 0/${task.totalSegments}' : '正在下载分片';
    notifyListeners();
  }

  void _appendFfmpegLog(DownloadTask task, String message) {
    final next =
        task.ffmpegLog.isEmpty ? message : '${task.ffmpegLog}\n$message';
    final lines = next.split('\n');
    task.ffmpegLog =
        lines.length > 20 ? lines.sublist(lines.length - 20).join('\n') : next;
  }

  String _errorSummary(Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('ffmpeg')) return 'm3u8 合并失败';
    if (text.contains('handshake') ||
        text.contains('connection') ||
        text.contains('network')) {
      return '网络连接失败';
    }
    if (text.contains('html') || text.contains('不是视频') || text.contains('无效')) {
      return '资源无效或已过期';
    }
    if (text.contains('403') || text.contains('401') || text.contains('拒绝')) {
      return '站点拒绝 App 下载';
    }
    return '下载失败，请查看详情';
  }

  String _errorDetails(Object error, DownloadTask task) {
    final lines = <String>[
      '$error',
      if (task.resource.url.isNotEmpty) 'URL: ${task.resource.url}',
      if (task.ffmpegLog.isNotEmpty) 'ffmpeg log:\n${task.ffmpegLog}',
      if ('$error'.contains('过期') ||
          '$error'.contains('403') ||
          '$error'.contains('401'))
        '请回到网页重新播放后再下载。',
    ];
    return lines.join('\n');
  }

  bool _looksLikeHtmlText(String value) {
    final lower = value.trimLeft().toLowerCase();
    return lower.startsWith('<!doctype html') ||
        lower.startsWith('<html') ||
        lower.contains('<body');
  }

  bool _looksLikeSegmentLog(String value) {
    final lower = value.toLowerCase();
    return lower.contains('.ts') || lower.contains('.m4s');
  }

  Duration _playlistDuration(String body) {
    var total = 0.0;
    final matches = RegExp(
      r'#EXTINF:([\d.]+)',
      caseSensitive: false,
    ).allMatches(body);
    for (final match in matches) {
      total += double.tryParse(match.group(1) ?? '') ?? 0;
    }
    return Duration(milliseconds: (total * 1000).round());
  }

  bool _isTerminalOrPaused(DownloadTask task) {
    return task.status == DownloadStatus.completed ||
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.canceled ||
        task.status == DownloadStatus.paused;
  }

  Future<void> _downloadWithHttpClient(
    DownloadTask task,
    File finalFile,
    File partFile,
    int resumeFrom,
    DateTime startedAt,
  ) async {
    final uri = Uri.parse(task.resource.url);
    final client = HttpClient();
    try {
      debugPrint('[download] request url=${task.resource.url}');
      debugPrint('[download] save path=${finalFile.path}');
      final request = await client.getUrl(uri);
      for (final entry in _headersFor(task.resource).entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (resumeFrom > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
      }
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final total =
          response.contentLength > 0 ? response.contentLength + resumeFrom : 0;
      var received = resumeFrom;
      final sink = partFile.openWrite(
        mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response) {
          if (task.status == DownloadStatus.paused ||
              task.status == DownloadStatus.canceled) {
            break;
          }
          sink.add(chunk);
          received += chunk.length;
          _updateProgress(task, received, total, startedAt);
        }
      } finally {
        await sink.close();
      }
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.canceled) {
        return;
      }
      if (await FileUtils.looksLikeHtml(partFile)) {
        await partFile.delete().catchError((_) => partFile);
        throw StateError('解析到的是网页，不是视频文件');
      }
      if (!await partFile.exists() || await partFile.length() <= 0) {
        throw StateError('没有写入有效视频文件');
      }
      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalFile.path);
      task.localPath = finalFile.path;
    } catch (e) {
      if (e is HandshakeException) {
        throw StateError('站点拒绝 App 直连下载，需要在网页内播放后再嗅探真实地址');
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  void _updateProgress(
    DownloadTask task,
    int received,
    int total,
    DateTime startedAt,
  ) {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds / 1000;
    task.elapsed = DateTime.now().difference(startedAt);
    final speedBytes = elapsed <= 0 ? 0 : received / elapsed;
    task.receivedBytes = received;
    task.totalBytes = total;
    task.progress = total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;
    task.phase = DownloadPhase.downloadingFile;
    task.isIndeterminate = total <= 0;
    task.speed =
        speedBytes <= 0 ? '--' : '${_formatBytes(speedBytes.round())}/s';
    task.remaining = total > 0 && speedBytes > 0
        ? _formatDuration(
            Duration(seconds: ((total - received) / speedBytes).ceil()),
          )
        : '剩余时间未知';
    task.message = total > 0
        ? '${_formatBytes(received)} / ${_formatBytes(total)}'
        : _formatBytes(received);
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
    final quality = resource.quality == '未知'
        ? ''
        : '-${FileUtils.safeFileName(resource.quality, fallback: '')}';
    return '$base$quality-${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Future<void> _writePageMetadata(DownloadTask task) async {
    if (task.outputDirectory.isEmpty) return;
    final file = File(p.join(task.outputDirectory, 'metadata.json'));
    final pageUri = Uri.tryParse(task.resource.pageUrl);
    final pageUrl = task.resource.pageUrl.isNotEmpty
        ? task.resource.pageUrl
        : task.resource.url;
    final collectionId = FileUtils.stableKey(pageUrl);
    final data = <String, dynamic>{
      'collectionId': collectionId,
      'pageUrl': task.resource.pageUrl,
      'pageTitle': task.resource.title,
      'sourceSite':
          pageUri?.host ?? Uri.tryParse(task.resource.url)?.host ?? '',
      'resourceId': task.resource.id,
      'quality': task.resource.quality,
      'format': task.resource.displayFormat,
      'durationMs': task.resource.duration.inMilliseconds,
      'downloadedAt': (task.completedAt ?? DateTime.now()).toIso8601String(),
      'filePath': task.localPath,
      'thumbnailPath': task.thumbnailPath,
      'selectedQuality': task.resource.quality,
      'downloadTime': DateTime.now().toIso8601String(),
      'files': [p.basename(task.localPath)],
      'resources': [_resourceMetadata(task.resource)],
      'headersSummary': {
        'hasUserAgent': task.resource.userAgent.isNotEmpty,
        'hasReferer': task.resource.referer.isNotEmpty,
        'hasCookie': task.resource.cookie.isNotEmpty,
        'hasOrigin': task.resource.origin.isNotEmpty,
      },
    };
    if (await file.exists()) {
      try {
        final existing = jsonDecode(await file.readAsString());
        if (existing is Map<String, dynamic>) {
          final files = [
            ...((existing['files'] as List?) ?? const []),
            p.basename(task.localPath),
          ].map((item) => item.toString()).toSet().toList();
          final resources = [
            ...((existing['resources'] as List?) ?? const []),
            _resourceMetadata(task.resource),
          ];
          data['files'] = files;
          data['resources'] = resources;
        }
      } catch (_) {}
    }
    await file.writeAsString(jsonEncode(data));
  }

  Map<String, dynamic> _resourceMetadata(VideoResource resource) {
    return {
      'url': resource.url,
      'type': resource.displayFormat,
      'quality': resource.quality,
      'size': resource.size,
      'bitrate': resource.bitrate,
      'codec': resource.codec,
      'source': resource.source,
      'isCurrentPlayback': resource.isCurrentPlayback,
      'preferredFolderId': resource.preferredFolderId,
      'preferredFolderName': resource.preferredFolderName,
    };
  }

  Map<String, String> _headersFor(VideoResource resource) {
    return {
      'User-Agent': resource.userAgent.isNotEmpty
          ? resource.userAgent
          : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      'Referer':
          resource.referer.isNotEmpty ? resource.referer : resource.pageUrl,
      if (resource.origin.isNotEmpty) 'Origin': resource.origin,
      if (resource.cookie.isNotEmpty) 'Cookie': resource.cookie,
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Connection': 'keep-alive',
    }..removeWhere((_, value) => value.trim().isEmpty);
  }

  String _ffmpegHeaders(VideoResource resource) {
    return _headersFor(
      resource,
    ).entries.map((entry) => '${entry.key}: ${entry.value}\r\n').join();
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  Future<void> _refreshPartialSize(DownloadTask task) async {
    final path = task.tempPath;
    if (path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    final size = await file.length();
    if (size <= task.receivedBytes) return;
    task.receivedBytes = size;
    notifyListeners();
  }

  String _ffmpegDurationSeconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(3);

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
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

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(_persistNow()),
    );
  }

  Future<void> _persistNow() async {
    try {
      await _taskStore.save(tasks);
    } catch (error) {
      debugPrint('[download] persist failed: $error');
    }
  }
}
