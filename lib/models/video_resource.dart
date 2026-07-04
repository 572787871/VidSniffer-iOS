enum VideoResourceType { mp4, hls, ts, unknown }

class VideoResource {
  const VideoResource({
    required this.url,
    required this.title,
    required this.type,
    required this.source,
    this.pageUrl = '',
    this.referer = '',
    this.userAgent = '',
    this.cookie = '',
    this.origin = '',
    this.size = '未知',
    this.quality = '未知',
  });

  final String url;
  final String title;
  final VideoResourceType type;
  final String source;
  final String pageUrl;
  final String referer;
  final String userAgent;
  final String cookie;
  final String origin;
  final String size;
  final String quality;

  String get id => normalizedUrl;
  String get normalizedUrl => Uri.tryParse(url)?.removeFragment().toString() ?? url;

  String get label {
    switch (type) {
      case VideoResourceType.hls:
        return 'm3u8 / HLS';
      case VideoResourceType.ts:
        return 'TS 分片';
      case VideoResourceType.unknown:
        return 'unknown';
      case VideoResourceType.mp4:
        return 'MP4';
    }
  }

  bool get isMergeRequired => type == VideoResourceType.hls;

  static VideoResourceType typeFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) {
      return VideoResourceType.hls;
    }
    if (lower.contains('.ts')) {
      return VideoResourceType.ts;
    }
    if (lower.contains('.mp4') || lower.contains('.m4v') || lower.contains('.mov')) {
      return VideoResourceType.mp4;
    }
    if (lower.contains('.m4s')) {
      return VideoResourceType.unknown;
    }
    if (!lower.contains('.')) {
      return VideoResourceType.unknown;
    }
    return VideoResourceType.mp4;
  }
}
