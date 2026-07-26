import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/video_resource.dart';
import '../services/browser_data_store.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';
import '../services/video_sniffer_controller.dart';
import '../widgets/home_sniffer.dart';
import 'downloads_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  final addressController = TextEditingController();
  final sniffer = VideoSniffer();
  final BrowserDataStore browserDataStore = BrowserDataStore();
  final List<BrowserPageRecord> history = [];
  final List<BrowserPageRecord> bookmarks = [];
  final List<_BrowserTabData> browserTabs = [
    _BrowserTabData(id: 'initial', title: '新窗口', url: 'about:blank'),
  ];
  final List<_BrowserTabData> recentlyClosedTabs = [];
  final Map<String, VideoResource> captured = {};
  late final VideoSnifferController snifferController;

  InAppWebViewController? controller;
  Timer? deepTimer;
  Timer? flushTimer;
  String currentUrl = 'about:blank';
  String pageTitle = '新窗口';
  String userAgent = '';
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  bool deepCapture = false;
  bool directParsing = false;
  String directParseUrl = '';
  bool showStartPage = true;
  int progress = 0;
  int handledBrowserRequestId = 0;
  int activeBrowserTab = 0;
  bool adBlockEnabled = true;
  bool blockPopups = true;
  bool blockTrackers = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    addressController.text = '';
    unawaited(_loadBrowserData());
    snifferController = VideoSnifferController(
      sniffer: sniffer,
      loadContext: _snifferContext,
      onResourcesChanged: (resources) {
        if (!mounted) return;
        setState(() {
          captured
            ..clear()
            ..addEntries(
              resources.map(
                (resource) =>
                    MapEntry(sniffer.dedupeKey(resource.url), resource),
              ),
            );
        });
      },
      debounce: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    deepTimer?.cancel();
    flushTimer?.cancel();
    snifferController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = UiStateScope.of(context);
    if (state.browserOpenRequestId != handledBrowserRequestId &&
        state.browserOpenUrl.isNotEmpty) {
      handledBrowserRequestId = state.browserOpenRequestId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadUrl(state.browserOpenUrl));
      });
    }

    return Scaffold(
      appBar: showStartPage ? _startAppBar() : _browserAppBar(),
      drawer: _TabsDrawer(
        history: history,
        bookmarks: bookmarks,
        onOpen: (url) {
          Navigator.pop(context);
          unawaited(_loadUrl(url));
        },
        onClearHistory: () {
          setState(() => history.clear());
          unawaited(_saveBrowserData());
          Navigator.pop(context);
        },
        onRemoveHistory: _removeHistory,
        onRemoveBookmark: _removeBookmark,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: showStartPage
                  ? _StartPage(
                      onOpen: _loadUrl,
                      onParseClipboard: _parseClipboardUrl,
                      parsing: directParsing,
                    )
                  : _browserBody(),
            ),
            if (directParsing && directParseUrl.isNotEmpty)
              Offstage(
                offstage: true,
                child: HomeSniffer(
                  key: ValueKey(directParseUrl),
                  initialUrl: directParseUrl,
                  onProgress: (_) {},
                  onFound: (record) {
                    if (!mounted) return;
                    setState(() {
                      directParsing = false;
                      directParseUrl = '';
                      captured
                        ..clear()
                        ..addEntries(
                          record.resources.map(
                            (resource) => MapEntry(
                              sniffer.dedupeKey(resource.url),
                              resource,
                            ),
                          ),
                        );
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        unawaited(
                          _showDownloadPicker(title: record.pageTitle),
                        );
                      }
                    });
                  },
                  onNotFound: (_, __) {
                    if (!mounted) return;
                    setState(() {
                      directParsing = false;
                      directParseUrl = '';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('未直接解析到视频，请确认网址或稍后重试')),
                    );
                  },
                  onFailed: (_, __, error) {
                    if (!mounted) return;
                    setState(() {
                      directParsing = false;
                      directParseUrl = '';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('直接解析失败：$error')),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: showStartPage
          ? null
          : _DownloadFloatButton(
              count: _downloadable.length,
              busy: deepCapture,
              onPressed: _downloadable.isEmpty
                  ? () => _sniffPage(openPicker: true)
                  : _showDownloadPicker,
            ),
    );
  }

  PreferredSizeWidget _startAppBar() {
    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: '收藏与历史',
          onPressed: _showBrowserTabs,
          icon: _TabCountBadge(count: browserTabs.length),
        ),
      ),
      title: const SizedBox.shrink(),
      actions: [
        PopupMenuButton<String>(
          onSelected: _handleMenu,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'parsePaste',
              child: Text('粘贴网址直接解析'),
            ),
            PopupMenuItem(value: 'paste', child: Text('粘贴并打开')),
            PopupMenuItem(value: 'favorites', child: Text('收藏夹')),
            PopupMenuItem(value: 'history', child: Text('历史记录')),
            PopupMenuItem(value: 'downloadHistory', child: Text('下载记录')),
            PopupMenuItem(value: 'help', child: Text('帮助')),
            PopupMenuItem(value: 'settings', child: Text('浏览器设置')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _browserAppBar() {
    return AppBar(
      leadingWidth: 40,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: '收藏与历史',
          onPressed: _showBrowserTabs,
          icon: _TabCountBadge(count: browserTabs.length),
        ),
      ),
      titleSpacing: 0,
      title: _AddressBar(
        controller: addressController,
        onSubmitted: _loadUrl,
      ),
      actions: [
        IconButton(
          tooltip: _isCurrentPageBookmarked ? '取消收藏' : '收藏当前网页',
          onPressed: currentUrl.startsWith('http') ? _toggleBookmark : null,
          icon: Icon(
            _isCurrentPageBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
          ),
        ),
        IconButton(
          tooltip: loading ? '停止' : '刷新',
          onPressed: loading ? _stopLoading : _reload,
          icon: Icon(loading ? Icons.close_rounded : Icons.refresh_rounded),
        ),
        PopupMenuButton<String>(
          onSelected: _handleMenu,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'home', child: Text('主页')),
            PopupMenuItem(value: 'sniff', child: Text('重新解析视频')),
            PopupMenuItem(value: 'favorites', child: Text('收藏夹')),
            PopupMenuItem(value: 'history', child: Text('历史记录')),
            PopupMenuItem(value: 'downloadHistory', child: Text('下载记录')),
            PopupMenuItem(
              value: 'parsePaste',
              child: Text('粘贴网址直接解析'),
            ),
            PopupMenuItem(value: 'copy', child: Text('复制网址')),
            PopupMenuItem(value: 'settings', child: Text('浏览器设置')),
          ],
        ),
      ],
    );
  }

  Widget _browserBody() {
    return Column(
      children: [
        if (loading || deepCapture)
          LinearProgressIndicator(
            value: deepCapture ? null : (progress <= 0 ? null : progress / 100),
            minHeight: 2,
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: InAppWebView(
                  key: const PageStorageKey('video-downloader-browser'),
                  initialUrlRequest: currentUrl.startsWith('about:')
                      ? null
                      : URLRequest(url: WebUri(currentUrl)),
                  initialSettings: _settings(),
                  onWebViewCreated: _onWebViewCreated,
                  onLoadStart: (_, url) {
                    final next = url?.toString() ?? currentUrl;
                    snifferController.reset(pageUrl: next);
                    setState(() {
                      currentUrl = next;
                      addressController.text = next;
                      loading = true;
                      progress = 0;
                      captured.clear();
                    });
                    _remember(next);
                    _updateActiveTab(url: next);
                  },
                  onLoadStop: (_, url) async {
                    currentUrl = url?.toString() ?? currentUrl;
                    await _syncBrowserState();
                    await _injectHooks();
                    await _scanDom();
                  },
                  onProgressChanged: (_, value) {
                    if (!mounted) return;
                    setState(() {
                      progress = value;
                      loading = value < 100;
                    });
                  },
                  onTitleChanged: (_, title) {
                    final value = title?.trim() ?? '';
                    if (value.isNotEmpty && mounted) {
                      setState(() => pageTitle = value);
                      _updateSavedTitle(value);
                      _updateActiveTab(title: value);
                    }
                  },
                  onUpdateVisitedHistory: (_, url, __) {
                    final next = url?.toString();
                    if (next == null) return;
                    setState(() {
                      currentUrl = next;
                      addressController.text = next;
                    });
                    _remember(next);
                  },
                  onLoadResource: (_, resource) {
                    snifferController.captureNetwork(
                      resource.url.toString(),
                      'resource',
                    );
                  },
                  shouldInterceptRequest: (_, request) async {
                    if (_shouldBlockRequest(request.url.toString())) {
                      return WebResourceResponse(
                        contentType: 'text/plain',
                        data: Uint8List(0),
                      );
                    }
                    snifferController.captureNetwork(
                      request.url.toString(),
                      'net',
                    );
                    return null;
                  },
                  shouldOverrideUrlLoading: (_, action) async {
                    final url = action.request.url?.toString() ?? '';
                    if (_shouldBlockNavigation(url)) {
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  shouldInterceptFetchRequest: (_, request) async {
                    final url = request.url?.toString();
                    if (url != null) {
                      snifferController.captureNetwork(url, 'fetch');
                    }
                    return request;
                  },
                  shouldInterceptAjaxRequest: (_, request) async {
                    final url = request.url?.toString();
                    if (url != null) {
                      snifferController.captureNetwork(url, 'xhr');
                    }
                    return request;
                  },
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _DetectionBar(
                  count: _downloadable.length,
                  onTap: _downloadable.isEmpty ? null : _showDownloadPicker,
                  onParse: () => _sniffPage(openPicker: true),
                ),
              ),
            ],
          ),
        ),
        _BrowserBottomControls(
          canGoBack: canGoBack,
          canGoForward: canGoForward,
          onBack: _goBack,
          onForward: _goForward,
          onHome: _goHome,
          onNew: _goHome,
        ),
      ],
    );
  }

  Future<void> _onWebViewCreated(InAppWebViewController value) async {
    controller = value;
    value.addJavaScriptHandler(
      handlerName: 'VideoDownloaderCapture',
      callback: (args) {
        for (final arg in args) {
          _captureCandidate(arg);
        }
      },
    );
    await _syncBrowserState();
  }

  InAppWebViewSettings _settings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useShouldInterceptRequest: true,
      useShouldInterceptAjaxRequest: true,
      useShouldInterceptFetchRequest: true,
      useShouldOverrideUrlLoading: true,
      javaScriptCanOpenWindowsAutomatically: !blockPopups,
      supportZoom: true,
    );
  }

  List<VideoResource> get _downloadable {
    final values = captured.values
        .where((item) => item.isPlayable && !item.isAdSuspect && !item.isFragment)
        .toList();
    values.sort((a, b) {
      final current = b.isCurrentPlayback.toString().compareTo(
            a.isCurrentPlayback.toString(),
          );
      if (current != 0) return current;
      return _score(b).compareTo(_score(a));
    });
    return values.take(12).toList(growable: false);
  }

  int _score(VideoResource resource) {
    final quality = resource.quality.toLowerCase();
    if (quality.contains('2160') || quality.contains('4k')) return 4000;
    if (quality.contains('1080')) return 3000;
    if (quality.contains('720')) return 2000;
    if (resource.type == VideoResourceType.hls) return 1200;
    if (resource.type == VideoResourceType.mp4) return 1000;
    return 0;
  }

  Future<void> _loadUrl(String input) async {
    final url = _normalize(input);
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      showStartPage = false;
      currentUrl = url;
      addressController.text = url;
      _updateActiveTab(url: url, notify: false);
    });
    final web = controller;
    if (web == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url))));
      });
    } else {
      await web.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
  }

  Future<void> _goBack() async {
    final web = controller;
    if (web == null) return;
    if (await web.canGoBack()) await web.goBack();
  }

  Future<void> _goForward() async {
    final web = controller;
    if (web == null) return;
    if (await web.canGoForward()) await web.goForward();
  }

  void _goHome() {
    setState(() {
      showStartPage = true;
      currentUrl = 'about:blank';
      pageTitle = '新窗口';
      captured.clear();
      addressController.clear();
      _updateActiveTab(url: 'about:blank', title: '新窗口', notify: false);
    });
  }

  Future<void> _reload() async => controller?.reload();

  Future<void> _stopLoading() async => controller?.stopLoading();

  Future<void> _syncBrowserState() async {
    final web = controller;
    if (web == null || !mounted) return;
    final url = (await web.getUrl())?.toString() ?? currentUrl;
    final title = await web.getTitle();
    final ua = await web.evaluateJavascript(source: 'navigator.userAgent');
    final back = await web.canGoBack();
    final forward = await web.canGoForward();
    if (!mounted) return;
    setState(() {
      currentUrl = url;
      addressController.text = url;
      pageTitle = title?.trim().isNotEmpty == true ? title!.trim() : pageTitle;
      userAgent = ua?.toString().replaceAll('"', '') ?? userAgent;
      canGoBack = back;
      canGoForward = forward;
      loading = false;
    });
  }

  Future<void> _injectHooks() async {
    try {
      await controller?.evaluateJavascript(source: _hookScript);
      if (adBlockEnabled) {
        await controller?.evaluateJavascript(source: _adBlockScript);
      }
    } catch (_) {}
  }

  Future<void> _scanDom() async {
    try {
      final result = await controller?.evaluateJavascript(source: _scanScript);
      _captureCandidate(result);
      _scheduleFlush();
    } catch (_) {}
  }

  Future<void> _sniffPage({required bool openPicker}) async {
    final web = controller;
    if (web == null) return;
    setState(() => deepCapture = true);
    await web.setSettings(settings: _settings());
    await _injectHooks();
    await _scanDom();
    deepTimer?.cancel();
    deepTimer = Timer(const Duration(seconds: 6), () async {
      await web.setSettings(settings: _settings());
      if (!mounted) return;
      setState(() => deepCapture = false);
      if (openPicker) {
        if (_downloadable.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先播放视频，再点击下载按钮')),
          );
        } else {
          _showDownloadPicker();
        }
      }
    });
  }

  void _captureUrl(String url, String source) {
    snifferController.captureNetwork(url, source);
  }

  void _captureCandidate(Object? value) {
    if (value == null) return;
    if (value is List) {
      for (final item in value) {
        _captureCandidate(item);
      }
      return;
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        _captureCandidate(decoded);
      } catch (_) {
        _captureUrl(value, 'js');
      }
      return;
    }
    if (value is! Map) return;
    final url = value['url']?.toString() ?? '';
    final sources = ((value['sources'] as List?) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty);
    final seconds = double.tryParse('${value['duration'] ?? ''}') ?? 0;
    final title = value['title']?.toString() ?? pageTitle;
    final poster = value['poster']?.toString() ?? '';
    final current = value['current'] == true;
    for (final item in [url, ...sources]) {
      _capture(
        url: item,
        source: value['source']?.toString() ?? 'video',
        title: title,
        current: current,
        duration: seconds > 0
            ? Duration(milliseconds: (seconds * 1000).round())
            : Duration.zero,
        poster: poster,
      );
    }
  }

  void _capture({
    required String url,
    required String source,
    required String title,
    required bool current,
    required Duration duration,
    required String poster,
  }) {
    snifferController.capture(
      _absoluteUrl(url),
      source,
      title: title,
      duration: duration,
      thumbnailUrl: poster,
      isCurrentPlayback: current,
    );
  }

  void _scheduleFlush() {
    if (flushTimer?.isActive == true) return;
    flushTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _showDownloadPicker({String? title}) async {
    final resources = _downloadable;
    if (resources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先播放视频，再点击下载按钮')),
      );
      return;
    }
    final appState = UiStateScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DownloadPicker(
        title: title ?? pageTitle,
        resources: resources,
        onDownload: (resource) async {
          Navigator.pop(context);
          appState.downloadResource(await _withCurrentCredentials(resource));
        },
      ),
    );
  }

  Future<SnifferPageContext> _snifferContext() async {
    await _syncBrowserState();
    return SnifferPageContext(
      pageUrl: currentUrl,
      pageTitle: pageTitle,
      userAgent: userAgent,
      cookie: await _cookiesFor(currentUrl),
    );
  }

  Future<VideoResource> _withCurrentCredentials(
    VideoResource resource,
  ) async {
    final cookieValues = <String>[
      await _cookiesFor(resource.url),
      await _cookiesFor(resource.pageUrl),
      resource.cookie,
    ];
    final cookieMap = <String, String>{};
    for (final value in cookieValues.reversed) {
      for (final part in value.split(';')) {
        final separator = part.indexOf('=');
        if (separator <= 0) continue;
        cookieMap[part.substring(0, separator).trim()] =
            part.substring(separator + 1).trim();
      }
    }
    final cookies = cookieMap.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    return resource.copyWith(
      referer: resource.referer.isNotEmpty ? resource.referer : currentUrl,
      pageUrl: resource.pageUrl.isNotEmpty ? resource.pageUrl : currentUrl,
      userAgent: userAgent.isNotEmpty ? userAgent : resource.userAgent,
      cookie: cookies.isNotEmpty ? cookies : resource.cookie,
      origin: resource.origin.isNotEmpty
          ? resource.origin
          : _origin(currentUrl),
    );
  }

  Future<String> _cookiesFor(String value) async {
    if (value.trim().isEmpty) return '';
    try {
      final uri = WebUri(value);
      final cookies = await CookieManager.instance().getCookies(url: uri);
      final unique = <String, String>{
        for (final cookie in cookies) cookie.name: cookie.value,
      };
      return unique.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'home':
        _goHome();
      case 'sniff':
        await _sniffPage(openPicker: true);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: currentUrl));
      case 'favorites':
        _showSavedPages(0);
      case 'history':
        _showSavedPages(1);
      case 'downloadHistory':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DownloadHistoryScreen(),
          ),
        );
      case 'parsePaste':
        await _parseClipboardUrl();
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim() ?? '';
        if (text.isNotEmpty) await _loadUrl(text);
      case 'settings':
        _showSettings();
      case 'help':
        _showHelp();
    }
  }

  Future<void> _parseClipboardUrl() async {
    if (directParsing) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板中没有网址')),
        );
      }
      return;
    }
    final url = _normalize(raw);
    setState(() {
      directParsing = true;
      directParseUrl = '';
    });
    try {
      final candidates = await sniffer.parsePage(url);
      final probedGroups = await Future.wait(
        candidates.map((candidate) async {
          try {
            return await sniffer.probeResource(candidate);
          } catch (_) {
            return const <VideoResource>[];
          }
        }),
      );
      final resources = sniffer
          .prioritizeResources(probedGroups.expand((group) => group).where(
            (resource) =>
                resource.isPlayable &&
                !resource.isFragment &&
                !resource.isAdSuspect,
          ).toList());
      if (!mounted) return;
      if (resources.isNotEmpty) {
        setState(() {
          directParsing = false;
          captured
            ..clear()
            ..addEntries(
              resources.map(
                (resource) =>
                    MapEntry(sniffer.dedupeKey(resource.url), resource),
              ),
            );
        });
        await _showDownloadPicker(title: resources.first.title);
        return;
      }

      // Some sites construct the player only after JavaScript runs. Load a
      // hidden one-pixel WebView as a fallback without navigating the browser.
      setState(() => directParseUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() => directParseUrl = url);
      }
    }
  }

  Future<void> _showSavedPages(int initialIndex) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DefaultTabController(
        length: 2,
        initialIndex: initialIndex,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.78,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    '收藏与历史',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.bookmark_rounded), text: '收藏夹'),
                    Tab(icon: Icon(Icons.history_rounded), text: '历史记录'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _BrowserRecordList(
                        records: bookmarks,
                        emptyText: '暂无收藏',
                        onOpen: (url) {
                          Navigator.pop(sheetContext);
                          unawaited(_loadUrl(url));
                        },
                        onRemove: _removeBookmark,
                      ),
                      _BrowserRecordList(
                        records: history,
                        emptyText: '暂无历史记录',
                        onOpen: (url) {
                          Navigator.pop(sheetContext);
                          unawaited(_loadUrl(url));
                        },
                        onRemove: _removeHistory,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => _SettingsSheet(
          adBlockEnabled: adBlockEnabled,
          blockPopups: blockPopups,
          blockTrackers: blockTrackers,
          onAdBlockChanged: (value) {
            setState(() => adBlockEnabled = value);
            setSheetState(() {});
            unawaited(_reload());
          },
          onPopupsChanged: (value) {
            setState(() => blockPopups = value);
            setSheetState(() {});
            unawaited(controller?.setSettings(settings: _settings()));
          },
          onTrackersChanged: (value) {
            setState(() => blockTrackers = value);
            setSheetState(() {});
            unawaited(_reload());
          },
        ),
      ),
    );
  }

  void _updateActiveTab({
    String? url,
    String? title,
    bool notify = true,
  }) {
    if (browserTabs.isEmpty || activeBrowserTab >= browserTabs.length) return;
    final current = browserTabs[activeBrowserTab];
    browserTabs[activeBrowserTab] = current.copyWith(url: url, title: title);
    if (notify && mounted) setState(() {});
  }

  Future<void> _showBrowserTabs() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '标签页',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _newBrowserTab();
                          Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    buildDefaultDragHandles: false,
                    itemCount: browserTabs.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final activeId = browserTabs[activeBrowserTab].id;
                        final item = browserTabs.removeAt(oldIndex);
                        browserTabs.insert(newIndex, item);
                        activeBrowserTab = browserTabs.indexWhere(
                          (tab) => tab.id == activeId,
                        );
                      });
                      setSheetState(() {});
                    },
                    itemBuilder: (context, index) {
                      final tab = browserTabs[index];
                      return Dismissible(
                        key: ValueKey(tab.id),
                        direction: browserTabs.length > 1
                            ? DismissDirection.endToStart
                            : DismissDirection.none,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: const Icon(Icons.close_rounded),
                        ),
                        onDismissed: (_) {
                          _closeBrowserTab(index);
                          setSheetState(() {});
                        },
                        child: ListTile(
                          selected: index == activeBrowserTab,
                          leading: const Icon(Icons.web_asset_rounded),
                          title: Text(
                            tab.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            tab.url == 'about:blank' ? '新标签页' : tab.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _activateBrowserTab(index);
                            Navigator.pop(sheetContext);
                          },
                          onLongPress: tab.url.startsWith('http')
                              ? () {
                                  Clipboard.setData(
                                    ClipboardData(text: tab.url),
                                  );
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    const SnackBar(content: Text('网址已复制')),
                                  );
                                }
                              : null,
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.drag_handle_rounded),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (recentlyClosedTabs.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.history_toggle_off_rounded),
                    title: const Text('最近关闭'),
                    subtitle: Text(recentlyClosedTabs.first.title),
                    onTap: () {
                      final tab = recentlyClosedTabs.removeAt(0);
                      setState(() {
                        browserTabs.add(tab);
                        activeBrowserTab = browserTabs.length - 1;
                      });
                      _activateBrowserTab(activeBrowserTab);
                      Navigator.pop(sheetContext);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _newBrowserTab() {
    setState(() {
      browserTabs.add(
        _BrowserTabData(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: '新窗口',
          url: 'about:blank',
        ),
      );
      activeBrowserTab = browserTabs.length - 1;
      showStartPage = true;
      currentUrl = 'about:blank';
      pageTitle = '新窗口';
      addressController.clear();
      captured.clear();
    });
  }

  void _activateBrowserTab(int index) {
    if (index < 0 || index >= browserTabs.length) return;
    final tab = browserTabs[index];
    setState(() {
      activeBrowserTab = index;
      currentUrl = tab.url;
      pageTitle = tab.title;
      showStartPage = tab.url == 'about:blank';
      addressController.text = showStartPage ? '' : tab.url;
      captured.clear();
    });
    if (!showStartPage) unawaited(_loadUrl(tab.url));
  }

  void _closeBrowserTab(int index) {
    if (browserTabs.length <= 1) return;
    final closed = browserTabs.removeAt(index);
    recentlyClosedTabs.insert(0, closed);
    if (recentlyClosedTabs.length > 10) recentlyClosedTabs.removeLast();
    activeBrowserTab =
        activeBrowserTab.clamp(0, browserTabs.length - 1).toInt();
    _activateBrowserTab(activeBrowserTab);
  }

  bool _shouldBlockRequest(String value) {
    if (!adBlockEnabled) return false;
    final lower = value.toLowerCase();
    const adTokens = [
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      '/ads/',
      '/advert',
      'adserver',
      'banner',
      'popunder',
    ];
    const trackerTokens = [
      'google-analytics.com',
      'googletagmanager.com',
      'facebook.net/tr',
      '/analytics',
      '/tracking',
      '/beacon',
    ];
    return adTokens.any(lower.contains) ||
        (blockTrackers && trackerTokens.any(lower.contains));
  }

  bool _shouldBlockNavigation(String value) {
    if (!blockPopups || value.isEmpty) return false;
    return _shouldBlockRequest(value) ||
        value.startsWith('intent:') ||
        value.startsWith('itms-services:');
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用方法'),
        content: const Text('打开网页并播放视频，右下角会出现下载按钮。未检测到时，先播放几秒再点击下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _remember(String url) {
    if (url.startsWith('about:')) return;
    final host = Uri.tryParse(url)?.host ?? '';
    setState(() {
      history.removeWhere((item) => item.url == url);
      history.insert(
        0,
        BrowserPageRecord(
          url: url,
          title: host,
          updatedAt: DateTime.now(),
        ),
      );
      if (history.length > 200) history.removeRange(200, history.length);
    });
    unawaited(_saveBrowserData());
  }

  bool get _isCurrentPageBookmarked =>
      bookmarks.any((item) => item.url == currentUrl);

  void _toggleBookmark() {
    final index = bookmarks.indexWhere((item) => item.url == currentUrl);
    setState(() {
      if (index >= 0) {
        bookmarks.removeAt(index);
      } else {
        bookmarks.insert(
          0,
          BrowserPageRecord(
            url: currentUrl,
            title: pageTitle,
            updatedAt: DateTime.now(),
          ),
        );
      }
    });
    unawaited(_saveBrowserData());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(index >= 0 ? '已取消收藏' : '已加入收藏')),
    );
  }

  void _removeHistory(String url) {
    setState(() => history.removeWhere((item) => item.url == url));
    unawaited(_saveBrowserData());
  }

  void _removeBookmark(String url) {
    setState(() => bookmarks.removeWhere((item) => item.url == url));
    unawaited(_saveBrowserData());
  }

  void _updateSavedTitle(String title) {
    final historyIndex = history.indexWhere((item) => item.url == currentUrl);
    final bookmarkIndex =
        bookmarks.indexWhere((item) => item.url == currentUrl);
    if (historyIndex < 0 && bookmarkIndex < 0) return;
    setState(() {
      if (historyIndex >= 0) {
        history[historyIndex] = history[historyIndex].copyWith(title: title);
      }
      if (bookmarkIndex >= 0) {
        bookmarks[bookmarkIndex] =
            bookmarks[bookmarkIndex].copyWith(title: title);
      }
    });
    unawaited(_saveBrowserData());
  }

  Future<void> _loadBrowserData() async {
    final data = await browserDataStore.load();
    if (!mounted) return;
    setState(() {
      for (final item in data.history) {
        if (!history.any((current) => current.url == item.url)) {
          history.add(item);
        }
      }
      for (final item in data.bookmarks) {
        if (!bookmarks.any((current) => current.url == item.url)) {
          bookmarks.add(item);
        }
      }
    });
  }

  Future<void> _saveBrowserData() => browserDataStore.save(
        history: history,
        bookmarks: bookmarks,
      );

  String _normalize(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (text.contains('.') && !text.contains(' ')) return 'https://$text';
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(text)}';
  }

  String _absoluteUrl(String value) {
    try {
      return Uri.parse(currentUrl).resolve(value).toString();
    } catch (_) {
      return value.trim();
    }
  }

  String _origin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}';
  }

  static const _scanScript = r'''
(() => {
  const title = document.querySelector('meta[property="og:title"],meta[name="twitter:title"]')?.content || document.title || '';
  const out = [];
  const push = (url, source, media) => {
    if (!url) return;
    out.push({
      url,
      source,
      title,
      duration: media && Number.isFinite(media.duration) ? media.duration : 0,
      poster: media ? (media.poster || '') : '',
      current: !!(media && (!media.paused || media.currentTime > 0)),
      sources: media ? Array.from(media.querySelectorAll('source')).map(s => s.src || s.getAttribute('src') || '').filter(Boolean) : []
    });
  };
  document.querySelectorAll('video,audio').forEach(v => {
    push(v.currentSrc || v.src, 'video', v);
    Array.from(v.querySelectorAll('source')).forEach(s => push(s.src || s.getAttribute('src'), 'source', v));
  });
  Array.from(document.querySelectorAll('a[href]')).forEach(a => {
    const href = a.href || '';
    if (/\.(mp4|m4v|mov|webm|m3u8)(\?|#|$)/i.test(href)) push(href, 'link', null);
  });
  return JSON.stringify(out);
})();
''';

  static const _hookScript = r'''
(() => {
  if (window.__videoDownloaderHooked) return;
  window.__videoDownloaderHooked = true;
  const title = () => document.querySelector('meta[property="og:title"],meta[name="twitter:title"]')?.content || document.title || '';
  const likely = u => typeof u === 'string' && /\.(mp4|m4v|mov|webm|m3u8)(\?|#|$)/i.test(u);
  const post = (url, source, media) => {
    try {
      if (!url || !likely(url)) return;
      window.flutter_inappwebview.callHandler('VideoDownloaderCapture', {
        url: new URL(url, location.href).href,
        source,
        title: title(),
        duration: media && Number.isFinite(media.duration) ? media.duration : 0,
        poster: media ? (media.poster || '') : '',
        current: !!(media && (!media.paused || media.currentTime > 0)),
        sources: media ? Array.from(media.querySelectorAll('source')).map(s => s.src || s.getAttribute('src') || '').filter(Boolean) : []
      });
    } catch (_) {}
  };
  const bind = media => {
    if (!media || media.__videoDownloaderBound) return;
    media.__videoDownloaderBound = true;
    ['play','playing','loadedmetadata','canplay','durationchange'].forEach(event => {
      media.addEventListener(event, () => post(media.currentSrc || media.src, event === 'play' || event === 'playing' ? 'current-video' : 'video', media), true);
    });
  };
  document.querySelectorAll('video,audio').forEach(bind);
  new MutationObserver(ms => ms.forEach(m => m.addedNodes.forEach(n => {
    if (!n.querySelectorAll) return;
    if (n.tagName === 'VIDEO' || n.tagName === 'AUDIO') bind(n);
    n.querySelectorAll('video,audio').forEach(bind);
  }))).observe(document.documentElement, {childList:true, subtree:true});
  const oldFetch = window.fetch;
  if (oldFetch) {
    window.fetch = function() {
      try {
        const input = arguments[0];
        const url = typeof input === 'string' ? input : input && input.url;
        post(url, 'fetch', null);
      } catch (_) {}
      return oldFetch.apply(this, arguments).then(r => {
        try { post(r.url, 'fetch-response', null); } catch (_) {}
        return r;
      });
    };
  }
  const oldOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    post(url, 'xhr', null);
    return oldOpen.apply(this, arguments);
  };
})();
''';

  static const _adBlockScript = r'''
(() => {
  const selectors = [
    '[id*="ad-"]', '[id^="ad_"]', '[class*=" ad-"]',
    '[class^="ad-"]', '[class*="advert"]', '[class*="banner"]',
    '[class*="popup"]', '[class*="popunder"]',
    'iframe[src*="ads"]', 'iframe[src*="doubleclick"]'
  ];
  const hide = root => {
    try {
      root.querySelectorAll(selectors.join(',')).forEach(node => {
        node.style.setProperty('display', 'none', 'important');
      });
    } catch (_) {}
  };
  hide(document);
  new MutationObserver(records => records.forEach(record =>
    record.addedNodes.forEach(node => {
      if (node.nodeType === 1) {
        if (node.matches && node.matches(selectors.join(','))) node.remove();
        if (node.querySelectorAll) hide(node);
      }
    })
  )).observe(document.documentElement, {childList: true, subtree: true});
  window.open = () => null;
})();
''';
}

