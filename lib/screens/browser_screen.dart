import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';
import '../services/video_sniffer_controller.dart';
import '../widgets/download_confirm_dialog.dart';
import '../widgets/resource_sheet.dart';

class BrowserController {
  BrowserController({this.homeUrl = 'https://www.google.com'});

  final String homeUrl;
  final List<String> history = [];
  final Set<String> bookmarks = {};

  void remember(String url) {
    if (url.trim().isEmpty) return;
    if (history.isNotEmpty && history.first == url) return;
    history.remove(url);
    history.insert(0, url);
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
  }

  bool toggleBookmark(String url) {
    if (bookmarks.contains(url)) {
      bookmarks.remove(url);
      return false;
    }
    bookmarks.add(url);
    return true;
  }
}

class BrowserSnifferController {
  BrowserSnifferController({
    required VideoSniffer sniffer,
    required Future<SnifferPageContext> Function() loadContext,
    required void Function(List<VideoResource>) onChanged,
  }) : controller = VideoSnifferController(
          sniffer: sniffer,
          loadContext: loadContext,
          onResourcesChanged: onChanged,
          debounce: const Duration(milliseconds: 800),
          maxResources: 50,
        );

  final VideoSnifferController controller;
  final Set<String> capturedUrls = {};

  void updatePageUrl(String url) => controller.updatePageUrl(url);

  void reset(String url) {
    capturedUrls.clear();
    controller.reset(pageUrl: url);
  }

  void capture(BrowserCandidate candidate) {
    if (!capturedUrls.add('${candidate.source}:${candidate.url}')) return;
    controller.capture(
      candidate.url,
      candidate.source,
      title: candidate.title,
      duration: candidate.duration,
      thumbnailUrl: candidate.thumbnailUrl,
      isCurrentPlayback: candidate.isCurrentPlayback,
      playerId: candidate.playerId,
    );
  }

  Future<void> flush() => controller.flush();

  List<VideoResource> get resources => controller.resources;

  void dispose() => controller.dispose();
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  final browser = BrowserController();
  final sniffer = VideoSniffer();
  final addressController = TextEditingController();

