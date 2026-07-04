enum VideoResourceType { mp4, hls, ts }

class VideoResource {
  const VideoResource({
    required this.url,
    required this.title,
    required this.type,
    required this.source,
    this.pageUrl = '',
  });

  final String url;
  final String title;
  final VideoResourceType type;
  final String source;
  final String pageUrl;

  String get label {
    switch (type) {
      case VideoResourceType.hls:
        return 'm3u8 / HLS';
      case VideoResourceType.ts:
        return 'TS 分片';
      case VideoResourceType.mp4:
        return 'MP4';
    }
  }

  bool get isMergeRequired => type == VideoResourceType.hls || type == VideoResourceType.ts;

  static VideoResourceType typeFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) {
      return VideoResourceType.hls;
    }
    if (lower.contains('.ts')) {
      return VideoResourceType.ts;
    }
    return VideoResourceType.mp4;
  }
}