class _BrowserTabData {
  const _BrowserTabData({
    required this.id,
    required this.title,
    required this.url,
  });

  final String id;
  final String title;
  final String url;

  _BrowserTabData copyWith({String? title, String? url}) {
    return _BrowserTabData(
      id: id,
      title: title ?? this.title,
      url: url ?? this.url,
    );
  }
}

class _StartPage extends StatefulWidget {
  const _StartPage({
    required this.onOpen,
    required this.onParseClipboard,
    required this.parsing,
  });

  final ValueChanged<String> onOpen;
  final VoidCallback onParseClipboard;
  final bool parsing;

  @override
  State<_StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<_StartPage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText: '搜索或输入网址',
            suffixIcon: IconButton(
              icon: const Icon(Icons.keyboard_return_rounded),
              onPressed: () => widget.onOpen(controller.text),
            ),
          ),
          onSubmitted: widget.onOpen,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: widget.parsing ? null : widget.onParseClipboard,
          icon: widget.parsing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.content_paste_go_rounded),
          label: Text(widget.parsing ? '正在解析…' : '粘贴网址直接解析视频'),
        ),
        const SizedBox(height: 26),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 20,
          crossAxisSpacing: 14,
          children: [
            _SiteShortcut(label: 'Facebook', color: const Color(0xff1877f2), text: 'f', url: 'https://www.facebook.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Instagram', color: const Color(0xffe4405f), text: '◎', url: 'https://www.instagram.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Vimeo', color: const Color(0xff1ab7ea), text: 'v', url: 'https://vimeo.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Dailymotion', color: const Color(0xff00aaff), text: 'd', url: 'https://www.dailymotion.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Twitter', color: const Color(0xff1da1f2), text: 't', url: 'https://twitter.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'TikTok', color: Colors.black, text: '♪', url: 'https://www.tiktok.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'WhatsApp', color: const Color(0xff25d366), text: 'w', url: 'https://www.whatsapp.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Google', color: const Color(0xff4285f4), text: 'G', url: 'https://www.google.com', onOpen: widget.onOpen),
          ],
        ),
        const SizedBox(height: 42),
        Center(
          child: TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.feedback_rounded),
            label: const Text('有反馈或问题吗？联系我们'),
          ),
        ),
      ],
    );
  }
}

