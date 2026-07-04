import 'video_resource.dart';

enum DownloadStatus { queued, running, paused, completed, failed, canceled }

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.resource,
    this.progress = 0,
    this.status = DownloadStatus.queued,
    this.localPath = '',
    this.message = '等待中',
  });

  final String id;
  final VideoResource resource;
  double progress;
  DownloadStatus status;
  String localPath;
  String message;

  bool get canRetry => status == DownloadStatus.failed || status == DownloadStatus.canceled || status == DownloadStatus.paused;
  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.running;
}
