import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/video_resource.dart';

class VideoSniffer {
  VideoSniffer() : _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 30)));

  final Dio _dio;

  Future<List<VideoResource>> parsePage(String input, {String userAgent = '', String cookie = ''}) async {
    final pageUri = normalizeUrl(input);
    if (pageUri == null) {
      throw FormatException('URL 格式不正确：$input');
    }

    final direct = resourceFromUrl(pageUri.toString(), pageTitle: pageUri.host, source: 'direct', pageUrl: pageUri.toString(), userAgent: userAgent, cookie: cookie);
    if (direct != null) {
      return [direct];
    }

    final response = await _dio.getUri<String>(
      pageUri,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ),
    );
    final html = response.data ?? '';
    if (_looksLikeProtectedPage(html)) {
      return const [];
    }
    return scanHtml(html, pageUri, userAgent: userAgent, cookie: cookie);
  }

  List<VideoResource> scanHtml(String html, Uri pageUri, {String userAgent = '', String cookie = '', String source = 'dom'}) {
    final title = _pageTitle(html) ?? pageUri.host;
    final candidates = <String>[];
    final patterns = <RegExp>[
      RegExp(r'''https?:[^"'\\\s<>]+?\.(?:m3u8|mp4|m4v|mov|ts|m4s)(?:\?[^"'\\\s<>]*)?''', caseSensitive: false),
      RegExp(r'''(?:src|href|url|file|video|source|content)["'\s:=]+([^"'\s<>]+?\.(?:m3u8|mp4|m4v|mov|ts|m4s)(?:\?[^"'\s<>]*)?)''', caseSensitive: false),
      RegExp(r'''"([^"]+?\.(?:m3u8|mp4|m4v|mov|ts|m4s)(?:\?[^"]*)?)"''', caseSensitive: false),
      RegExp(r'''<video[^>]+(?:src|data-src)=["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''<source[^>]+(?:src|data-src)=["']([^"']+)["']''', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        candidates.add(match.groupCount >= 1 ? (match.group(1) ?? match.group(0)!) : match.group(0)!);
      }
    }

    final resources = <VideoResource>[];
    final seen = <String>{};
    for (final raw in candidates) {
      final cleaned = _decodeCandidate(raw);
      final resolved = normalizeUrl(cleaned, base: pageUri);
      if (resolved == null) {
        continue;
      }
      final resource = resourceFromUrl(resolved.toString(), pageTitle: title, pageUrl: pageUri.toString(), source: source, userAgent: userAgent, cookie: cookie);
      if (resource == null || !seen.add(resource.url)) {
        continue;
      }
      resources.add(resource);
    }
    resources.sort((a, b) => _priority(a).compareTo(_priority(b)));
    return resources;
  }

  VideoResource? resourceFromUrl(
    String value, {
    String pageTitle = '网页视频',
    String pageUrl = '',
    String source = 'dom',
    String referer = '',
    String userAgent = '',
    String cookie = '',
    String size = '未知',
    String quality = '未知',
  }) {
    final base = pageUrl.isEmpty ? null : Uri.tryParse(pageUrl);
    final uri = normalizeUrl(value, base: base);
    if (uri == null || !_isAllowedMedia(uri)) {
      return null;
    }
    final pageUri = Uri.tryParse(pageUrl);
    return VideoResource(
      url: uri.toString(),
      title: pageTitle.trim().isEmpty ? (uri.host.isEmpty ? '网页视频' : uri.host) : pageTitle.trim(),
      type: VideoResource.typeFromUrl(uri.toString()),
      source: source,
      pageUrl: pageUrl,
      referer: referer.isNotEmpty ? referer : pageUrl,
      userAgent: userAgent,
      cookie: cookie,
      origin: pageUri?.origin ?? '',
      size: size,
      quality: quality,
    );
  }

  Future<VideoResource?> probeUnknown(VideoResource resource) async {
    if (resource.type != VideoResourceType.unknown) {
      return resource;
    }
    try {
      final response = await _dio.headUri(
        Uri.parse(resource.url),
        options: Options(
          followRedirects: true,
          headers: {
            if (resource.userAgent.isNotEmpty) 'User-Agent': resource.userAgent,
            if (resource.referer.isNotEmpty) 'Referer': resource.referer,
            if (resource.cookie.isNotEmpty) 'Cookie': resource.cookie,
            'Accept': '*/*',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final contentType = response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
      final length = response.headers.value(Headers.contentLengthHeader);
      if (contentType.contains('mpegurl') || contentType.contains('application/vnd.apple.mpegurl')) {
        return _copyWith(resource, type: VideoResourceType.hls, size: length ?? '未知');
      }
      if (contentType.startsWith('video/') || contentType.contains('mp4')) {
        return _copyWith(resource, type: VideoResourceType.mp4, size: length ?? '未知');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  VideoResource _copyWith(VideoResource resource, {required VideoResourceType type, required String size}) {
    return VideoResource(
      url: resource.url,
      title: resource.title,
      type: type,
      source: resource.source,
      pageUrl: resource.pageUrl,
      referer: resource.referer,
      userAgent: resource.userAgent,
      cookie: resource.cookie,
      origin: resource.origin,
      size: size,
      quality: resource.quality,
    );
  }

  Uri? normalizeUrl(String value, {Uri? base}) {
    var text = value.trim();
    if (text.isEmpty || text.startsWith('blob:') || text.startsWith('data:')) {
      return null;
    }
    if (text.startsWith('//')) {
      text = 'https:$text';
    }
    if (base != null) {
      return base.resolve(text);
    }
    if (!text.contains('://')) {
      text = 'https://$text';
    }
    return Uri.tryParse(text);
  }

  bool _isAllowedMedia(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (!(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    if (value.contains('widevine') || value.contains('fairplay') || value.contains('drm') || value.contains('license')) {
      return false;
    }
    if (value.contains('doubleclick') || value.contains('/ads/') || value.contains('analytics')) {
      return false;
    }
    return ['.mp4', '.m4v', '.mov', '.m3u8', '.ts', '.m4s'].any(value.contains) || value.contains('application/vnd.apple.mpegurl') || value.contains('application/x-mpegurl');
  }

  bool _looksLikeProtectedPage(String html) {
    final lower = html.toLowerCase();
    return lower.contains('widevine') || lower.contains('fairplay') || lower.contains('encrypted-media') || lower.contains('eme');
  }

  String _decodeCandidate(String raw) {
    var value = raw.trim().replaceAll(r'\/', '/').replaceAll('&amp;', '&');
    value = value.replaceAll(RegExp(r'''^["'\s<>()]+|["'\s<>()]+$'''), '');
    try {
      value = Uri.decodeFull(value);
    } catch (_) {
      try {
        value = utf8.decode(value.codeUnits);
      } catch (_) {}
    }
    return value;
  }

  String? _pageTitle(String html) {
    final match = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html);
    return match?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _priority(VideoResource resource) {
    switch (resource.type) {
      case VideoResourceType.hls:
        return 0;
      case VideoResourceType.mp4:
        return 1;
      case VideoResourceType.ts:
        return 2;
      case VideoResourceType.unknown:
        return 3;
    }
  }
}