class _SiteShortcut extends StatelessWidget {
  const _SiteShortcut({
    required this.label,
    required this.color,
    required this.text,
    required this.url,
    required this.onOpen,
  });

  final String label;
  final Color color;
  final String text;
  final String url;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onOpen(url),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: color,
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBar extends StatelessWidget {
  const _AddressBar({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: 1,
      textInputAction: TextInputAction.go,
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.lock_rounded, size: 18),
        hintText: '搜索或输入网址',
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _DownloadFloatButton extends StatelessWidget {
  const _DownloadFloatButton({
    required this.count,
    required this.busy,
    required this.onPressed,
  });

  final int count;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'video-download-fab',
      onPressed: onPressed,
      backgroundColor: count > 0 ? Colors.redAccent : null,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.file_download_rounded),
            ),
    );
  }
}

class _DetectionBar extends StatelessWidget {
  const _DetectionBar({
    required this.count,
    required this.onTap,
    required this.onParse,
  });

  final int count;
  final VoidCallback? onTap;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                count > 0 ? Icons.check_circle : Icons.info_outline,
                color: count > 0 ? Colors.green : scheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count > 0 ? '发现 $count 个视频' : '播放视频后点击下载',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: onParse,
                child: const Text('检测'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadPicker extends StatefulWidget {
  const _DownloadPicker({
    required this.title,
    required this.resources,
    required this.onDownload,
  });

  final String title;
  final List<VideoResource> resources;
  final FutureOr<void> Function(VideoResource) onDownload;

  @override
  State<_DownloadPicker> createState() => _DownloadPickerState();
}

class _DownloadPickerState extends State<_DownloadPicker> {
  late VideoResource selected = widget.resources.first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('网络', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Icon(Icons.wifi_rounded, color: scheme.primary),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 92,
                  height: 74,
                  alignment: Alignment.center,
                  color: scheme.primaryContainer,
                  child: Icon(Icons.movie_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title.trim().isEmpty ? selected.title : widget.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final resource in widget.resources)
                  ChoiceChip(
                    selected: resource.url == selected.url,
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            resource.quality == '未知'
                                ? resource.displayFormat
                                : resource.quality,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(resource.size),
                          if (resource.duration > Duration.zero)
                            Text(_formatVideoDuration(resource.duration)),
                        ],
                      ),
                    ),
                    onSelected: (_) => setState(() => selected = resource),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () async => widget.onDownload(selected),
                icon: const Icon(Icons.file_download_rounded),
                label: const Text('下载'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatVideoDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

class _BrowserBottomControls extends StatelessWidget {
  const _BrowserBottomControls({
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onNew,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(onPressed: canGoBack ? onBack : null, icon: const Icon(Icons.arrow_back_rounded)),
          IconButton(onPressed: onHome, icon: const Icon(Icons.home_rounded)),
          IconButton(onPressed: canGoForward ? onForward : null, icon: const Icon(Icons.arrow_forward_rounded)),
          IconButton(onPressed: onNew, icon: const Icon(Icons.add_rounded)),
        ],
      ),
    );
  }
}

class _TabsDrawer extends StatelessWidget {
  const _TabsDrawer({
    required this.history,
    required this.bookmarks,
    required this.onOpen,
    required this.onClearHistory,
    required this.onRemoveHistory,
    required this.onRemoveBookmark,
  });

