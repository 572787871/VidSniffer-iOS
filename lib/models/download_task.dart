import 'video_resource.dart';

enum DownloadStatus {
  idle,
  preparing,
  downloading,
  paused,
  merging,
  completed,
  failed,
  canceled,
}

enum DownloadPhase {
  preparing,
  fetchingPlaylist,
  downloadingSegments,
  downloadingFile,
  merging,
  completed,
  failed,
  canceled,
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.resource,
    this.progress = 0,
    this.status = DownloadStatus.preparing,
    this.localPath = '',
    this.message = '准备中',
    this.errorMessage = '',
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speed = '--',
    this.remaining = '--',
    this.phase = DownloadPhase.preparing,
    this.isIndeterminate = false,
    this.totalSegments = 0,
    this.downloadedSegments = 0,
    this.ffmpegTime = '--',
    this.ffmpegSpeed = '--',
    this.ffmpegLog = '',
  });

  final String id;
  final VideoResource resource;
  double progress;
  DownloadStatus status;
  String localPath;
  String message;
  String errorMessage;
  int receivedBytes;
  int totalBytes;
  String speed;
  String remaining;
  DownloadPhase phase;
  bool isIndeterminate;
  int totalSegments;
  int downloadedSegments;
  String ffmpegTime;
  String ffmpegSpeed;
  String ffmpegLog;

  bool get canRetry =>
      status == DownloadStatus.failed ||
      status == DownloadStatus.canceled ||
      status == DownloadStatus.paused;
  bool get isActive =>
      status == DownloadStatus.preparing ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.merging;

  String get idShort => id.length <= 6 ? id : id.substring(id.length - 6);
}
