import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/ui_state.dart';
import '../services/video_sniffer.dart';
import '../widgets/resource_sheet.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({this.initialUrl = '', super.key});

  final String initialUrl;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final sniffer = VideoSniffer();
  final addressController = TextEditingController();
  InAppWebViewController? webController;
  PullToRefreshController? pullToRefreshController;
  double progress = 0;
  String? errorText;
  String currentUrl = '';
  String userAgent = '';

  @override
  void initState() {
    super.initState();
    final initial = _normalized(widget.initialUrl);
    debugPrint('[webview] initialUrl=$initial');
    addressController.text = initial;
    currentUrl = initial;
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xff2563eb)),
      onRefresh: () => webController?.reload(),
    );
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('网页嗅探')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: Row(
                  children: [
                    IconButton.filledTonal(onPressed: () => webController?.goBack(), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                    IconButton.filledTonal(onPressed: () => webController?.goForward(), icon: const Icon(Icons.arrow_forward_ios_rounded)),
                    IconButton.filledTonal(onPressed: () => webController?.reload(), icon: const Icon(Icons.refresh_rounded)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: addressController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _load(),
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded), hintText: '输入网址'),
                      ),
                    ),
                  ],
                ),
              ),
              if (progress > 0 && progress < 1) LinearProgressIndicator(value: progress),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        InAppWebView(
                          initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            mediaPlaybackRequiresUserGesture: false,
                            allowsInlineMediaPlayback: true,
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
                                    _addCandidate(arg['url'] as String, arg['source']?.toString() ?? 'jsHook');
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
                            });
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
                          },
                          onReceivedError: (controller, request, error) {
                            debugPrint('[webview] error: ${error.description}');
                            pullToRefreshController?.endRefreshing();
                            setState(() => errorText = error.description);
                          },
                          onLoadResource: (controller, resource) {
                            _addCandidate(resource.url.toString(), 'network');
                          },
                          shouldInterceptFetchRequest: (controller, request) async {
                            final url = request.url?.toString();
                            if (url != null) _addCandidate(url, 'fetch');
                            return request;
                          },
                          shouldInterceptAjaxRequest: (controller, request) async {
                            final url = request.url?.toString();
                            if (url != null) _addCandidate(url, 'xhr');
                            return request;
                          },
                        ),
                        if (errorText != null)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Theme.of(context).colorScheme.surface,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text('网页加载失败：$errorText', textAlign: TextAlign.center),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: FilledButton.icon(
              onPressed: () async {
                await _scanDom();
                if (!context.mounted) return;
                showResourceSheet(context, state.resources);
              },
              icon: const Icon(Icons.video_library_rounded),
              label: Text(state.resources.isEmpty ? '发现视频' : '发现视频 (${state.resources.length})'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    FocusScope.of(context).unfocus();
    final url = _normalized(addressController.text);
    debugPrint('[webview] load start: $url');
    setState(() {
      currentUrl = url;
      addressController.text = url;
      errorText = null;
    });
    await webController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _scanDom() async {
    final controller = webController;
    if (controller == null) return;
    final result = await controller.evaluateJavascript(source: _domScanScript);
    final urls = _decodeJsStringList(result);
    for (final url in urls) {
      _addCandidate(url, 'dom');
    }
  }

  Future<void> _injectSniffer() async {
    await webController?.evaluateJavascript(source: _hookScript);
  }

  Future<void> _updateUserAgent() async {
    final value = await webController?.evaluateJavascript(source: 'navigator.userAgent');
    if (value != null) {
      userAgent = value.toString().replaceAll('"', '');
    }
  }

  Future<String> _cookiesFor(String pageUrl) async {
    final uri = WebUri(pageUrl);
    final cookies = await CookieManager.instance().getCookies(url: uri);
    return cookies.map((item) => '${item.name}=${item.value}').join('; ');
  }

  Future<void> _addCandidate(String rawUrl, String source) async {
    final state = UiStateScope.of(context);
    final pageUrl = currentUrl.isEmpty ? addressController.text : currentUrl;
    final cookie = await _cookiesFor(pageUrl);
    final resource = sniffer.resourceFromUrl(
      rawUrl,
      pageTitle: await _pageTitle(),
      pageUrl: pageUrl,
      source: source,
      userAgent: userAgent,
      cookie: cookie,
    );
    if (resource == null) return;
    final probed = await sniffer.probeUnknown(resource);
    if (probed == null) return;
    state.addResource(probed);
  }

  Future<String> _pageTitle() async {
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
      if (decoded is List) return decoded.map((item) => item.toString()).toList();
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