  final List<BrowserPageRecord> history;
  final List<BrowserPageRecord> bookmarks;
  final ValueChanged<String> onOpen;
  final VoidCallback onClearHistory;
  final ValueChanged<String> onRemoveHistory;
  final ValueChanged<String> onRemoveBookmark;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: DefaultTabController(
        length: 2,
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: const Text(
                  '浏览器',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                trailing: IconButton(
                  tooltip: '清空历史记录',
                  onPressed: history.isEmpty ? null : onClearHistory,
                  icon: const Icon(Icons.delete_sweep_rounded),
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.bookmark_rounded), text: '收藏'),
                  Tab(icon: Icon(Icons.history_rounded), text: '历史'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _BrowserRecordList(
                      records: bookmarks,
                      emptyText: '暂无收藏',
                      onOpen: onOpen,
                      onRemove: onRemoveBookmark,
                    ),
                    _BrowserRecordList(
                      records: history,
                      emptyText: '暂无历史记录',
                      onOpen: onOpen,
                      onRemove: onRemoveHistory,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserRecordList extends StatelessWidget {
  const _BrowserRecordList({
    required this.records,
    required this.emptyText,
    required this.onOpen,
    required this.onRemove,
  });

  final List<BrowserPageRecord> records;
  final String emptyText;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return Center(child: Text(emptyText));
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final host = Uri.tryParse(record.url)?.host ?? record.url;
        return Dismissible(
          key: ValueKey('${record.url}-${record.updatedAt.microsecondsSinceEpoch}'),
          direction: DismissDirection.endToStart,
          background: const ColoredBox(
            color: Colors.redAccent,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 22),
                child: Icon(Icons.delete_rounded, color: Colors.white),
              ),
            ),
          ),
          onDismissed: (_) => onRemove(record.url),
          child: ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(
              record.title.trim().isEmpty ? host : record.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              record.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onOpen(record.url),
          ),
        );
      },
    );
  }
}

