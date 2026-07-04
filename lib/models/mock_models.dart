enum MockVideoType { mp4, m3u8, unknown }

class MockVideoResource {
  const MockVideoResource({
    required this.title,
    required this.url,
    required this.type,
    required this.meta,
  });

  final String title;
  final String url;
  final MockVideoType type;
  final String meta;

  String get typeLabel {
    switch (type) {
      case MockVideoType.mp4:
        return 'mp4';
      case MockVideoType.m3u8:
        return 'm3u8';
      case MockVideoType.unknown:
        return 'unknown';
    }
  }
}

class MockDownloadTask {
  MockDownloadTask({
    required this.title,
    required this.type,
    required this.progress,
    required this.speed,
    required this.remaining,
    required this.completed,
  });

  final String title;
  final String type;
  double progress;
  String speed;
  String remaining;
  bool completed;
  bool paused = false;
}

class MockLocalVideo {
  const MockLocalVideo({
    required this.title,
    required this.size,
    required this.date,
    required this.path,
  });

  final String title;
  final String size;
  final String date;
  final String path;
}
