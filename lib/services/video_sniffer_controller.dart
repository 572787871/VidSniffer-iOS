import 'dart:async';

import '../models/video_resource.dart';
import 'video_sniffer.dart';

class SnifferPageContext {
  const SnifferPageContext({
    required this.pageUrl,
    required this.pageTitle,
    required this.userAgent,
    required this.cookie,
  });

  final String pageUrl;
  final String pageTitle;
  final String userAgent;
  final String cookie;
}

class _SnifferCandidate {
  const _SnifferCandidate({required this.url, required this.source});

  final String url;
  final String source;
}

class VideoSnifferController {
  VideoSnifferController({
    required this.sniffer,
    required this.loadContext,
    required this.onResourcesChanged,
    this.debounce = const Duration(milliseconds: 800),
    this.maxResources = 50,
  });

  final VideoSniffer sniffer;
  final Future<SnifferPageContext> Function() loadContext;
  final void Function(List<VideoResource> resources) onResourcesChanged;
  final Duration debounce;
  final int maxResources;

  final Map<String, _SnifferCandidate> _pending = {};
  final Map<String, VideoResource> _resources = {};
  Timer? _timer;
  bool _processing = false;
  String _lastPageUrl = '';

  List<VideoResource> get resources =>
      sniffer.prioritizeResources(_resources.values, limit: maxResources);

  void updatePageUrl(String value) {
    _lastPageUrl = value;
  }

  void reset({String pageUrl = ''}) {
    _timer?.cancel();
    _pending.clear();
    _resources.clear();
    _processing = false;
    _lastPageUrl = pageUrl;
    onResourcesChanged(const []);
  }

  void capture(String rawUrl, String source) {
    if (!sniffer.isLikelyMediaCandidate(rawUrl)) {
      return;
    }
    final base = Uri.tryParse(_lastPageUrl);
    final key = sniffer.dedupeKey(rawUrl, base: base);
    if (_resources.containsKey(key) || _pending.containsKey(key)) {
      return;
    }
    _pending[key] = _SnifferCandidate(url: rawUrl, source: source);
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_processing || _pending.isEmpty) {
      return;
    }
    _processing = true;
    final candidates = List<_SnifferCandidate>.from(_pending.values);
    _pending.clear();
    try {
      final context = await loadContext();
      _lastPageUrl = context.pageUrl;
      for (final candidate in candidates) {
        final resource = sniffer.resourceFromUrl(
          candidate.url,
          pageTitle: context.pageTitle,
          pageUrl: context.pageUrl,
          source: candidate.source,
          userAgent: context.userAgent,
          cookie: context.cookie,
          allowUnknown: true,
        );
        if (resource == null) {
          continue;
        }
        final resolved = resource.type == VideoResourceType.unknown &&
                !sniffer.isFragmentResource(resource)
            ? await sniffer.probeUnknown(resource)
            : resource;
        if (resolved == null) {
          continue;
        }
        _resources[sniffer.dedupeKey(resolved.url)] = resolved;
      }
      onResourcesChanged(resources);
    } finally {
      _processing = false;
      if (_pending.isNotEmpty) {
        _timer = Timer(debounce, () => unawaited(flush()));
      }
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
