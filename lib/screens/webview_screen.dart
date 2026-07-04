import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';
import '../services/video_sniffer_controller.dart';
import '../widgets/resource_sheet.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    this.initialUrl = '',
    this.autoDiscover = false,
    this.autoParseOnly = false,
    super.key,
  });

  final String initialUrl;
  final bool autoDiscover;
  final bool autoParseOnly;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final sniffer = VideoSniffer();
  final addressController = TextEditingController();
  late final VideoSnifferController snifferController;
  InAppWebViewController? webController;
  PullToRefreshController? pullToRefreshController;
  Timer? noResourceHintTimer;
  Timer? autoResultTimer;
  double progress = 0;
  String? errorText;
  String currentUrl = '';
  String userAgent = '';
  bool browserVisible = true;
  bool toolbarVisible = true;
  bool autoDialogVisible = false;
  int lastScrollY = 0;

  @override
  void initState() {
    super.initState();
    final initial = _normalized(widget.initialUrl);
    debugPrint('[webview] initialUrl=$initial');
    addressController.text = initial;
    currentUrl = initial;
    browserVisible = !widget.autoParseOnly;
    snifferController = VideoSnifferController(
      sniffer: sniffer,
      loadContext: _snifferContext,
      onResourcesChanged: (resources) {
        if (!mounted) return;
        UiStateScope.of(context).setResources(resources);
        _scheduleAutoResult(
          shortDelay: resources.any(
            (item) => item.isPlayable && !item.isAdSuspect,
          ),
        );
      },
    )..updatePageUrl(initial);
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xff2563eb)),
      onRefresh: () => webController?.reload(),
    );
  }

  @override
  void dispose() {
    noResourceHintTimer?.cancel();
    autoResultTimer?.cancel();
    snifferController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canGoBack = await webController?.canGoBack() ?? false;
        if (canGoBack) {
          await webController?.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: browserVisible && toolbarVisible ? 50 : 0,
                    curve: Curves.easeOut,
                    child: ClipRect(child: _browserToolbar()),
                  ),
                  if (progress > 0 && progress < 1)
                    LinearProgressIndicator(value: progress, minHeight: 2),
                  Expanded(
                    child: Stack(
                      children: [
                        Opacity(
                          opacity: browserVisible ? 1 : 0.02,
                          child: IgnorePointer(
                            ignoring: !browserVisible,
                            child: InAppWebView(
                              initialUrlRequest: URLRequest(
                                url: WebUri(currentUrl),
                              ),
                              initialSettings: InAppWebViewSettings(
                                javaScriptEnabled: true,
                                mediaPlaybackRequiresUserGesture: false,
                                allowsInlineMediaPlayback: true,
                                useShouldInterceptRequest: true,
                                useShouldInterceptAjaxRequest: true,
                                useShouldInterceptFetchRequest: true,
                              ),
                              pullToRefreshController: pullToRefreshController,
                              onWebViewCreated: (controller) async {
                                webController = controller;
                                controller.addJavaScriptHandler(
                                  handlerName: 'VidSniffer',
                                  callback: (args) {
                                    for (final arg in args) {
                                      if (arg is Map && arg['url'] is String) {
                                        _captureCandidate(
                                          arg['url'] as String,
                                          arg['source']?.toString() ?? 'jsHook',
                                        );
                                      }
                                    }
                                  },
                                );
                                await _updateUserAgent();
                              },
                              onLoadStart: (controller, url) {
                                final value = url?.toString() ?? '';
                                debugPrint('[webview] load start: $value');
                                setState(() {
                                  currentUrl = value;
                                  addressController.text = value;
                                  errorText = null;
                                  progress = 0;
                                });
                                snifferController.reset(pageUrl: value);
                                _captureCandidate(value, 'resource');
                              },
                              onProgressChanged: (controller, value) {
                                debugPrint('[webview] progress: $value');
                                setState(() => progress = value / 100);
                              },
                              onLoadStop: (controller, url) async {
                                final value = url?.toString() ?? '';
                                debugPrint('[webview] load finish: $value');
                                pullToRefreshController?.endRefreshing();
                                setState(() {
                                  currentUrl = value;
                                  addressController.text = value;
                                  progress = 1;
                                });
                                await _updateUserAgent();
                                await _injectSniffer();
                                await _scanDom();
                                await snifferController.flush();
                                _scheduleNoResourceHint();
                                _scheduleAutoResult();
                              },
                              onReceivedError: (controller, request, error) {
                                debugPrint(
                                  '[webview] error: ${error.description}',
                                );
                                pullToRefreshController?.endRefreshing();
                                setState(() => errorText = error.description);
                              },
                              onLoadResource: (controller, resource) {
                                _captureCandidate(
                                  resource.url.toString(),
                                  'resource',
                                );
                              },
                              shouldInterceptRequest:
                                  (controller, request) async {
                                    final url = request.url.toString();
                                    _captureCandidate(url, 'resource');
                                    return null;
                                  },
                              shouldInterceptFetchRequest:
                                  (controller, request) async {
                                    final url = request.url?.toString();
                                    if (url != null) {
                                      _captureCandidate(url, 'fetch');
                                    }
                                    return request;
                                  },
                              shouldInterceptAjaxRequest:
                                  (controller, request) async {
                                    final url = request.url?.toString();
                                    if (url != null) {
                                      _captureCandidate(url, 'xhr');
                                    }
                                    return request;
                                  },
                              onScrollChanged: (controller, x, y) {
                                if (!browserVisible) return;
                                final shouldShow = y < lastScrollY || y < 24;
                                if (shouldShow != toolbarVisible && mounted) {
                                  setState(() => toolbarVisible = shouldShow);
                                }
                                lastScrollY = y;
                              },
                            ),
                          ),
                        ),
                        if (errorText != null)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Theme.of(context).colorScheme.surface,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    '网页加载失败：$errorText',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!browserVisible) _autoParsingOverlay(state),
                      ],
                    ),
                  ),
                ],
              ),
              if (browserVisible)
                Positioned(
                  right: 16,
                  bottom: 18,
                  child: FloatingActionButton.extended(
                    heroTag: 'discoverVideo',
                    onPressed: () async {
                      await _scanDom();
                      await snifferController.flush();
                      if (!context.mounted) return;
                      showResourceSheet(context, state.resources);
                    },
                    icon: const Icon(Icons.video_library_rounded),
                    label: Text(
                      state.resources.isEmpty
                          ? '发现视频'
                          : '发现视频 (${state.resources.length})',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _browserToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: _backOrClose,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => webController?.goForward(),
            icon: const Icon(Icons.arrow_forward_ios_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 19,
            onPressed: () => webController?.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: addressController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 16),
                  hintText: '输入网址',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoParsingOverlay(UiState state) {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  '正在自动解析视频',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  progress < 1
                      ? '正在加载网页 ${(progress * 100).round()}%'
                      : '正在扫描 DOM、XHR、fetch 和媒体请求',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() {
                    browserVisible = true;
                    toolbarVisible = true;
                  }),
                  icon: const Icon(Icons.language_rounded),
                  label: const Text('进入网页播放并嗅探'),
                ),
                if (state.resources.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '已发现 ${state.resources.length} 个候选资源',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _backOrClose() async {
    final canGoBack = await webController?.canGoBack() ?? false;
    if (canGoBack) {
      await webController?.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _load() async {
    FocusScope.of(context).unfocus();
    final url = _normalized(addressController.text);
    debugPrint('[webview] load start: $url');
    setState(() {
      currentUrl = url;
      addressController.text = url;
      errorText = null;
      progress = 0;
    });
    snifferController.reset(pageUrl: url);
    await webController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _scanDom() async {
    final controller = webController;
    if (controller == null) return;
    final result = await controller.evaluateJavascript(source: _domScanScript);
    final urls = _decodeJsStringList(result);
    for (final url in urls) {
      _captureCandidate(url, 'dom');
    }
  }

  Future<void> _injectSniffer() async {
    await webController?.evaluateJavascript(source: _hookScript);
  }

  Future<void> _updateUserAgent() async {
    final value = await webController?.evaluateJavascript(
      source: 'navigator.userAgent',
    );
    if (value != null) {
      userAgent = value.toString().replaceAll('"', '');
    }
  }

  Future<String> _cookiesFor(String pageUrl) async {
    try {
      final uri = WebUri(pageUrl);
      final cookies = await CookieManager.instance().getCookies(url: uri);
      return cookies.map((item) => '${item.name}=${item.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  void _captureCandidate(String rawUrl, String source) {
    snifferController.updatePageUrl(
      currentUrl.isEmpty ? addressController.text : currentUrl,
    );
    snifferController.capture(rawUrl, source);
  }

  Future<SnifferPageContext> _snifferContext() async {
    final pageUrl = currentUrl.isEmpty ? addressController.text : currentUrl;
    return SnifferPageContext(
      pageUrl: pageUrl,
      pageTitle: await _pageTitle(),
      userAgent: userAgent,
      cookie: await _cookiesFor(pageUrl),
    );
  }

  void _scheduleNoResourceHint() {
    if (!widget.autoDiscover || !browserVisible) return;
    noResourceHintTimer?.cancel();
    noResourceHintTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final state = UiStateScope.of(context);
      if (state.resources.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请点击播放网页视频后再点发现视频')));
      }
    });
  }

  void _scheduleAutoResult({bool shortDelay = false}) {
    if (!widget.autoParseOnly || browserVisible || autoDialogVisible) return;
    autoResultTimer?.cancel();
    autoResultTimer = Timer(Duration(seconds: shortDelay ? 1 : 6), () async {
      if (!mounted || browserVisible || autoDialogVisible) return;
      await _scanDom();
      await snifferController.flush();
      if (!mounted) return;
      final state = UiStateScope.of(context);
      final downloadable = _downloadableResources(state.resources);
      if (downloadable.isNotEmpty) {
        autoDialogVisible = true;
        setState(() {
          browserVisible = true;
          toolbarVisible = true;
        });
        await showResourceSheet(context, state.resources);
        autoDialogVisible = false;
      } else {
        autoDialogVisible = true;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('未自动发现视频'),
            content: const Text('部分网站需要先播放视频，请进入网页播放后再点发现视频。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _retryAutoParse();
                },
                child: const Text('重试自动解析'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    browserVisible = true;
                    toolbarVisible = true;
                  });
                },
                child: const Text('进入网页播放并嗅探'),
              ),
            ],
          ),
        );
        autoDialogVisible = false;
      }
    });
  }

  void _retryAutoParse() {
    autoDialogVisible = false;
    setState(() {
      browserVisible = false;
      toolbarVisible = false;
    });
    _load();
  }

  List<VideoResource> _downloadableResources(List<VideoResource> resources) {
    return resources
        .where((item) => item.isPlayable && !item.isAdSuspect)
        .toList();
  }

  Future<String> _pageTitle() async {
    final richTitle = await webController?.evaluateJavascript(
      source: '''
(() => {
  const meta = document.querySelector('meta[property="og:title"], meta[name="twitter:title"], meta[itemprop="name"]');
  const video = document.querySelector('video[title], [data-video-title], [data-title]');
  return (meta && meta.content) || (video && (video.getAttribute('title') || video.getAttribute('data-video-title') || video.getAttribute('data-title'))) || document.title || '';
})();
''',
    );
    final rich = richTitle?.toString().replaceAll('"', '').trim();
    if (rich != null && rich.isNotEmpty) {
      return rich;
    }
    final title = await webController?.getTitle();
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '网页视频';
    }
    return trimmed;
  }

  List<String> _decodeJsStringList(Object? value) {
    if (value == null) return const [];
    if (value is List) return value.map((item) => item.toString()).toList();
    final text = value.toString();
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  String _normalized(String value) {
    final text = value.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (text.isEmpty || text == 'https://') return 'https://example.com';
    return 'https://$text';
  }

  static const String _domScanScript = r'''
(() => {
  const out = new Set();
  const push = (value) => {
    try {
      if (!value || typeof value !== 'string') return;
      out.add(new URL(value, location.href).href);
    } catch (_) {}
  };
  document.querySelectorAll('video, source').forEach((node) => {
    push(node.src);
    push(node.currentSrc);
    push(node.getAttribute('src'));
    push(node.getAttribute('data-src'));
  });
  document.querySelectorAll('a[href]').forEach((node) => {
    const href = node.getAttribute('href') || '';
    if (/\.(mp4|m3u8|m4v|mov|ts|m4s)(\?|$)/i.test(href)) push(href);
  });
  const html = document.documentElement.outerHTML || '';
  const matches = html.match(/https?:[^"'\\\s<>]+?\.(?:mp4|m3u8|m4v|mov|ts|m4s)(?:\?[^"'\\\s<>]*)?/ig) || [];
  matches.forEach(push);
  return Array.from(out);
})();
''';

  static const String _hookScript = r'''
(() => {
  if (window.__videoDownloaderHooked) return;
  window.__videoDownloaderHooked = true;
  const post = (url, source) => {
    try {
      if (!url || typeof url !== 'string') return;
      const absolute = new URL(url, location.href).href;
      window.flutter_inappwebview.callHandler('VidSniffer', {url: absolute, source});
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
  const desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
  if (desc && desc.set) {
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      set: function(value) { post(value, 'media-src'); return desc.set.call(this, value); },
      get: function() { return desc.get.call(this); }
    });
  }
  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    post(this.currentSrc || this.src, 'video-play');
    return originalPlay.apply(this, arguments);
  };
})();
''';
}