  late final BrowserSnifferController browserSniffer;
  InAppWebViewController? webController;
  Timer? resourceUpdateTimer;
  Timer? deepTimer;
  List<VideoResource> resources = const [];
  List<VideoResource> pendingResources = const [];
  final List<_TimedBrowserCandidate> recentCandidates = [];
  String currentUrl = 'https://www.google.com';
  String pageTitle = '浏览器';
  String userAgent = '';
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  bool deepSniffing = false;
  int progress = 0;
  int handledBrowserRequestId = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    currentUrl = browser.homeUrl;
    addressController.text = currentUrl;
    browserSniffer = BrowserSnifferController(
      sniffer: sniffer,
      loadContext: _snifferContext,
      onChanged: _queueResourceUpdate,
    )..updatePageUrl(currentUrl);
  }

  @override
  void dispose() {
    resourceUpdateTimer?.cancel();
    deepTimer?.cancel();
    browserSniffer.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = UiStateScope.of(context);
    if (appState.browserOpenRequestId != handledBrowserRequestId &&
        appState.browserOpenUrl.isNotEmpty) {
      handledBrowserRequestId = appState.browserOpenRequestId;
      final url = appState.browserOpenUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadUrl(url));
      });
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              color: scheme.surface,
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: '返回',
                        onPressed: canGoBack ? _goBack : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: '前进',
                        onPressed: canGoForward ? _goForward : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: addressController,
                          minLines: 1,
                          maxLines: 1,
                          textInputAction: TextInputAction.go,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            prefixIcon: const Icon(Icons.language_rounded),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                            hintText: '输入网址',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.65),
                          ),
                          onSubmitted: _loadUrl,
                        ),
                      ),
                      IconButton(
                        tooltip: loading ? '停止加载' : '刷新',
                        onPressed: loading ? _stopLoading : _reload,
                        icon: Icon(
                          loading ? Icons.close_rounded : Icons.refresh_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: '主页',
                        onPressed: () => _loadUrl(browser.homeUrl),
                        icon: const Icon(Icons.home_rounded),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pageTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            resources.isEmpty ? null : () => _openResources(),
                        icon: const Icon(Icons.playlist_play_rounded),
                        label: Text('发现 ${resources.length}'),
                      ),
                      IconButton(
                        tooltip: browser.bookmarks.contains(currentUrl)
                            ? '取消收藏'
                            : '收藏书签',
                        onPressed: () {
                          setState(() => browser.toggleBookmark(currentUrl));
                        },
                        icon: Icon(
                          browser.bookmarks.contains(currentUrl)
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                        ),
                      ),
                    ],
                  ),
                  if (loading || deepSniffing)
                    LinearProgressIndicator(
                      value: deepSniffing
                          ? null
                          : (progress <= 0 ? null : progress / 100),
                      minHeight: 2,
                    ),
                ],
              ),
            ),
            Expanded(
              child: InAppWebView(
                key: const PageStorageKey('browser-webview'),
                initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
                initialSettings: _settings(deep: false),
                onWebViewCreated: _onWebViewCreated,
                onLoadStart: (controller, url) {
                  final next = url?.toString() ?? currentUrl;
                  setState(() {
                    currentUrl = next;
                    addressController.text = next;
                    loading = true;
                    progress = 0;
                    resources = const [];
                  });
                  browser.remember(next);
                  browserSniffer.reset(next);
                },
                onLoadStop: (controller, url) async {
                  currentUrl = url?.toString() ?? currentUrl;
                  await _syncBrowserState();
                  await _injectLightHooks();
                  await _scanCurrentVideos();
                },
                onProgressChanged: (controller, value) {
                  if (!mounted) return;
                  setState(() {
                    progress = value;
                    loading = value < 100;
                  });
                },
                onTitleChanged: (controller, title) {
                  if (!mounted) return;
                  final nextTitle = title?.trim() ?? '';
                  if (nextTitle.isNotEmpty) {
                    setState(() => pageTitle = nextTitle);
                  }
                },
                onUpdateVisitedHistory: (controller, url, _) {
                  final next = url?.toString();
                  if (next == null) return;
                  setState(() {
                    currentUrl = next;
                    addressController.text = next;
                  });
                  browser.remember(next);
                  browserSniffer.updatePageUrl(next);
                },
                onLoadResource: (controller, resource) {
                  if (!deepSniffing) return;
                  _capture(resource.url.toString(), 'resource');
                },
                shouldInterceptRequest: (controller, request) async {
                  if (deepSniffing) {
                    _capture(request.url.toString(), 'resource');
                  }
                  return null;
                },
                shouldInterceptFetchRequest: (controller, request) async {
                  if (deepSniffing) {
                    final url = request.url?.toString();
                    if (url != null) _capture(url, 'fetch');
                  }
                  return request;
                },
                shouldInterceptAjaxRequest: (controller, request) async {
                  if (deepSniffing) {
                    final url = request.url?.toString();
                    if (url != null) _capture(url, 'xhr');
                  }
                  return request;
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (resources.isNotEmpty)
            _FoundVideoChip(
              count: resources.length,
              onTap: _openResources,
            ),
          if (resources.isNotEmpty) const SizedBox(height: 8),
          FloatingActionButton.extended(
            onPressed: deepSniffing ? null : _autoParsePage,
            icon:
                Icon(deepSniffing ? Icons.radar_rounded : Icons.search_rounded),
            label: Text(deepSniffing ? '解析中' : '自动解析'),
          ),
        ],
      ),
    );
  }

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    webController = controller;
    controller.addJavaScriptHandler(
      handlerName: 'VidSniffer',
      callback: (args) {
        for (final arg in args) {
          final candidate = _candidateFromDynamic(arg);
          if (candidate != null) {
            _captureCandidate(candidate);
          }
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'VideoLongPress',
      callback: (args) {
        final candidate = args.isEmpty ? null : _candidateFromDynamic(args[0]);
        unawaited(_showVideoMenu(candidate));
      },
    );
    await _syncBrowserState();
    await _injectLightHooks();
  }

  InAppWebViewSettings _settings({required bool deep}) {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useShouldInterceptRequest: deep,
      useShouldInterceptAjaxRequest: deep,
      useShouldInterceptFetchRequest: deep,
      supportZoom: false,
    );
  }

  Future<void> _loadUrl(String value) async {
    final next = _normalized(value);
    FocusScope.of(context).unfocus();
    addressController.text = next;
    await webController?.loadUrl(urlRequest: URLRequest(url: WebUri(next)));
  }

  Future<void> _goBack() async {
    final controller = webController;
    if (controller == null) return;
    if (await controller.canGoBack()) {
      await controller.goBack();
    }
  }

  Future<void> _goForward() async {
    final controller = webController;
    if (controller == null) return;
    if (await controller.canGoForward()) {
      await controller.goForward();
    }
  }

  Future<void> _reload() async => webController?.reload();

  Future<void> _stopLoading() async => webController?.stopLoading();

  Future<void> _syncBrowserState() async {
    final controller = webController;
    if (controller == null || !mounted) return;
    final url = (await controller.getUrl())?.toString() ?? currentUrl;
    final title = await controller.getTitle();
    final ua = await controller.evaluateJavascript(
      source: 'navigator.userAgent',
    );
    setState(() {
      currentUrl = url;
      addressController.text = url;
      final nextTitle = title?.trim() ?? '';
      pageTitle = nextTitle.isNotEmpty ? nextTitle : pageTitle;
      userAgent = ua?.toString().replaceAll('"', '') ?? userAgent;
      loading = false;
    });
    canGoBack = await controller.canGoBack();
    canGoForward = await controller.canGoForward();
    if (mounted) setState(() {});
    browser.remember(url);
    browserSniffer.updatePageUrl(url);
  }

  Future<void> _injectLightHooks() async {
    final controller = webController;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: _lightHookScript);
    } catch (_) {}
  }

  Future<void> _injectDeepHooks() async {
    final controller = webController;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: _deepHookScript);
    } catch (_) {}
  }

  Future<void> _scanCurrentVideos() async {
    final controller = webController;
    if (controller == null) return;
    try {
      final result =
          await controller.evaluateJavascript(source: _domScanScript);
      for (final candidate in _decodeCandidates(result)) {
        _captureCandidate(candidate);
      }
      await browserSniffer.flush();
    } catch (_) {}
  }

  Future<void> _autoParsePage() async {
    final controller = webController;
    if (controller == null) return;
    setState(() => deepSniffing = true);
    await controller.setSettings(settings: _settings(deep: true));
    await _injectLightHooks();
    await _injectDeepHooks();
    await _scanCurrentVideos();
    deepTimer?.cancel();
    deepTimer = Timer(const Duration(seconds: 5), () {
      unawaited(_finishDeepSniffing(openSheet: true));
    });
  }

  Future<void> _finishDeepSniffing({required bool openSheet}) async {
    deepTimer?.cancel();
    await browserSniffer.flush();
    await webController?.setSettings(settings: _settings(deep: false));
    if (!mounted) return;
    setState(() => deepSniffing = false);
    if (openSheet) {
      if (resources.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未发现视频资源，请播放视频后再试')),
        );
      } else {
        await _openResources();
      }
    }
  }

  Future<void> _showVideoMenu(BrowserCandidate? candidate) async {
    if (!mounted) return;
    if (candidate != null) {
      _captureCandidate(candidate);
      await browserSniffer.flush();
    }
    if (!mounted) return;
    final state = UiStateScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                '视频操作',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                candidate == null || candidate.url.startsWith('blob:')
                    ? '未拿到直链时，请先播放视频几秒后再长按。'
                    : '已定位当前视频资源。',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('解析此视频'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final related = await _currentVideoResources(candidate);
                if (!mounted) return;
                if (related.isEmpty) {
                  _showNeedPlaybackHint();
                } else {
                  await showResourceSheet(context, related);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载此视频'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final related = await _currentVideoResources(candidate);
                final resource = _firstPlayable(related);
                if (resource == null) {
                  if (mounted) {
                    _showNeedPlaybackHint();
                  }
                  return;
                }
                if (!mounted) return;
                final selected =
                    await showDownloadConfirmDialog(context, resource);
                if (selected != null && mounted) {
                  state.downloadResource(selected);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制视频链接'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final related = await _currentVideoResources(candidate);
                final resource = _firstPlayable(related);
                if (resource != null) {
                  Clipboard.setData(ClipboardData(text: resource.url));
                } else if (candidate?.url.startsWith('blob:') == true) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('blob 不是可下载地址')),
                    );
                  }
                } else {
                  if (mounted) _showNeedPlaybackHint();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.radar_rounded),
              title: const Text('自动解析整页'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_autoParsePage());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openResources() {
    return showResourceSheet(context, resources);
  }

  Future<SnifferPageContext> _snifferContext() async {
    return SnifferPageContext(
      pageUrl: currentUrl,
      pageTitle: pageTitle.trim().isEmpty ? _host(currentUrl) : pageTitle,
      userAgent: userAgent,
      cookie: await _cookiesFor(currentUrl),
    );
  }

  Future<String> _cookiesFor(String url) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(url),
      );
      return cookies.map((item) => '${item.name}=${item.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  void _capture(String url, String source) {
    if (!sniffer.isLikelyMediaCandidate(url)) return;
    _captureCandidate(BrowserCandidate(url: url, source: source));
  }

  void _captureCandidate(BrowserCandidate candidate) {
    _rememberRecent(candidate);
    browserSniffer.capture(candidate);
  }

  void _rememberRecent(BrowserCandidate candidate) {
    if (!sniffer.isLikelyMediaCandidate(candidate.url)) return;
    final now = DateTime.now();
    recentCandidates.add(_TimedBrowserCandidate(candidate, now));
    recentCandidates.removeWhere(
      (item) => now.difference(item.capturedAt) > const Duration(seconds: 10),
    );
    if (recentCandidates.length > 80) {
      recentCandidates.removeRange(0, recentCandidates.length - 80);
    }
  }

  void _queueResourceUpdate(List<VideoResource> values) {
    pendingResources = values;
    if (resourceUpdateTimer?.isActive == true) return;
    resourceUpdateTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => resources = pendingResources);
    });
  }

  Future<List<VideoResource>> _currentVideoResources(
    BrowserCandidate? candidate,
  ) async {
    await _scanCurrentVideos();
    final rawUrls = <String>{};
    if (candidate != null) {
      rawUrls.add(candidate.url);
      rawUrls.addAll(candidate.relatedUrls);
    }
    final now = DateTime.now();
    for (final item in recentCandidates) {
      if (now.difference(item.capturedAt) <= const Duration(seconds: 10)) {
        rawUrls.add(item.candidate.url);
        rawUrls.addAll(item.candidate.relatedUrls);
      }
    }
    rawUrls.removeWhere(
      (url) =>
          url.trim().isEmpty ||
          url.startsWith('blob:') ||
          url.startsWith('data:') ||
          url.startsWith('about:'),
    );
    for (final url in rawUrls) {
      _captureCandidate(
        BrowserCandidate(
          url: url,
          source: candidate?.source ?? 'video-longpress',
          title: candidate?.title ?? pageTitle,
          duration: candidate?.duration ?? Duration.zero,
          thumbnailUrl: candidate?.thumbnailUrl ?? '',
          isCurrentPlayback: true,
          playerId: candidate?.playerId ?? '',
        ),
      );
    }
    await browserSniffer.flush();
    final keys = rawUrls.map((url) => sniffer.dedupeKey(url)).toSet();
    final related = browserSniffer.resources
        .where((resource) => keys.contains(sniffer.dedupeKey(resource.url)))
        .where((resource) => resource.isPlayable && !resource.isAdSuspect)
        .toList();
    return sniffer.prioritizeResources(related, limit: 20);
  }

  VideoResource? _firstPlayable(List<VideoResource> values) {
    for (final item in values) {
      if (item.isPlayable && !item.isFragment && !item.isAdSuspect) {
        return item;
      }
    }
    return null;
  }

  void _showNeedPlaybackHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先播放视频几秒后再长按解析')),
    );
  }

  List<BrowserCandidate> _decodeCandidates(Object? value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map(_candidateFromDynamic)
          .whereType<BrowserCandidate>()
          .toList();
    }
    final text = value.toString();
    try {
      var decoded = jsonDecode(text);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is List) {
        return decoded
            .map(_candidateFromDynamic)
            .whereType<BrowserCandidate>()
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  BrowserCandidate? _candidateFromDynamic(Object? value) {
    if (value == null) return null;
    if (value is String) {
      return BrowserCandidate(url: value, source: 'dom');
    }
    if (value is! Map) return null;
    final url = value['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    final seconds = double.tryParse('${value['duration'] ?? ''}') ?? 0;
    return BrowserCandidate(
      url: url,
      source: value['source']?.toString() ?? 'jsHook',
      title: value['title']?.toString() ?? '',
      duration: seconds > 0
          ? Duration(milliseconds: (seconds * 1000).round())
          : Duration.zero,
      thumbnailUrl: value['poster']?.toString() ??
          value['thumbnailUrl']?.toString() ??
          '',
      isCurrentPlayback: value['current'] == true,
      playerId: value['playerId']?.toString() ?? '',
      relatedUrls: ((value['sources'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }

  String _normalized(String value) {
    final text = value.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (text.isEmpty || text == 'https://') return browser.homeUrl;
    return 'https://$text';
  }

  String _host(String url) => Uri.tryParse(url)?.host ?? '网页视频';

  static const String _domScanScript = r'''
(() => {
  const out = new Map();
  const pageTitle = (() => {
    const meta = document.querySelector('meta[property="og:title"], meta[name="twitter:title"], meta[itemprop="name"]');
    return (meta && meta.content) || document.title || '';
  })();
  const push = (url, source, node) => {
    try {
      if (!url || typeof url !== 'string') return;
      const absolute = new URL(url, location.href).href;
      const media = node && (node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ? node : node.closest && node.closest('video,audio'));
      const sources = media ? [media.currentSrc, media.src, ...Array.from(media.querySelectorAll('source')).map((item) => item.src || item.getAttribute('src') || '')].filter(Boolean) : [absolute];
      out.set(absolute, {
        url: absolute,
        source,
        title: (media && (media.getAttribute('title') || media.getAttribute('data-title') || media.getAttribute('data-video-title'))) || pageTitle,
        duration: media && isFinite(media.duration) && media.duration > 0 ? media.duration : 0,
        poster: (media && (media.poster || media.getAttribute('poster'))) || '',
        current: !!(media && (!media.paused || media.currentTime > 0)),
        playerId: (media && (media.id || media.getAttribute('data-player') || media.getAttribute('data-video-id'))) || '',
        sources
      });
    } catch (_) {}
  };
  document.querySelectorAll('video,audio').forEach((node) => {
    push(node.currentSrc, 'video-current', node);
    push(node.src, 'video-tag', node);
    node.querySelectorAll('source').forEach((source) => {
      push(source.src || source.getAttribute('src'), 'video-source', source);
    });
  });
  return JSON.stringify(Array.from(out.values()));
})();
''';

  static const String _lightHookScript = r'''
(() => {
  if (window.__vidSnifferLightHooked) return;
  window.__vidSnifferLightHooked = true;
  const pageTitle = () => {
    const meta = document.querySelector('meta[property="og:title"], meta[name="twitter:title"], meta[itemprop="name"]');
    return (meta && meta.content) || document.title || '';
  };
  const mediaMeta = (media, source) => ({
    title: (media && (media.getAttribute('title') || media.getAttribute('data-title') || media.getAttribute('data-video-title'))) || pageTitle(),
    duration: media && isFinite(media.duration) && media.duration > 0 ? media.duration : 0,
    poster: (media && (media.poster || media.getAttribute('poster'))) || '',
    current: /current|play/i.test(source) || !!(media && (!media.paused || media.currentTime > 0)),
    playerId: (media && (media.id || media.getAttribute('data-player') || media.getAttribute('data-video-id'))) || '',
    sources: media ? [media.currentSrc, media.src, ...Array.from(media.querySelectorAll('source')).map((item) => item.src || item.getAttribute('src') || '')].filter(Boolean) : []
  });
  const likely = (url) => typeof url === 'string' && /\.(mp4|m4v|mov|m3u8|ts|m4s|aac)(\?|#|$)/i.test(url);
  const post = (url, source, media) => {
    try {
      if (!url || typeof url !== 'string') return;
      const absolute = new URL(url, location.href).href;
      window.flutter_inappwebview.callHandler('VidSniffer', {url: absolute, source, ...mediaMeta(media, source)});
    } catch (_) {}
  };
  const longPress = (media) => {
    post(media.currentSrc || media.src, 'video-current', media);
    const meta = mediaMeta(media, 'video-longpress');
    const urls = meta.sources || [];
    window.flutter_inappwebview.callHandler('VideoLongPress', {url: urls[0] || media.currentSrc || media.src || '', source: 'video-longpress', ...meta});
  };
  const bind = (node) => {
    if (!node || node.__vidSnifferLightBound) return;
    node.__vidSnifferLightBound = true;
    ['play','loadedmetadata','canplay','durationchange'].forEach((event) => {
      node.addEventListener(event, () => post(node.currentSrc || node.src, event === 'play' ? 'video-current' : 'video-tag', node), true);
    });
    let timer = null;
    node.addEventListener('touchstart', () => { timer = setTimeout(() => longPress(node), 650); }, true);
    node.addEventListener('touchend', () => { if (timer) clearTimeout(timer); }, true);
    node.addEventListener('touchmove', () => { if (timer) clearTimeout(timer); }, true);
    node.addEventListener('contextmenu', (event) => { event.preventDefault(); longPress(node); }, true);
  };
  document.querySelectorAll('video,audio').forEach(bind);
  const originalFetch = window.fetch;
  if (originalFetch && !window.__vidSnifferLightFetchHooked) {
    window.__vidSnifferLightFetchHooked = true;
    window.fetch = function() {
      try {
        const input = arguments[0];
        const url = typeof input === 'string' ? input : input && input.url;
        if (likely(url)) post(url, 'fetch', null);
      } catch (_) {}
      return originalFetch.apply(this, arguments).then((response) => {
        try { if (likely(response.url)) post(response.url, 'fetch-response', null); } catch (_) {}
        return response;
      });
    };
  }
  if (!XMLHttpRequest.prototype.__vidSnifferLightXhrHooked) {
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.__vidSnifferLightXhrHooked = true;
    XMLHttpRequest.prototype.open = function(method, url) {
      try { if (likely(url)) post(url, 'xhr', null); } catch (_) {}
      return originalOpen.apply(this, arguments);
    };
  }
  new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      mutation.addedNodes && mutation.addedNodes.forEach((node) => {
        if (!node.querySelectorAll) return;
        if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO') bind(node);
        node.querySelectorAll('video,audio').forEach(bind);
      });
    });
  }).observe(document.documentElement, {childList: true, subtree: true});
})();
''';

  static const String _deepHookScript = r'''
(() => {
  if (window.__vidSnifferDeepHooked) return;
  window.__vidSnifferDeepHooked = true;
  const likely = (url) => typeof url === 'string' && /\.(mp4|m4v|mov|m3u8|ts|m4s|aac)(\?|#|$)/i.test(url);
  const post = (url, source) => {
    try {
      if (!likely(url)) return;
      window.flutter_inappwebview.callHandler('VidSniffer', {url: new URL(url, location.href).href, source});
    } catch (_) {}
  };
  const originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function() {
      try {
        const input = arguments[0];
        post(typeof input === 'string' ? input : input && input.url, 'fetch');
      } catch (_) {}
      return originalFetch.apply(this, arguments).then((response) => {
        try { post(response.url, 'fetch-response'); } catch (_) {}
        return response;
      });
    };
  }
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    post(url, 'xhr');
    return originalOpen.apply(this, arguments);
  };
})();
''';
}

class BrowserCandidate {
  const BrowserCandidate({
    required this.url,
    required this.source,
    this.title = '',
    this.duration = Duration.zero,
    this.thumbnailUrl = '',
    this.isCurrentPlayback = false,
    this.playerId = '',
    this.relatedUrls = const [],
  });

  final String url;
  final String source;
  final String title;
  final Duration duration;
  final String thumbnailUrl;
  final bool isCurrentPlayback;
  final String playerId;
  final List<String> relatedUrls;
}

class _FoundVideoChip extends StatelessWidget {
  const _FoundVideoChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                '已发现 $count 个视频',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimedBrowserCandidate {
  const _TimedBrowserCandidate(this.candidate, this.capturedAt);

  final BrowserCandidate candidate;
  final DateTime capturedAt;
}
