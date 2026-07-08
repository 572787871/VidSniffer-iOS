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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _BrowserTopBar(
              controller: addressController,
              canGoBack: canGoBack,
              canGoForward: canGoForward,
              loading: loading,
              tabCount: browser.history.length.clamp(1, 99).toInt(),
              onHome: () => _loadUrl(browser.homeUrl),
              onBack: _goBack,
              onForward: _goForward,
              onSubmit: _loadUrl,
              onStopOrReload: loading ? _stopLoading : _reload,
              onMenu: _showBrowserMenu,
            ),
            if (loading || deepSniffing)
              LinearProgressIndicator(
                value: deepSniffing ? null : (progress <= 0 ? null : progress / 100),
                minHeight: 2,
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
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
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: _BrowserFoundBar(
                      count: resources.length,
                      deepSniffing: deepSniffing,
                      onOpenResources:
                          resources.isEmpty ? null : _openResources,
                      onParse: deepSniffing ? null : _autoParsePage,
                    ),
                  ),
                ],
              ),
            ),
            _BrowserBottomBar(
              canGoBack: canGoBack,
              canGoForward: canGoForward,
              bookmarked: browser.bookmarks.contains(currentUrl),
              loading: loading,
              onBack: _goBack,
              onForward: _goForward,
              onReload: loading ? _stopLoading : _reload,
              onTabs: _showHistory,
              onBookmark: () {
                setState(() => browser.toggleBookmark(currentUrl));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBrowserMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('解析设置'),
              subtitle: const Text('智能模式、全量模式和资源类型过滤'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showParseSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.radar_rounded),
              title: const Text('自动解析整页'),
              subtitle: const Text('开启深度嗅探 5 秒后展示资源'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_autoParsePage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('历史记录'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showHistory();
              },
            ),
            ListTile(
              leading: Icon(
                browser.bookmarks.contains(currentUrl)
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
              title: Text(
                browser.bookmarks.contains(currentUrl) ? '取消收藏' : '收藏书签',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => browser.toggleBookmark(currentUrl));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHistory() async {
    final history = browser.history.take(20).toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                '历史记录',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (history.isEmpty)
              const ListTile(title: Text('暂无历史记录'))
            else
              for (final url in history)
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: Text(
                    Uri.tryParse(url)?.host ?? url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_loadUrl(url));
                  },
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showParseSettings() async {
    var smartMode = true;
    var video = true;
    var audio = true;
    var images = false;
    var live = true;
    var xhr = true;
    var mediaSource = true;
    var mergeM3u8 = true;
    var filterAds = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Expanded(
                        child: Text(
                          '解析设置',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _SettingsLabel('解析模式'),
                  _ModeOption(
                    title: '智能模式（推荐）',
                    subtitle: '自动检测视频，性能更好',
                    selected: smartMode,
                    onTap: () => setSheetState(() => smartMode = true),
                  ),
                  const SizedBox(height: 8),
                  _ModeOption(
                    title: '全量模式',
                    subtitle: '深度扫描页面资源',
                    selected: !smartMode,
                    onTap: () => setSheetState(() => smartMode = false),
                  ),
                  const SizedBox(height: 18),
                  const _SettingsLabel('资源类型'),
                  _SwitchRow(
                    title: '视频（mp4, m3u8, webm）',
                    value: video,
                    onChanged: (value) => setSheetState(() => video = value),
                  ),
                  _SwitchRow(
                    title: '音频（mp3, m4a, aac）',
                    value: audio,
                    onChanged: (value) => setSheetState(() => audio = value),
                  ),
                  _SwitchRow(
                    title: '图片',
                    value: images,
                    onChanged: (value) => setSheetState(() => images = value),
                  ),
                  _SwitchRow(
                    title: '直播流（m3u8, flv）',
                    value: live,
                    onChanged: (value) => setSheetState(() => live = value),
                  ),
                  const SizedBox(height: 18),
                  const _SettingsLabel('高级选项'),
                  _SwitchRow(
                    title: '捕获 XHR / Fetch',
                    value: xhr,
                    onChanged: (value) => setSheetState(() => xhr = value),
                  ),
                  _SwitchRow(
                    title: '捕获 Media Source',
                    value: mediaSource,
                    onChanged: (value) =>
                        setSheetState(() => mediaSource = value),
                  ),
                  _SwitchRow(
                    title: '自动合并 m3u8',
                    value: mergeM3u8,
                    onChanged: (value) => setSheetState(() => mergeM3u8 = value),
                  ),
                  _SwitchRow(
                    title: '过滤广告和跟踪',
                    value: filterAds,
                    onChanged: (value) => setSheetState(() => filterAds = value),
                  ),
                  const SizedBox(height: 18),
                  _SettingsActionRow(
                    title: '最大捕获时间',
                    value: '5 秒',
                    onTap: () {},
                  ),
                  _SettingsActionRow(
                    title: '清除缓存',
                    value: '',
                    onTap: () {
                      setState(() => resources = const []);
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已清除当前页面资源缓存')),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        if (!smartMode) unawaited(_autoParsePage());
                      },
                      child: const Text('保存设置'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

class _BrowserTopBar extends StatelessWidget {
  const _BrowserTopBar({
    required this.controller,
    required this.canGoBack,
    required this.canGoForward,
    required this.loading,
    required this.tabCount,
    required this.onHome,
    required this.onBack,
    required this.onForward,
    required this.onSubmit,
    required this.onStopOrReload,
    required this.onMenu,
  });

  final TextEditingController controller;
  final bool canGoBack;
  final bool canGoForward;
  final bool loading;
  final int tabCount;
  final VoidCallback onHome;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<String> onSubmit;
  final VoidCallback onStopOrReload;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Row(
        children: [
          IconButton(
            tooltip: '主页',
            onPressed: onHome,
            icon: const Icon(Icons.home_outlined),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '返回',
            onPressed: canGoBack ? onBack : null,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '前进',
            onPressed: canGoForward ? onForward : null,
            icon: const Icon(Icons.arrow_forward_ios_rounded),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 1,
              textInputAction: TextInputAction.go,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                hintText: '输入网址',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.66),
              ),
              onSubmitted: onSubmit,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                '$tabCount',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: loading ? '停止加载' : '刷新',
            onPressed: onStopOrReload,
            icon: Icon(loading ? Icons.close_rounded : Icons.refresh_rounded),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '更多',
            onPressed: onMenu,
            icon: const Icon(Icons.more_vert_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _BrowserFoundBar extends StatelessWidget {
  const _BrowserFoundBar({
    required this.count,
    required this.deepSniffing,
    required this.onOpenResources,
    required this.onParse,
  });

  final int count;
  final bool deepSniffing;
  final VoidCallback? onOpenResources;
  final VoidCallback? onParse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: count > 0 ? Colors.greenAccent.shade400 : scheme.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: onOpenResources,
                child: Text(
                  count > 0 ? '发现 $count 个视频' : '播放视频后可长按解析',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            TextButton(
              onPressed: onParse,
              child: Text(deepSniffing ? '解析中' : '解析页面'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserBottomBar extends StatelessWidget {
  const _BrowserBottomBar({
    required this.canGoBack,
    required this.canGoForward,
    required this.bookmarked,
    required this.loading,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onTabs,
    required this.onBookmark,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool bookmarked;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onTabs;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: canGoBack ? onBack : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: '前进',
            onPressed: canGoForward ? onForward : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          IconButton(
            tooltip: loading ? '停止加载' : '刷新',
            onPressed: onReload,
            icon: Icon(loading ? Icons.stop_rounded : Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '历史记录',
            onPressed: onTabs,
            icon: const Icon(Icons.crop_square_rounded),
          ),
          IconButton(
            tooltip: bookmarked ? '取消收藏' : '收藏',
            onPressed: onBookmark,
            icon: Icon(bookmarked ? Icons.star_rounded : Icons.star_border_rounded),
          ),
        ],
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        dense: true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value.isNotEmpty)
              Text(value, style: TextStyle(color: scheme.onSurfaceVariant)),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _TimedBrowserCandidate {
  const _TimedBrowserCandidate(this.candidate, this.capturedAt);

  final BrowserCandidate candidate;
  final DateTime capturedAt;
}
