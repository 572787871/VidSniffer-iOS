import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

import '../models/video_resource.dart';

class VideoSniffer {
  VideoSniffer()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final Dio _dio;
  final Map<String, Future<List<VideoResource>>> _definitionRequests = {};
  static const _defaultUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15';

  Future<List<VideoResource>> parsePage(
    String input, {
    String userAgent = '',
    String cookie = '',
  }) async {
    final pageUri = normalizeUrl(input);
    if (pageUri == null) {
      throw FormatException('URL 格式不正确：$input');
    }

    final direct = resourceFromUrl(
      pageUri.toString(),
      pageTitle: pageUri.host,
      source: 'direct',
      pageUrl: pageUri.toString(),
      userAgent: userAgent,
      cookie: cookie,
    );
    if (direct != null) {
      return probeResource(direct);
    }

    final response = await _dio.getUri<String>(
      pageUri,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        headers: {
          'User-Agent': userAgent.isEmpty ? _defaultUserAgent : userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ),
    );
    final html = response.data ?? '';
    if (_looksLikeProtectedPage(html)) {
      return const [];
    }
    return scanHtml(
      html,
      pageUri,
      userAgent: userAgent.isEmpty ? _defaultUserAgent : userAgent,
      cookie: cookie,
    );
  }

  List<VideoResource> scanHtml(
    String html,
    Uri pageUri, {
    String userAgent = '',
    String cookie = '',
    String source = 'dom',
  }) {
    final decodedHtml = html
        .replaceAll(r'\/', '/')
        .replaceAll('&amp;', '&')
        .replaceAll(r'\u0026', '&');
    // Player configurations often keep short pre-roll/post-roll media beside
    // the real video. Do not offer those ad resources as download choices.
    final scannableHtml = decodedHtml.replaceAll(
      RegExp(
        r'"(?:pre|post)_ads"\s*:\s*\[.*?\]\s*,',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );
    final title = _pageTitle(decodedHtml) ?? pageUri.host;
    final candidates = <String>[];
    final patterns = <RegExp>[
      RegExp(
        r'''https?:[^"'\\\s<>]+?\.(?:m3u8|mp4|m4v|mov|ts|m4s)(?:\?[^"'\\\s<>]*)?''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:src|href|url|file|video|source|content)["'\s:=]+([^"'\s<>]+?\.(?:m3u8|mp4|m4v|mov|ts|m4s)(?:\?[^"'\s<>]*)?)''',
        caseSensitive: false,
      ),
      RegExp(
        r'''"([^"]+?\.(?:m3u8|mp4|m4v|mov|ts|m4s)(?:\?[^"]*)?)"''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<video[^>]+(?:src|data-src)=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<source[^>]+(?:src|data-src)=["']([^"']+)["']''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(scannableHtml)) {
        candidates.add(
          match.groupCount >= 1
              ? (match.group(1) ?? match.group(0)!)
              : match.group(0)!,
        );
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
      final resource = resourceFromUrl(
        resolved.toString(),
        pageTitle: title,
        pageUrl: pageUri.toString(),
        source: source,
        userAgent: userAgent,
        cookie: cookie,
      );
      if (resource == null || !seen.add(resource.url)) {
        continue;
      }
      resources.add(resource);
    }
    return prioritizeResources(resources);
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
    Duration duration = Duration.zero,
    String thumbnailUrl = '',
    bool isCurrentPlayback = false,
    String playerId = '',
    bool allowUnknown = false,
  }) {
    final base = pageUrl.isEmpty ? null : Uri.tryParse(pageUrl);
    final uri = normalizeUrl(value, base: base);
    if (uri == null || (!_isAllowedMedia(uri) && !allowUnknown)) {
      return null;
    }
    final pageUri = Uri.tryParse(pageUrl);
    final sourceLower = source.toLowerCase();
    final currentPlayback =
        isCurrentPlayback ||
        sourceLower.contains('current') ||
        sourceLower.contains('video-play');
    final adSuspect = isAdSuspect(uri.toString());
    return VideoResource(
      url: uri.toString(),
      title: pageTitle.trim().isEmpty
          ? (uri.host.isEmpty ? '网页视频' : uri.host)
          : pageTitle.trim(),
      type: VideoResource.typeFromUrl(uri.toString()),
      source: source,
      pageUrl: pageUrl,
      referer: referer.isNotEmpty ? referer : pageUrl,
      userAgent: userAgent,
      cookie: cookie,
      origin: pageUri?.origin ?? '',
      size: size,
      quality: quality == '未知' ? _qualityFromUrl(uri.toString()) : quality,
      container: _containerFromUrl(uri.toString()),
      isAdSuspect: adSuspect,
      detectedAtMs: DateTime.now().millisecondsSinceEpoch,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      isCurrentPlayback: currentPlayback,
      playerId: playerId,
    );
  }

  Future<VideoResource?> probeUnknown(VideoResource resource) async {
    if (resource.type != VideoResourceType.unknown) return resource;
    final resources = await probeResource(resource);
    return resources.isEmpty ? null : resources.first;
  }

  Future<List<VideoResource>> probeResource(VideoResource resource) async {
    if (resource.type == VideoResourceType.hls) {
      return _probeHls(resource);
    }
    if (resource.type == VideoResourceType.mp4) {
      final probed = await _probeMp4(resource);
      return probed == null ? const [] : [probed];
    }
    if (resource.type == VideoResourceType.ts || resource.isFragment) {
      return [resource.copyWith(container: resource.displayFormat)];
    }
    final jsonDefinitions = await _probeJsonMediaDefinitions(resource);
    if (jsonDefinitions.isNotEmpty) return jsonDefinitions;
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
      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
          '';
      final length = response.headers.value(Headers.contentLengthHeader);
      if (contentType.contains('mpegurl') ||
          contentType.contains('application/vnd.apple.mpegurl')) {
        return _probeHls(
          resource.copyWith(
            type: VideoResourceType.hls,
            size: length == null
                ? '未知'
                : _formatBytes(int.tryParse(length) ?? 0),
            contentType: contentType,
          ),
        );
      }
      if (contentType.startsWith('video/') || contentType.contains('mp4')) {
        final mp4 = await _probeMp4(
          resource.copyWith(
            url: response.realUri.toString(),
            type: VideoResourceType.mp4,
            size: length == null
                ? '未知'
                : _formatBytes(int.tryParse(length) ?? 0),
            contentType: contentType,
          ),
        );
        return mp4 == null ? const [] : [mp4];
      }
      return _probeUnknownWithRange(resource);
    } catch (_) {
      return _probeUnknownWithRange(resource);
    }
  }

  Future<List<VideoResource>> _probeJsonMediaDefinitions(
    VideoResource resource,
  ) {
    final lower = resource.url.toLowerCase();
    if (!lower.contains('get_media') &&
        !lower.contains('media_definition') &&
        !lower.contains('/video/')) {
      return Future.value(const []);
    }
    return _definitionRequests.putIfAbsent(
      resource.url,
      () => _loadJsonMediaDefinitions(resource),
    );
  }

  Future<List<VideoResource>> _loadJsonMediaDefinitions(
    VideoResource resource,
  ) async {
    try {
      final response = await _dio.get<String>(
        resource.url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: _headersFor(resource),
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final decoded = jsonDecode(response.data ?? '');
      final items = decoded is List
          ? decoded
          : decoded is Map && decoded['mediaDefinitions'] is List
              ? decoded['mediaDefinitions'] as List
              : const [];
      final children = <VideoResource>[];
      for (final raw in items.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final url =
            item['videoUrl']?.toString() ?? item['video_url']?.toString() ?? '';
        if (url.isEmpty || url == resource.url) continue;
        final quality = _normalizeQuality(
          item['quality']?.toString() ??
              item['qualityText']?.toString() ??
              '未知',
        );
        final child = resourceFromUrl(
          url,
          pageTitle: resource.title,
          pageUrl: resource.pageUrl,
          source: 'remote-media-definition',
          referer: resource.referer,
          userAgent: resource.userAgent,
          cookie: resource.cookie,
          quality: quality,
          duration: resource.duration,
          thumbnailUrl: resource.thumbnailUrl,
          allowUnknown: true,
        );
        if (child == null) continue;
        children.add(child);
      }
      final groups = await Future.wait(
        children.map((child) async {
          final probed = await probeResource(child);
          return probed.isEmpty ? <VideoResource>[child] : probed;
        }),
      );
      final results = groups.expand((group) => group).toList(growable: false);
      return prioritizeResources(results, limit: results.length);
    } catch (_) {
      return const [];
    }
  }

  Future<List<VideoResource>> _probeUnknownWithRange(
    VideoResource resource,
  ) async {
    try {
      final response = await _dio.get<ResponseBody>(
        resource.url,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: {..._headersFor(resource), 'Range': 'bytes=0-511'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
          '';
      if ((response.statusCode ?? 0) >= 400) return const [];
      final prefix = await response.data?.stream.first ?? const <int>[];
      final resolved = resource.copyWith(url: response.realUri.toString());
      final prefixText = utf8.decode(prefix, allowMalformed: true).trimLeft();
      if (contentType.contains('mpegurl') ||
          prefixText.startsWith('#EXTM3U')) {
        return _probeHls(
          resolved.copyWith(
            type: VideoResourceType.hls,
            contentType: contentType,
          ),
        );
      }
      final length = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      final mp4Signature = _hasMp4Signature(prefix);
      if ((contentType.startsWith('video/') ||
              contentType.contains('mp4') ||
              contentType.contains('octet-stream')) &&
          (mp4Signature || length == null || length >= 1024) &&
          (!contentType.contains('octet-stream') || mp4Signature)) {
        return [
          resolved.copyWith(
            type: VideoResourceType.mp4,
            contentType: contentType,
            size: length == null ? '未知' : _formatBytes(length),
            container: 'direct mp4',
            recommendation: '检测到的媒体响应',
          ),
        ];
      }
    } catch (_) {}
    return const [];
  }

  bool isLikelyMediaCandidate(String value) {
    final lower = value.toLowerCase().trim();
    if (lower.isEmpty ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:') ||
        lower.startsWith('about:')) {
      return false;
    }
    if (lower.contains('widevine') ||
        lower.contains('fairplay') ||
        lower.contains('drm') ||
        lower.contains('license')) {
      return false;
    }
    if (RegExp(
      r'\.(?:png|jpe?g|gif|webp|svg|ico|css|js|woff2?|ttf|otf)(?:\?|$)',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return false;
    }
    return RegExp(
          r'\.(?:mp4|m4v|mov|m3u8|ts|m4s|aac)(?:[?#]|$)',
          caseSensitive: false,
        ).hasMatch(lower) ||
        lower.contains('mpegurl') ||
        lower.contains('video/') ||
        lower.contains('audio/') ||
        lower.contains('/video') ||
        lower.contains('media') ||
        lower.contains('playurl');
  }

  bool isNetworkProbeCandidate(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final lower = value.toLowerCase();
    if (isLikelyMediaCandidate(value)) return true;
    return !RegExp(
      r'\.(?:png|jpe?g|gif|webp|svg|ico|css|js|mjs|json|xml|woff2?|ttf|otf|map|txt|html?)(?:[?#]|$)',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  bool isFragmentResource(VideoResource resource) {
    final lower = resource.url.toLowerCase();
    return resource.type == VideoResourceType.ts || lower.contains('.m4s');
  }

  bool isAdSuspect(String value) {
    final lower = value.toLowerCase();
    const keywords = [
      'ad',
      'ads',
      'advert',
      'banner',
      'promo',
      'vast',
      'vpaid',
      'ima',
      'doubleclick',
      'googlesyndication',
      'tracking',
      'analytics',
    ];
    return keywords.any((keyword) {
      if (keyword == 'ad') {
        return RegExp(r'(^|[./?&=_-])ad([./?&=_-]|$)').hasMatch(lower);
      }
      return lower.contains(keyword);
    });
  }

  List<VideoResource> prioritizeResources(
    Iterable<VideoResource> values, {
    int limit = 50,
  }) {
    final deduped = _dedupe(values);
    deduped.sort((a, b) {
      final score = _score(b).compareTo(_score(a));
      if (score != 0) return score;
      return a.url.length.compareTo(b.url.length);
    });
    return deduped.take(limit).toList();
  }

  String dedupeKey(String value, {Uri? base}) {
    final uri = normalizeUrl(value, base: base);
    if (uri == null) {
      return value.trim();
    }
    final lowerPath = uri.path.toLowerCase();
    if (lowerPath.endsWith('.ts') || lowerPath.endsWith('.m4s')) {
      return _fragmentGroupKey(uri);
    }
    final keptQuery = <String, List<String>>{};
    final noise = {
      '_',
      't',
      'time',
      'timestamp',
      'cache',
      'cb',
      'rnd',
      'random',
      'r',
    };
    for (final entry in uri.queryParametersAll.entries) {
      final key = entry.key.toLowerCase();
      if (noise.contains(key)) {
        continue;
      }
      keptQuery[entry.key] = entry.value;
    }
    final sortedKeys = keptQuery.keys.toList()..sort();
    final query = <String, dynamic>{
      for (final key in sortedKeys) key: keptQuery[key],
    };
    return uri
        .replace(queryParameters: query.isEmpty ? null : query, fragment: '')
        .toString();
  }

  Future<List<VideoResource>> _probeHls(VideoResource resource) async {
    try {
      final response = await _dio.get<String>(
        resource.url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: _headersFor(resource),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final body = response.data ?? '';
      if ((response.statusCode ?? 0) >= 400 || _looksLikeHtmlText(body)) {
        return [resource.copyWith(container: 'm3u8', recommendation: '')];
      }
      final variants = _parseHlsVariants(resource, body);
      if (variants.isNotEmpty) {
        final enriched = await Future.wait(
          variants.map(_enrichHlsMetadata),
        );
        return prioritizeResources(enriched, limit: enriched.length);
      }
      final duration = _playlistDuration(body);
      final estimatedBytes = await _estimateHlsBytes(resource, body);
      final parsed = resource.copyWith(
        container: 'media m3u8',
        quality: resource.quality == '未知' ? '单清晰度 HLS' : resource.quality,
        duration: duration > 0
            ? Duration(milliseconds: (duration * 1000).round())
            : resource.duration,
        size: estimatedBytes > 0
            ? '约 ${_formatBytes(estimatedBytes)}'
            : resource.size,
        isAdSuspect: resource.isAdSuspect,
        recommendation: resource.isAdSuspect ? '' : '可能的视频资源',
      );
      return [await _enrichHlsMetadata(parsed)];
    } catch (_) {
      return [
        resource.copyWith(
          container: 'm3u8',
          recommendation: resource.isAdSuspect ? '' : '可能的视频资源',
        ),
      ];
    }
  }

  Future<VideoResource> _enrichHlsMetadata(VideoResource resource) async {
    try {
      final extraHeaders = [
        if (resource.referer.isNotEmpty) 'Referer: ${resource.referer}',
        if (resource.cookie.isNotEmpty) 'Cookie: ${resource.cookie}',
      ].join('\r\n');
      final session = await FFprobeKit.getMediaInformationFromCommandArguments([
        '-v',
        'error',
        '-hide_banner',
        '-user_agent',
        resource.userAgent.isEmpty ? _defaultUserAgent : resource.userAgent,
        if (extraHeaders.isNotEmpty) ...['-headers', '$extraHeaders\r\n'],
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        '-show_chapters',
        '-i',
        resource.url,
      ]).timeout(const Duration(seconds: 15));
      final information = session.getMediaInformation();
      if (information == null) return resource;

      final streams = information.getStreams();
      final videoStreams = streams.where(
        (stream) => stream.getType() == 'video',
      );
      final video = videoStreams.isEmpty ? null : videoStreams.first;
      final height = video?.getHeight() ?? 0;
      final durationSeconds =
          double.tryParse(information.getDuration() ?? '') ?? 0;
      final duration = durationSeconds > 0
          ? Duration(milliseconds: (durationSeconds * 1000).round())
          : resource.duration;
      final bitrate =
          int.tryParse(information.getBitrate() ?? '') ??
          int.tryParse(video?.getBitrate() ?? '') ??
          0;
      final estimatedSize = bitrate > 0 && duration > Duration.zero
          ? (bitrate * duration.inMilliseconds / 8000).round()
          : 0;
      return resource.copyWith(
        quality: height > 0 ? '${height}p' : _normalizeQuality(resource.quality),
        duration: duration,
        size: estimatedSize >= 1024 * 1024
            ? '约 ${_formatBytes(estimatedSize)}'
            : resource.size,
        bitrate: bitrate > 0
            ? '${(bitrate / 1000).round()} kbps'
            : resource.bitrate,
        codec: video?.getCodec() ?? resource.codec,
      );
    } catch (_) {
      return resource;
    }
  }

  Future<int> _estimateHlsBytes(
    VideoResource resource,
    String playlist,
  ) async {
    final base = Uri.parse(resource.url);
    final segments = playlist
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map(base.resolve)
        .toList();
    if (segments.isEmpty) return 0;
    final sampleCount = segments.length.clamp(1, 6);
    final sampled = <Uri>[];
    for (var index = 0; index < sampleCount; index++) {
      final position = ((segments.length - 1) * index / sampleCount).round();
      sampled.add(segments[position]);
    }
    final lengths = await Future.wait(
      sampled.map((uri) async {
        try {
          final response = await _dio.headUri(
            uri,
            options: Options(
              followRedirects: true,
              headers: _headersFor(resource),
              validateStatus: (status) => status != null && status < 500,
            ),
          );
          return int.tryParse(
                response.headers.value(Headers.contentLengthHeader) ?? '',
              ) ??
              0;
        } catch (_) {
          return 0;
        }
      }),
    );
    final valid = lengths.where((length) => length > 0).toList();
    if (valid.isEmpty) return 0;
    final average = valid.reduce((a, b) => a + b) / valid.length;
    return (average * segments.length).round();
  }

  Future<VideoResource?> _probeMp4(VideoResource resource) async {
    try {
      final response = await _dio.headUri(
        Uri.parse(resource.url),
        options: Options(
          followRedirects: true,
          headers: _headersFor(resource),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return _resourceFromHeaders(resource, response.headers);
    } catch (_) {
      try {
        final response = await _dio.get<ResponseBody>(
          resource.url,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            headers: {..._headersFor(resource), 'Range': 'bytes=0-511'},
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        final prefix = await response.data?.stream.first ?? const <int>[];
        return _resourceFromHeaders(
          resource,
          response.headers,
          prefix: prefix,
        );
      } catch (_) {
        return resource.copyWith(
          container: 'direct mp4',
          recommendation: resource.isAdSuspect ? '' : '可能的视频资源',
        );
      }
    }
  }

  VideoResource? _resourceFromHeaders(
    VideoResource resource,
    Headers headers, {
    List<int> prefix = const [],
  }) {
    final contentType =
        headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
    if (contentType.contains('text/html')) {
      return null;
    }
    final length = int.tryParse(
      headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (length != null && length < 1024) {
      return null;
    }
    if (contentType.contains('octet-stream') &&
        !_hasMp4Signature(prefix)) {
      return null;
    }
    final acceptRanges = (headers.value(HttpHeaders.acceptRangesHeader) ?? '')
        .toLowerCase()
        .contains('bytes');
    return resource.copyWith(
      container: 'direct mp4',
      size: length == null || length <= 0
          ? resource.size
          : _formatBytes(length),
      contentType: contentType,
      acceptRanges: acceptRanges,
      recommendation: resource.isAdSuspect ? '' : '可能的视频资源',
    );
  }

  bool _hasMp4Signature(List<int> bytes) {
    return bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
  }

  List<VideoResource> _parseHlsVariants(VideoResource resource, String body) {
    final lines = body.split('\n').map((line) => line.trim()).toList();
    final variants = <VideoResource>[];
    final base = Uri.parse(resource.url);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final attrs = _parseAttributes(line.substring(line.indexOf(':') + 1));
      String? next;
      for (var nextIndex = index + 1; nextIndex < lines.length; nextIndex++) {
        final candidate = lines[nextIndex].trim();
        if (candidate.isEmpty) continue;
        if (candidate.startsWith('#')) continue;
        next = candidate;
        break;
      }
      if (next == null) continue;
      final variantUri = base.resolve(next);
      final resolution = attrs['RESOLUTION'] ?? '';
      final height = int.tryParse(
        RegExp(r'x(\d+)').firstMatch(resolution)?.group(1) ?? '',
      );
      final bandwidth = int.tryParse(attrs['BANDWIDTH'] ?? '');
      final codecs = (attrs['CODECS'] ?? '').replaceAll('"', '');
      variants.add(
        resource.copyWith(
          url: variantUri.toString(),
          quality: height == null
              ? _qualityFromUrl(variantUri.toString())
              : '${height}p',
          bitrate: bandwidth == null
              ? ''
              : '${(bandwidth / 1000).round()} kbps',
          codec: codecs,
          container: 'master m3u8',
          isAdSuspect:
              resource.isAdSuspect || isAdSuspect(variantUri.toString()),
          recommendation: '最高分辨率',
        ),
      );
    }
    if (variants.isEmpty) return variants;
    variants.sort((a, b) => _heightHint(b).compareTo(_heightHint(a)));
    return [
      variants.first.copyWith(
        recommendation: variants.first.isAdSuspect ? '' : '推荐下载',
      ),
      ...variants
          .skip(1)
          .map(
            (item) =>
                item.copyWith(recommendation: item.isAdSuspect ? '' : '正片可能'),
          ),
    ];
  }

  Map<String, String> _parseAttributes(String value) {
    final result = <String, String>{};
    final matches = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)').allMatches(value);
    for (final match in matches) {
      result[match.group(1)!] = match.group(2) ?? '';
    }
    return result;
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
    if (value.contains('widevine') ||
        value.contains('fairplay') ||
        value.contains('drm') ||
        value.contains('license')) {
      return false;
    }
    if (value.contains('doubleclick') ||
        value.contains('/ads/') ||
        value.contains('analytics')) {
      return false;
    }
    return [
          '.mp4',
          '.m4v',
          '.mov',
          '.m3u8',
          '.ts',
          '.m4s',
        ].any(value.contains) ||
        value.contains('application/vnd.apple.mpegurl') ||
        value.contains('application/x-mpegurl');
  }

  Map<String, String> _headersFor(VideoResource resource) {
    return {
      if (resource.userAgent.isNotEmpty) 'User-Agent': resource.userAgent,
      if (resource.referer.isNotEmpty) 'Referer': resource.referer,
      if (resource.cookie.isNotEmpty) 'Cookie': resource.cookie,
      'Accept': '*/*',
    };
  }

  List<VideoResource> _dedupe(Iterable<VideoResource> values) {
    final out = <VideoResource>[];
    final seen = <String>{};
    for (final item in values) {
      final key = dedupeKey(item.url);
      if (seen.add(key)) {
        out.add(item);
      }
    }
    return out;
  }

  int _sizeHint(VideoResource resource) {
    final raw = resource.size.trim().toLowerCase();
    final number = double.tryParse(
      RegExp(r'[\d.]+').firstMatch(raw)?.group(0) ?? '',
    );
    if (number == null) return 0;
    if (raw.contains('gb')) return (number * 1024 * 1024 * 1024).round();
    if (raw.contains('mb')) return (number * 1024 * 1024).round();
    if (raw.contains('kb')) return (number * 1024).round();
    return number.round();
  }

  int _heightHint(VideoResource resource) {
    final fromQuality =
        int.tryParse(
          RegExp(
                r'(\d{3,4})p',
              ).firstMatch(resource.quality.toLowerCase())?.group(1) ??
              '',
        ) ??
        0;
    if (fromQuality > 0) return fromQuality;
    return int.tryParse(
          RegExp(r'(\d{3,4})').firstMatch(resource.url)?.group(1) ?? '',
        ) ??
        0;
  }

  int _bitrateHint(VideoResource resource) {
    return int.tryParse(
          RegExp(r'\d+').firstMatch(resource.bitrate)?.group(0) ?? '',
        ) ??
        0;
  }

  int _score(VideoResource resource) {
    var score = 0;
    if (resource.isAdSuspect) score -= 10000;
    if (resource.isCurrentPlayback) score += 9000;
    if (resource.isFragment) score -= 2000;
    if (resource.source.toLowerCase().contains('current')) score += 5000;
    if (resource.source.toLowerCase().contains('video-play')) score += 4000;
    if (resource.source.toLowerCase().contains('media')) score += 2500;
    if (resource.duration > Duration.zero) score += resource.duration.inSeconds;
    switch (resource.type) {
      case VideoResourceType.hls:
        score += 1500;
        break;
      case VideoResourceType.mp4:
        score += 1200;
        break;
      case VideoResourceType.ts:
        score += 100;
        break;
      case VideoResourceType.unknown:
        score += 0;
        break;
    }
    if (resource.container.contains('master')) score += 500;
    score += _heightHint(resource) * 3;
    score += _bitrateHint(resource);
    score += (_sizeHint(resource) / (1024 * 1024)).round();
    return score;
  }

  double _playlistDuration(String body) {
    var total = 0.0;
    final regExp = RegExp(r'#EXTINF:([\d.]+)', caseSensitive: false);
    for (final match in regExp.allMatches(body)) {
      total += double.tryParse(match.group(1) ?? '') ?? 0;
    }
    return total;
  }

  bool _looksLikeHtmlText(String value) {
    final lower = value.trimLeft().toLowerCase();
    return lower.startsWith('<!doctype html') ||
        lower.startsWith('<html') ||
        lower.contains('<body');
  }

  String _qualityFromUrl(String value) {
    final lower = value.toLowerCase();
    final pMatch = RegExp(r'([1-9]\d{2,3})p').firstMatch(lower);
    if (pMatch != null) {
      final raw = pMatch.group(1) ?? '';
      return '${_normalizedVideoHeight(int.tryParse(raw)) ?? raw}p';
    }
    final resMatch = RegExp(r'(\d{3,4})x([1-9]\d{2,3})').firstMatch(lower);
    if (resMatch != null) return '${resMatch.group(2)}p';
    return '未知';
  }

  String _normalizeQuality(String value) {
    final p = RegExp(r'(\d{3,4})p', caseSensitive: false)
        .firstMatch(value)
        ?.group(1);
    if (p != null) {
      return '${_normalizedVideoHeight(int.tryParse(p)) ?? p}p';
    }
    final resolution = RegExp(r'\d{3,4}\s*[x×]\s*(\d{3,4})')
        .firstMatch(value)
        ?.group(1);
    if (resolution != null) return '${resolution}p';
    final number = _normalizedVideoHeight(int.tryParse(value.trim()));
    if (number != null && number >= 144) return '${number}p';
    return value;
  }

  int? _normalizedVideoHeight(int? value) {
    switch (value) {
      case 1920:
        return 1080;
      case 1280:
        return 720;
      case 854:
        return 480;
      case 640:
        return 360;
      default:
        return value;
    }
  }

  String _containerFromUrl(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('.m3u8')) return 'm3u8';
    if (lower.contains('.mp4')) return 'direct mp4';
    if (lower.contains('.m4v')) return 'direct m4v';
    if (lower.contains('.mov')) return 'direct mov';
    if (lower.contains('.ts')) return 'ts segment';
    if (lower.contains('.m4s')) return 'm4s segment';
    return '';
  }

  String _formatBytes(int value) {
    if (value <= 0) return '未知';
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _fragmentGroupKey(Uri uri) {
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty) {
      final name = segments.removeLast();
      final grouped = name.replaceAll(RegExp(r'\d{2,}'), '{n}');
      segments.add(grouped);
    }
    return uri
        .replace(pathSegments: segments, queryParameters: null, fragment: '')
        .toString();
  }

  bool _looksLikeProtectedPage(String html) {
    final lower = html.toLowerCase();
    return lower.contains('com.widevine.alpha') ||
        lower.contains('fairplay') ||
        lower.contains('skd://') ||
        lower.contains('requestmediakeysystemaccess') ||
        lower.contains('webkitkeysystemaccess');
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
    final match = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return match?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