class _TabCountBadge extends StatelessWidget {
  const _TabCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$count', style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.adBlockEnabled,
    required this.blockPopups,
    required this.blockTrackers,
    required this.onAdBlockChanged,
    required this.onPopupsChanged,
    required this.onTrackersChanged,
  });

  final bool adBlockEnabled;
  final bool blockPopups;
  final bool blockTrackers;
  final ValueChanged<bool> onAdBlockChanged;
  final ValueChanged<bool> onPopupsChanged;
  final ValueChanged<bool> onTrackersChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('浏览器设置', style: TextStyle(fontSize: 22)),
          ),
          SwitchListTile(
            value: adBlockEnabled,
            onChanged: onAdBlockChanged,
            title: const Text('广告拦截'),
            subtitle: const Text('隐藏横幅、广告脚本和常见广告框架'),
          ),
          SwitchListTile(
            value: blockPopups,
            onChanged: onPopupsChanged,
            title: const Text('阻止弹窗与自动跳转'),
          ),
          SwitchListTile(
            value: blockTrackers,
            onChanged: adBlockEnabled ? onTrackersChanged : null,
            title: const Text('隐私追踪过滤'),
          ),
          const ListTile(
            title: Text('过滤模式'),
            subtitle: Text('基础过滤 + 去弹窗 + 去追踪'),
          ),
        ],
      ),
    );
  }
}
