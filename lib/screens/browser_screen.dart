import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/video_resource.dart';
import '../services/browser_data_store.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';
import '../services/video_sniffer_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_ui.dart';
import '../widgets/download_confirm_dialog.dart';
import 'downloads_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.active = true});

  final bool active;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final addressController = TextEditingController();
  final sniffer = VideoSniffer();
  final BrowserDataStore browserDataStore = BrowserDataStore();
  final List<BrowserPageRecord> history = [];
  final List<BrowserPageRecord> bookmarks = [];
  final List<_BrowserTabData> browserTabs = [
    _BrowserTabData(
      id: 'initial',
      title: '新窗口',
      url: 'about:blank',
      keepAlive: InAppWebViewKeepAlive(),
    ),
  ];
  final List<_BrowserTabData> recentlyClosedTabs = [];
  final List<_ParseHistoryEntry> parseHistory = [];
  final Map<String, VideoResource> captured = {};
  final Map<String, InAppWebViewController> tabControllers = {};
  late final VideoSnifferController snifferController;

  InAppWebViewController? controller;
  Timer? deepTimer;
  Timer? flushTimer;
  String currentUrl = 'about:blank';
  String pageTitle = '新窗口';
  String userAgent = '';
  String currentCookie = '';
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  bool deepCapture = false;
  bool showStartPage = true;
  int progress = 0;
  int handledBrowserRequestId = 0;
  int activeBrowserTab = 0;
  bool adBlockEnabled = true;
  bool blockPopups = true;
  bool blockTrackers = true;
  bool browserTabsSheetOpen = false;
  bool creatingBrowserTab = false;
  bool browserDataLoaded = false;
  String detectionNotice = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    deepTimer?.cancel();
    flushTimer?.cancel();
    snifferController.dispose();
    addressController.dispose();
    if (browserDataLoaded) unawaited(_saveBrowserData());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      unawaited(_pauseAllWebMedia());
    }
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
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: showStartPage
                  ? _StartPage(
                      onOpen: _loadUrl,
                      tabs: browserTabs,
                      activeTab: activeBrowserTab,
                      recentlyClosed: recentlyClosedTabs,
                      onActivateTab: _activateBrowserTab,
                      onCloseTab: _closeBrowserTab,
                      onNewTab: _newBrowserTab,
                      onRestoreRecent: _restoreRecentlyClosedTab,
                    )
                  : _browserBody(),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _startAppBar() {
    return AppBar(
      toolbarHeight: 76,
      titleSpacing: 24,
      titleTextStyle: Theme.of(context).textTheme.displaySmall,
      title: const Text('浏览器'),
      actions: [
        IconButton(
          tooltip: '智能解析',
          onPressed: _openSmartParsePage,
          icon: const Icon(CupertinoIcons.link),
        ),
        _TabCountButton(
          count: browserTabs.length,
          onTap: _showBrowserTabs,
        ),
        _browserMenu(startPage: true),
        const SizedBox(width: 8),
      ],
    );
  }

  PreferredSizeWidget _browserAppBar() {
    return AppBar(
      toolbarHeight: 58,
      titleSpacing: 14,
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
        _browserMenu(startPage: false),
      ],
    );
  }

  Widget _browserMenu({required bool startPage}) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      position: PopupMenuPosition.under,
      offset: const Offset(-8, 8),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 238),
      icon: const Icon(CupertinoIcons.ellipsis),
      onSelected: _handleMenu,
      itemBuilder: (context) => startPage
          ? [
              _browserMenuItem(
                'smartParse',
                CupertinoIcons.link,
                '智能解析',
              ),
              _browserMenuItem(
                'paste',
                Icons.content_paste_go_rounded,
                '粘贴并打开',
              ),
              _browserMenuItem(
                'favorites',
                Icons.bookmark_border_rounded,
                '收藏夹',
              ),
              _browserMenuItem(
                'history',
                Icons.history_rounded,
                '历史记录',
              ),
              _browserMenuItem(
                'downloadHistory',
                Icons.download_done_rounded,
                '下载记录',
              ),
              _browserMenuItem(
                'help',
                Icons.help_outline_rounded,
                '帮助',
              ),
              _browserMenuItem(
                'settings',
                Icons.tune_rounded,
                '浏览器设置',
              ),
            ]
          : [
              _browserMenuItem('home', Icons.home_outlined, '主页'),
              _browserMenuItem(
                'sniff',
                Icons.video_library_outlined,
                '重新解析视频',
              ),
              _browserMenuItem(
                'favorites',
                Icons.bookmark_border_rounded,
                '收藏夹',
              ),
              _browserMenuItem(
                'history',
                Icons.history_rounded,
                '历史记录',
              ),
              _browserMenuItem(
                'downloadHistory',
                Icons.download_done_rounded,
                '下载记录',
              ),
              _browserMenuItem(
                'smartParse',
                CupertinoIcons.link,
                '智能解析',
              ),
              _browserMenuItem(
                'copy',
                Icons.content_copy_rounded,
                '复制网址',
              ),
              _browserMenuItem(
                'settings',
                Icons.tune_rounded,
                '浏览器设置',
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
                  key: ValueKey(browserTabs[activeBrowserTab].id),
                  keepAlive: browserTabs[activeBrowserTab].keepAlive,
                  initialUserScripts: UnmodifiableListView([
                    if (adBlockEnabled)
                      UserScript(
                        source: _adBlockScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                  ]),
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
                      detectionNotice = '';
                    });
                    _remember(next);
                    _updateActiveTab(url: next);
                  },
                  onLoadStop: (_, url) async {
                    currentUrl = url?.toString() ?? currentUrl;
                    await _syncBrowserState();
                    unawaited(_refreshCurrentCookie());
                    await _injectHooks();
                    await _scanDom();
                    unawaited(_captureEmbeddedPageResources());
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
                    final url = resource.url.toString();
                    if (_looksLikeMediaRequest(url)) {
                      snifferController.captureNetwork(url, 'resource');
                    }
                  },
                  shouldOverrideUrlLoading: (_, action) async {
                    final url = action.request.url?.toString() ?? '';
                    if (_shouldBlockNavigation(url)) {
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                ),
              ),
              if (MediaQuery.viewInsetsOf(context).bottom > 0)
                Positioned(
                  right: 16,
                  bottom: 80,
                  child: FilledButton.tonalIcon(
                    onPressed: _dismissKeyboard,
                    icon: const Icon(Icons.keyboard_hide_rounded),
                    label: const Text('完成'),
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
          tabCount: browserTabs.length,
          onTabs: _showBrowserTabs,
          videoCount: _downloadable.length,
          detectingVideo: deepCapture,
          notice: detectionNotice,
          onDetectVideo: _downloadable.isEmpty
              ? () => _sniffPage(openPicker: true)
              : _showDownloadPicker,
        ),
      ],
    );
  }

  Future<void> _onWebViewCreated(InAppWebViewController value) async {
    controller = value;
    tabControllers[browserTabs[activeBrowserTab].id] = value;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_pauseAllWebMedia());
    }
  }

  Future<void> _pauseAllWebMedia() async {
    await Future.wait(tabControllers.values.map(_pauseWebMedia));
  }

  Future<void> _pauseWebMedia(InAppWebViewController web) async {
    try {
      await web.evaluateJavascript(
        source: '''
          document.querySelectorAll('video,audio').forEach(media => {
            try { media.pause(); } catch (_) {}
          });
        ''',
      );
    } catch (_) {}
  }

  InAppWebViewSettings _settings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useShouldInterceptRequest: false,
      useShouldInterceptAjaxRequest: false,
      useShouldInterceptFetchRequest: false,
      useShouldOverrideUrlLoading: true,
      contentBlockers: adBlockEnabled
          ? [
              ContentBlocker(
                trigger: ContentBlockerTrigger(urlFilter: '.*'),
                action: ContentBlockerAction(
                  type: ContentBlockerActionType.CSS_DISPLAY_NONE,
                  selector: _adBlockSelector,
                ),
              ),
            ]
          : const [],
      javaScriptCanOpenWindowsAutomatically: !blockPopups,
      supportZoom: true,
    );
  }

  List<VideoResource> get _downloadable {
    var values = captured.values
        .where((item) => item.isPlayable && !item.isAdSuspect && !item.isFragment)
        .toList();
    final longest = values.fold<int>(
      0,
      (current, item) => item.duration.inSeconds > current
          ? item.duration.inSeconds
          : current,
    );
    if (longest >= 90) {
      values = values
          .where(
            (item) =>
                item.duration == Duration.zero ||
                item.duration.inSeconds >= longest * 0.55,
          )
          .toList();
    }
    values = _collapseVideoQualities(values);
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
    unawaited(_pauseAllWebMedia());
    setState(() {
      showStartPage = true;
      captured.clear();
      addressController.clear();
    });
  }

  Future<void> _reload() async => controller?.reload();

  Future<void> _stopLoading() async => controller?.stopLoading();

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

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

  Future<void> _captureEmbeddedPageResources() async {
    final pageUrl = currentUrl;
    final host = Uri.tryParse(pageUrl)?.host.toLowerCase() ?? '';
    final supported =
        host == 'xhchannel.com' ||
        host.endsWith('.xhchannel.com') ||
        host == 'xhamster.com' ||
        host.endsWith('.xhamster.com') ||
        host == 'noodlemagazine.com' ||
        host.endsWith('.noodlemagazine.com');
    if (!supported) return;
    try {
      final resources = await sniffer.parsePage(
        pageUrl,
        userAgent: userAgent,
        cookie: await _cookiesFor(pageUrl),
      );
      if (!mounted || pageUrl != currentUrl || resources.isEmpty) return;
      setState(() {
        for (final resource in resources.where(
          (item) => item.isPlayable && !item.isAdSuspect && !item.isFragment,
        )) {
          captured[sniffer.dedupeKey(resource.url)] = resource;
        }
        detectionNotice = '';
      });
    } catch (error) {
      debugPrint('[browser] embedded media parse failed: $error');
    }
  }

  Future<void> _sniffPage({required bool openPicker}) async {
    final web = controller;
    if (web == null) return;
    setState(() => deepCapture = true);
    await web.setSettings(settings: _settings());
    await _injectHooks();
    await _scanDom();
    await _captureEmbeddedPageResources();
    deepTimer?.cancel();
    for (var attempt = 0; attempt < 10 && _downloadable.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
    await web.setSettings(settings: _settings());
    if (!mounted) return;
    setState(() => deepCapture = false);
    if (openPicker) {
      if (_downloadable.isEmpty) {
        setState(() {
          detectionNotice = '暂未检测到视频，可播放后重试';
        });
      } else {
        if (detectionNotice.isNotEmpty) {
          setState(() => detectionNotice = '');
        }
        unawaited(_showDownloadPicker());
      }
    }
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
    final quality = _qualityLabel(value['quality']?.toString() ?? '');
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
        quality: quality,
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
    String quality = '未知',
  }) {
    snifferController.capture(
      _absoluteUrl(url),
      source,
      title: title,
      duration: duration,
      thumbnailUrl: poster,
      quality: quality,
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
    var resources = _downloadable;
    if (resources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先播放视频，再点击下载按钮')),
      );
      return;
    }
    final pageCover = await _currentPageCover();
    final cover = pageCover.isNotEmpty
        ? pageCover
        : resources
            .map((resource) => resource.thumbnailUrl)
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (!mounted) return;
    if (cover.isNotEmpty) {
      resources = resources
          .map(
            (resource) => resource.thumbnailUrl.trim().isEmpty
                ? resource.copyWith(thumbnailUrl: cover)
                : resource,
          )
          .toList(growable: false);
    }
    final appState = UiStateScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _DownloadPicker(
        title: title ?? pageTitle,
        resources: resources,
        coverUrl: cover,
        loadCoverBytes: (url) async {
          final credentialed = await _withCurrentCredentials(resources.first);
          return _loadCoverBytes(
            url,
            referer: credentialed.pageUrl,
            coverUserAgent: credentialed.userAgent,
            coverCookie: credentialed.cookie,
          );
        },
        onProbe: (resource) async => sniffer.probeResource(
          await _withCurrentCredentials(resource),
        ),
        onDownload: (resource) async {
          final credentialed = await _withCurrentCredentials(resource);
          if (!sheetContext.mounted) return;
          Navigator.pop(sheetContext);
          await Future<void>.delayed(const Duration(milliseconds: 180));
          if (!mounted) return;
          final selected = await showDownloadConfirmDialog(
            context,
            credentialed,
          );
          if (selected == null || !mounted) return;
          appState.downloadResource(selected);
        },
      ),
    );
  }

  Future<Uint8List?> _loadCoverBytes(
    String url, {
    String referer = '',
    String coverUserAgent = '',
    String coverCookie = '',
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.refererHeader,
        referer.isNotEmpty ? referer : currentUrl,
      );
      final effectiveUserAgent =
          coverUserAgent.isNotEmpty ? coverUserAgent : userAgent;
      if (effectiveUserAgent.isNotEmpty) {
        request.headers.set(HttpHeaders.userAgentHeader, effectiveUserAgent);
      }
      final effectiveCookie =
          coverCookie.isNotEmpty ? coverCookie : currentCookie;
      if (effectiveCookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, effectiveCookie);
      }
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response) {
        length += chunk.length;
        if (length > 6 * 1024 * 1024) return null;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _currentPageCover() async {
    try {
      final value = await controller?.evaluateJavascript(
        source: '''
          (() => {
            const mediaPoster = Array.from(document.querySelectorAll('video'))
              .map(video => video.poster || video.getAttribute('poster') || '')
              .find(Boolean);
            if (mediaPoster) return new URL(mediaPoster, location.href).href;
            for (const key of Object.keys(window)) {
              if (!/flashvars|player/i.test(key)) continue;
              try {
                const value = window[key];
                const poster = value && (
                  value.image_url || value.imageUrl || value.poster ||
                  value.thumbnail_url
                );
                if (poster) return new URL(poster, location.href).href;
              } catch (_) {}
            }
            const meta = document.querySelector(
              'meta[property="og:image"],meta[name="twitter:image"]'
            );
            if (meta && meta.content) {
              return new URL(meta.content, location.href).href;
            }
            const player = document.querySelector('.dplayer,[data-config]');
            const images = Array.from(document.querySelectorAll(
              'img[z-image-loader-url], article img, .post-content img'
            ));
            const before = player
              ? images.filter(img => !!(
                  img.compareDocumentPosition(player) &
                  Node.DOCUMENT_POSITION_FOLLOWING
                ))
              : images;
            const image = before.length ? before[before.length - 1] : null;
            return image
              ? (image.getAttribute('z-image-loader-url') ||
                  image.currentSrc || image.src || '')
              : '';
          })()
        ''',
      );
      return value?.toString().replaceAll(RegExp(r'^"|"$'), '') ?? '';
    } catch (_) {
      return '';
    }
  }

  String _qualityLabel(String value) {
    final text = value.trim().toLowerCase();
    final direct = RegExp(r'(\d{3,4})p').firstMatch(text)?.group(1);
    if (direct != null) {
      return '${_normalizedVideoHeight(int.tryParse(direct)) ?? direct}p';
    }
    final resolution =
        RegExp(r'\d{3,4}\s*[x×]\s*(\d{3,4})').firstMatch(text)?.group(1);
    if (resolution != null) return '${resolution}p';
    final number = _normalizedVideoHeight(int.tryParse(text));
    return number != null && number >= 144 ? '${number}p' : '未知';
  }

  Future<SnifferPageContext> _snifferContext() async {
    return SnifferPageContext(
      pageUrl: currentUrl,
      pageTitle: pageTitle,
      userAgent: userAgent,
      cookie: currentCookie,
    );
  }

  Future<void> _refreshCurrentCookie() async {
    final value = await _cookiesFor(currentUrl);
    if (!mounted) return;
    currentCookie = value;
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
      case 'smartParse':
        _openSmartParsePage();
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

  void _openSmartParsePage() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (routeContext) => _SmartParsePage(
          onBack: () => Navigator.of(routeContext).pop(),
          onParse: _parseStandaloneUrl,
          onShowResources: _showStandaloneResources,
          history: parseHistory,
        ),
      ),
    );
  }

  Future<List<VideoResource>> _parseStandaloneUrl(String value) async {
    final url = _normalize(value);
    try {
      final staticResources = await sniffer
          .parsePage(url, userAgent: userAgent)
          .timeout(const Duration(seconds: 7));
      final playable = staticResources
          .where((resource) => resource.isPlayable && !resource.isAdSuspect)
          .toList(growable: false);
      if (playable.isNotEmpty) {
        return _collapseVideoQualities(playable);
      }
    } catch (error) {
      debugPrint('[browser] static standalone parse fallback: $error');
    }
    return _parseWithHeadlessWebView(url);
  }

  Future<void> _showStandaloneResources(
    List<VideoResource> resources,
  ) async {
    if (resources.isEmpty || !mounted) return;
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
    await _showDownloadPicker(title: resources.first.title);
  }

  Future<List<VideoResource>> _parseWithHeadlessWebView(String url) async {
    final completer = Completer<List<VideoResource>>();
    HeadlessInAppWebView? headless;
    var processing = false;
    final accumulated = <VideoResource>[];

    Future<void> finish(List<VideoResource> value) async {
      if (completer.isCompleted) return;
      completer.complete(value);
      await headless?.dispose();
    }

    void startProcessing(
      InAppWebViewController web,
      WebUri? loadedUrl,
    ) {
      if (processing || completer.isCompleted) return;
      processing = true;
      unawaited(() async {
        try {
          // Start from navigation rather than waiting for onLoadStop. Ad-heavy
          // pages often keep requests alive indefinitely and never become idle.
          for (var attempt = 0; attempt < 8; attempt++) {
            await Future<void>.delayed(
              Duration(milliseconds: attempt == 0 ? 500 : 650),
            );
            if (completer.isCompleted) return;
            final current = (await web.getUrl())?.toString();
            final actualUrl = current ?? loadedUrl?.toString() ?? url;
            final candidates = <VideoResource>[
              ...await _headlessPlayerResources(web, actualUrl),
            ];
            // Perform the more expensive full-HTML scan once, after player
            // scripts have had time to populate their configuration.
            if (attempt == 3 || (attempt == 7 && candidates.isEmpty)) {
              final html = await web.evaluateJavascript(
                source: 'document.documentElement.outerHTML',
              );
              candidates.addAll(
                sniffer.scanHtml(
                  html?.toString() ?? '',
                  Uri.parse(actualUrl),
                  source: 'headless-dom',
                ),
              );
            }
            accumulated.addAll(
              candidates.where(
                (resource) =>
                    resource.isPlayable &&
                    !resource.isAdSuspect &&
                    !resource.isFragment,
              ),
            );
            final collapsed = _collapseVideoQualities(accumulated);
            if (collapsed.any(
                  (resource) =>
                      resource.source.contains('media-definition'),
                ) ||
                (attempt >= 3 && collapsed.isNotEmpty)) {
              await finish(collapsed);
              return;
            }
          }
          await finish(_collapseVideoQualities(accumulated));
        } catch (error) {
          debugPrint('[browser] headless scan failed: $error');
          await finish(_collapseVideoQualities(accumulated));
        }
      }());
    }

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
      ),
      onLoadStart: startProcessing,
      onLoadStop: startProcessing,
      onReceivedError: (_, request, __) {
        if (request.isForMainFrame == true) {
          unawaited(finish(const []));
        }
      },
    );
    try {
      await headless.run();
    } catch (error) {
      await finish(const []);
    }
    return completer.future.timeout(
      const Duration(seconds: 14),
      onTimeout: () {
        unawaited(headless?.dispose());
        return const [];
      },
    );
  }

  Future<List<VideoResource>> _headlessPlayerResources(
    InAppWebViewController web,
    String pageUrl,
  ) async {
    try {
      final payload = await web.evaluateJavascript(source: _scanScript);
      final decoded = payload is String ? jsonDecode(payload) : payload;
      if (decoded is! List) return const [];
      final fallbackPoster = (await web.evaluateJavascript(
            source: '''
              document.querySelector('video')?.poster ||
              document.querySelector(
                'meta[property="og:image"],meta[name="twitter:image"]'
              )?.content || ''
            ''',
          ))
              ?.toString()
              .replaceAll(RegExp(r'^"|"$'), '') ??
          '';
      final resources = <VideoResource>[];
      for (final raw in decoded.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final durationSeconds =
            double.tryParse('${item['duration'] ?? 0}') ?? 0;
        for (final url in [
          item['url']?.toString() ?? '',
          ...((item['sources'] as List?) ?? const []).map((value) => '$value'),
        ]) {
          final resource = sniffer.resourceFromUrl(
            url,
            pageTitle: item['title']?.toString() ?? pageTitle,
            pageUrl: pageUrl,
            source: item['source']?.toString() ?? 'headless-player',
            quality: _qualityLabel(item['quality']?.toString() ?? ''),
            duration: durationSeconds > 0
                ? Duration(
                    milliseconds: (durationSeconds * 1000).round(),
                  )
                : Duration.zero,
            thumbnailUrl: item['poster']?.toString().isNotEmpty == true
                ? item['poster'].toString()
                : fallbackPoster,
            allowUnknown: true,
          );
          if (resource != null) resources.add(resource);
        }
      }
      return resources;
    } catch (_) {
      return const [];
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
    if (browserDataLoaded) unawaited(_saveBrowserData());
    if (notify && mounted) setState(() {});
  }

  Future<void> _showBrowserTabs() async {
    if (browserTabsSheetOpen || !mounted) return;
    browserTabsSheetOpen = true;
    try {
      browserTabs[activeBrowserTab].thumbnail =
          await controller?.takeScreenshot();
    } catch (_) {}
    if (!mounted) {
      browserTabsSheetOpen = false;
      return;
    }
    try {
      await showModalBottomSheet<void>(
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
                        onPressed: creatingBrowserTab
                            ? null
                            : () {
                                creatingBrowserTab = true;
                                Navigator.pop(sheetContext);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  _newBrowserTab();
                                  creatingBrowserTab = false;
                                });
                              },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: browserTabs.length,
                    itemBuilder: (context, index) {
                      final tab = browserTabs[index];
                      return GestureDetector(
                        key: ValueKey(tab.id),
                        onTap: () {
                          _activateBrowserTab(index);
                          Navigator.pop(sheetContext);
                        },
                        onLongPress: tab.url.startsWith('http')
                            ? () {
                                Clipboard.setData(
                                  ClipboardData(text: tab.url),
                                );
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(content: Text('网址已复制')),
                                );
                              }
                            : null,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            side: index == activeBrowserTab
                                ? BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    width: 2,
                                  )
                                : BorderSide.none,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: tab.thumbnail == null
                                    ? Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        child: const Icon(
                                          Icons.language_rounded,
                                          size: 42,
                                        ),
                                      )
                                    : Image.memory(
                                        tab.thumbnail!,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    24,
                                    12,
                                    12,
                                  ),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black87,
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    tab.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 6,
                                top: 6,
                                child: IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: '关闭标签页',
                                  onPressed: browserTabs.length > 1
                                      ? () {
                                          _closeBrowserTab(index);
                                          setSheetState(() {});
                                        }
                                      : null,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                            ],
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
    } finally {
      browserTabsSheetOpen = false;
      creatingBrowserTab = false;
    }
  }

  void _newBrowserTab() {
    setState(() {
      browserTabs.add(
        _BrowserTabData(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: '新窗口',
          url: 'about:blank',
          keepAlive: InAppWebViewKeepAlive(),
        ),
      );
      activeBrowserTab = browserTabs.length - 1;
      showStartPage = true;
      currentUrl = 'about:blank';
      pageTitle = '新窗口';
      addressController.clear();
      captured.clear();
    });
    if (browserDataLoaded) unawaited(_saveBrowserData());
  }

  void _activateBrowserTab(int index) {
    if (index < 0 || index >= browserTabs.length) return;
    final previousController = controller;
    final tab = browserTabs[index];
    if (index != activeBrowserTab && previousController != null) {
      unawaited(_pauseWebMedia(previousController));
    }
    setState(() {
      activeBrowserTab = index;
      currentUrl = tab.url;
      pageTitle = tab.title;
      showStartPage = tab.url == 'about:blank';
      addressController.text = showStartPage ? '' : tab.url;
      captured.clear();
      controller = tabControllers[tab.id];
    });
    if (browserDataLoaded) unawaited(_saveBrowserData());
  }

  void _closeBrowserTab(int index) {
    if (browserTabs.length <= 1) return;
    final closed = browserTabs.removeAt(index);
    tabControllers.remove(closed.id);
    recentlyClosedTabs.insert(0, closed);
    if (recentlyClosedTabs.length > 10) recentlyClosedTabs.removeLast();
    activeBrowserTab =
        activeBrowserTab.clamp(0, browserTabs.length - 1).toInt();
    _activateBrowserTab(activeBrowserTab);
    if (browserDataLoaded) unawaited(_saveBrowserData());
  }

  void _restoreRecentlyClosedTab() {
    if (recentlyClosedTabs.isEmpty) return;
    final tab = recentlyClosedTabs.removeAt(0);
    setState(() {
      browserTabs.add(tab);
      activeBrowserTab = browserTabs.length - 1;
    });
    _activateBrowserTab(activeBrowserTab);
  }

  bool _shouldBlockRequest(String value) {
    if (!adBlockEnabled) return false;
    final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    const adHosts = [
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'adnxs.com',
      'popads.net',
      'popcash.net',
    ];
    const trackerHosts = [
      'google-analytics.com',
      'googletagmanager.com',
      'connect.facebook.net',
      'analytics.twitter.com',
    ];
    bool matchesHost(String blocked) =>
        host == blocked || host.endsWith('.$blocked');
    return adHosts.any(matchesHost) ||
        (blockTrackers && trackerHosts.any(matchesHost));
  }

  bool _looksLikeMediaRequest(String value) {
    final lower = value.toLowerCase();
    return RegExp(
      r'\.(m3u8|mp4|m4v|mov|webm|mpd)(?:[?#]|$)',
    ).hasMatch(lower);
  }

  bool _shouldBlockNavigation(String value) {
    if (!blockPopups || value.isEmpty) return false;
    return _shouldBlockRequest(value) ||
        value.startsWith('intent:') ||
        value.startsWith('itms-services:');
  }

  void _showHelp() {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('使用方法'),
        content: const Text(
          '\n打开网页并播放视频，工具栏会显示检测结果。未检测到时，先播放几秒再重新解析。',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
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
      if (data.openTabs.isNotEmpty) {
        browserTabs
          ..clear()
          ..addAll(
            data.openTabs.asMap().entries.map(
              (entry) => _BrowserTabData(
                id: '${DateTime.now().microsecondsSinceEpoch}-${entry.key}',
                title: entry.value.title.isEmpty ? '网页' : entry.value.title,
                url: entry.value.url,
                keepAlive: InAppWebViewKeepAlive(),
              ),
            ),
          );
        activeBrowserTab =
            data.activeTab.clamp(0, browserTabs.length - 1).toInt();
        final restored = browserTabs[activeBrowserTab];
        currentUrl = restored.url;
        pageTitle = restored.title;
        showStartPage = restored.url == 'about:blank';
        addressController.text = showStartPage ? '' : restored.url;
      }
      browserDataLoaded = true;
    });
  }

  Future<void> _saveBrowserData() => browserDataStore.save(
        history: history,
        bookmarks: bookmarks,
        openTabs: browserTabs
            .map(
              (tab) => BrowserPageRecord(
                url: tab.url,
                title: tab.title,
                updatedAt: DateTime.now(),
              ),
            )
            .toList(growable: false),
        activeTab: activeBrowserTab,
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
  const push = (url, source, media, quality = '') => {
    if (!url) return;
    out.push({
      url,
      source,
      title,
      duration: media && Number.isFinite(media.duration) ? media.duration : 0,
      poster: media ? (media.poster || '') : '',
      current: !!(media && (!media.paused || media.currentTime > 0)),
      quality,
      sources: media ? Array.from(media.querySelectorAll('source')).map(s => s.src || s.getAttribute('src') || '').filter(Boolean) : []
    });
  };
  document.querySelectorAll('video,audio').forEach(v => {
    push(v.currentSrc || v.src, 'video', v);
    Array.from(v.querySelectorAll('source')).forEach(s => push(s.src || s.getAttribute('src'), 'source', v));
  });
  document.querySelectorAll('[data-config]').forEach(node => {
    try {
      const config = JSON.parse(node.getAttribute('data-config') || '{}');
      const video = config && config.video;
      if (!video || !video.url) return;
      const media = node.querySelector('video');
      const precedingImages = Array.from(document.querySelectorAll('img')).filter(
        img => !!(img.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING)
      );
      const preceding = precedingImages.length ? precedingImages[precedingImages.length - 1] : null;
      out.push({
        url: video.url,
        source: 'player-config',
        title: node.getAttribute('data-video-title') || title,
        duration: 0,
        poster: (media && media.poster) || video.pic || video.poster ||
          (preceding && (preceding.getAttribute('z-image-loader-url') || preceding.currentSrc || preceding.src)) || '',
        current: false,
        sources: []
      });
    } catch (_) {}
  });
  Object.keys(window).filter(key => /flashvars|player/i.test(key)).forEach(key => {
    try {
      const config = window[key];
      const definitions = config && config.mediaDefinitions;
      if (!Array.isArray(definitions)) return;
      const poster = config.image_url || config.imageUrl || config.poster || '';
      const duration = Number(config.video_duration || config.duration || 0);
      definitions.forEach(definition => {
        const url = definition && (definition.videoUrl || definition.video_url);
        if (!url) return;
        out.push({
          url,
          source: 'player-media-definition',
          title: config.video_title || title,
          duration: Number.isFinite(duration) ? duration : 0,
          poster,
          current: false,
          quality: definition.quality || definition.qualityText || '',
          sources: []
        });
      });
    } catch (_) {}
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
  const post = (url, source, media, quality = '', posterOverride = '', durationOverride = 0) => {
    try {
      if (!url || (!likely(url) && source !== 'player-media-definition')) return;
      window.flutter_inappwebview.callHandler('VideoDownloaderCapture', {
        url: new URL(url, location.href).href,
        source,
        title: title(),
        duration: media && Number.isFinite(media.duration) ? media.duration : durationOverride,
        poster: posterOverride || (media ? (media.poster || '') : ''),
        current: !!(media && (!media.paused || media.currentTime > 0)),
        quality,
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
  document.querySelectorAll('[data-config]').forEach(node => {
    try {
      const config = JSON.parse(node.getAttribute('data-config') || '{}');
      if (config && config.video && config.video.url) {
        post(config.video.url, 'player-config', null);
      }
    } catch (_) {}
  });
  const postPlayerDefinitions = () => {
    Object.keys(window).filter(key => /flashvars|player/i.test(key)).forEach(key => {
      try {
        const config = window[key];
        const definitions = config && config.mediaDefinitions;
        if (!Array.isArray(definitions)) return;
        const poster = config.image_url || config.imageUrl || config.poster || '';
        const duration = Number(config.video_duration || config.duration || 0);
        definitions.forEach(definition => {
          if (!definition) return;
          post(
            definition.videoUrl || definition.video_url,
            'player-media-definition',
            null,
            definition.quality || definition.qualityText || '',
            poster,
            Number.isFinite(duration) ? duration : 0
          );
        });
      } catch (_) {}
    });
  };
  postPlayerDefinitions();
  setTimeout(postPlayerDefinitions, 1200);
  const pendingRoots = new Set();
  let scanScheduled = false;
  const flushAddedMedia = () => {
    scanScheduled = false;
    pendingRoots.forEach(n => {
      if (!n.querySelectorAll) return;
      if (n.tagName === 'VIDEO' || n.tagName === 'AUDIO') bind(n);
      n.querySelectorAll('video,audio').forEach(bind);
    });
    pendingRoots.clear();
  };
  new MutationObserver(ms => {
    ms.forEach(m => m.addedNodes.forEach(n => pendingRoots.add(n)));
    if (!scanScheduled) {
      scanScheduled = true;
      requestAnimationFrame(flushAddedMedia);
    }
  }).observe(document.documentElement, {childList:true, subtree:true});
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

  static const _adBlockSelector = '''
    .adsbygoogle,
    [data-ad-client],
    [data-ad-slot],
    [data-ad_slot_key],
    [data-ad_type],
    [data-event="ad_click"],
    [data-page_key="float_ads"],
    .horizontal-banner,
    .dw-activity-banner,
    .adspop,
    #adFloat,
    #aiFloat,
    .xqbj-component-adfloat,
    .xqbj-component-aifloat,
    .launchapp-btn-container,
    iframe[src*="doubleclick.net"],
    iframe[src*="googlesyndication.com"]
  ''';

  static const _adBlockScript = r'''
(() => {
  if (!document.getElementById('__vidsniffer_adblock')) {
    const style = document.createElement('style');
    style.id = '__vidsniffer_adblock';
    style.textContent = `
      .adsbygoogle,
      [data-ad-client],
      [data-ad-slot],
      [data-ad_slot_key],
      [data-ad_type],
      [data-event="ad_click"],
      [data-page_key="float_ads"],
      .horizontal-banner,
      .dw-activity-banner,
      .adspop,
      #adFloat,
      #aiFloat,
      .xqbj-component-adfloat,
      .xqbj-component-aifloat,
      .launchapp-btn-container,
      iframe[src*="doubleclick.net"],
      iframe[src*="googlesyndication.com"] {
        display: none !important;
        visibility: hidden !important;
        min-height: 0 !important;
        height: 0 !important;
        margin: 0 !important;
        padding: 0 !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }
  window.open = () => null;
})();
''';
}

class _BrowserTabData {
  _BrowserTabData({
    required this.id,
    required this.title,
    required this.url,
    required this.keepAlive,
    this.thumbnail,
  });

  final String id;
  final String title;
  final String url;
  final InAppWebViewKeepAlive keepAlive;
  Uint8List? thumbnail;

  _BrowserTabData copyWith({String? title, String? url}) {
    return _BrowserTabData(
      id: id,
      title: title ?? this.title,
      url: url ?? this.url,
      keepAlive: keepAlive,
      thumbnail: thumbnail,
    );
  }
}

class _StartPage extends StatefulWidget {
  const _StartPage({
    required this.onOpen,
    required this.tabs,
    required this.activeTab,
    required this.recentlyClosed,
    required this.onActivateTab,
    required this.onCloseTab,
    required this.onNewTab,
    required this.onRestoreRecent,
  });

  final ValueChanged<String> onOpen;
  final List<_BrowserTabData> tabs;
  final int activeTab;
  final List<_BrowserTabData> recentlyClosed;
  final ValueChanged<int> onActivateTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback onRestoreRecent;

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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 42),
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText: '搜索或输入网址',
            prefixIcon: const Icon(CupertinoIcons.search),
            suffixIcon: IconButton(
              tooltip: '打开',
              icon: const Icon(CupertinoIcons.arrow_right_circle_fill),
              onPressed: () => widget.onOpen(controller.text),
            ),
          ),
          onSubmitted: widget.onOpen,
        ),
        const SizedBox(height: 34),
        Row(
          children: [
            const Expanded(
              child: Text(
                '标签页',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: const Size(44, 44),
              onPressed: widget.onNewTab,
              child: const Text('新建'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < widget.tabs.length; index++) ...[
          _BrowserHomeTabCard(
            tab: widget.tabs[index],
            selected: index == widget.activeTab,
            canClose: widget.tabs.length > 1,
            onTap: () => widget.onActivateTab(index),
            onClose: () => widget.onCloseTab(index),
          ),
          if (index < widget.tabs.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 16),
        _RecentlyClosedCard(
          tab: widget.recentlyClosed.isEmpty
              ? null
              : widget.recentlyClosed.first,
          onTap: widget.recentlyClosed.isEmpty
              ? null
              : widget.onRestoreRecent,
        ),
      ],
    );
  }
}

class _TabCountButton extends StatelessWidget {
  const _TabCountButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '标签页，共 $count 个',
      child: IconButton(
        tooltip: '标签页',
        onPressed: onTap,
        icon: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(CupertinoIcons.square_on_square, size: 25),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserHomeTabCard extends StatelessWidget {
  const _BrowserHomeTabCard({
    required this.tab,
    required this.selected,
    required this.canClose,
    required this.onTap,
    required this.onClose,
  });

  final _BrowserTabData tab;
  final bool selected;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(tab.url)?.host;
    final subtitle = tab.url == 'about:blank'
        ? '搜索或输入网址'
        : (host == null || host.isEmpty ? tab.url : host);
    final title = tab.url == 'about:blank'
        ? '新标签页'
        : (tab.title.trim().isEmpty ? '上次浏览' : tab.title);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        side: selected
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 106,
                  height: 78,
                  child: tab.thumbnail == null
                      ? _TabPreviewPlaceholder(active: selected)
                      : Image.memory(tab.thumbnail!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: canClose ? '关闭标签页' : '至少保留一个标签页',
                onPressed: canClose ? onClose : null,
                icon: const Icon(CupertinoIcons.xmark, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabPreviewPlaceholder extends StatelessWidget {
  const _TabPreviewPlaceholder({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var index = 0; index < 3; index++) ...[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: index == 0 && active
                          ? scheme.primary
                          : scheme.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (index < 2) const SizedBox(width: 4),
                ],
                const SizedBox(width: 7),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              height: 25,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(child: _previewLine(context)),
                const SizedBox(width: 6),
                Expanded(child: _previewLine(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewLine(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _RecentlyClosedCard extends StatelessWidget {
  const _RecentlyClosedCard({required this.tab, required this.onTap});

  final _BrowserTabData? tab;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.clock_solid,
                color: scheme.onSurfaceVariant,
                size: 31,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '最近关闭',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tab == null ? '暂无最近关闭的标签页' : tab!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                color: onTap == null
                    ? scheme.outlineVariant
                    : scheme.onSurfaceVariant,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartParsePage extends StatefulWidget {
  const _SmartParsePage({
    required this.onBack,
    required this.onParse,
    required this.onShowResources,
    required this.history,
  });

  final VoidCallback onBack;
  final Future<List<VideoResource>> Function(String) onParse;
  final Future<void> Function(List<VideoResource>) onShowResources;
  final List<_ParseHistoryEntry> history;

  @override
  State<_SmartParsePage> createState() => _SmartParsePageState();
}

class _SmartParsePageState extends State<_SmartParsePage> {
  final urlController = TextEditingController();
  final scrollController = ScrollController();
  List<VideoResource> resources = const [];
  bool parsing = false;
  bool showAllHistory = false;
  String notice = '';

  @override
  void dispose() {
    urlController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final value = data?.text?.trim() ?? '';
    if (value.isEmpty) {
      setState(() => notice = '剪贴板中没有网址');
      return;
    }
    setState(() {
      urlController.text = value;
      urlController.selection = TextSelection.collapsed(offset: value.length);
      notice = '';
    });
  }

  Future<void> _parse() async {
    final value = urlController.text.trim();
    if (value.isEmpty || parsing) {
      if (value.isEmpty) setState(() => notice = '请先输入视频页面链接');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      parsing = true;
      notice = '';
      resources = const [];
    });
    try {
      final result = await widget.onParse(value);
      if (!mounted) return;
      setState(() {
        parsing = false;
        resources = result;
        notice = result.isEmpty ? '未解析到视频，请检查链接后重试' : '';
        if (result.isNotEmpty) {
          widget.history.removeWhere((entry) => entry.url == value);
          widget.history.insert(
            0,
            _ParseHistoryEntry(
              url: value,
              title: result.first.title,
              resources: result,
            ),
          );
          if (widget.history.length > 10) widget.history.removeLast();
        }
      });
      if (result.isNotEmpty) {
        await widget.onShowResources(result);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        parsing = false;
        notice = '解析失败，请检查网络或链接后重试';
      });
      debugPrint('[browser] standalone parse failed: $error');
    }
  }

  void _scrollToRecent() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleHistory = showAllHistory
        ? widget.history
        : widget.history.take(2).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          tooltip: '返回浏览器',
          onPressed: widget.onBack,
          icon: const Icon(CupertinoIcons.back),
        ),
        title: const Text('智能解析'),
        actions: [
          IconButton(
            tooltip: '最近解析',
            onPressed: _scrollToRecent,
            icon: const Icon(CupertinoIcons.clock),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 112),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '粘贴视频页面链接',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'https://example.com/video',
                    suffixIcon: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: _paste,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.doc_on_clipboard, size: 19),
                          SizedBox(width: 5),
                          Text('粘贴'),
                        ],
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _parse(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: parsing ? null : _parse,
                    icon: parsing
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(CupertinoIcons.link),
                    label: Text(parsing ? '正在解析' : '开始解析'),
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.shield,
                      color: scheme.onSurfaceVariant,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '链接仅用于本机解析，不会上传',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (notice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              notice,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 28),
          const _ParseSectionTitle(title: '解析结果'),
          const SizedBox(height: 12),
          _ParseResultCard(
            parsing: parsing,
            resources: resources,
            onTap: resources.isEmpty
                ? null
                : () => widget.onShowResources(resources),
          ),
          const SizedBox(height: 28),
          _ParseSectionTitle(
            title: '最近解析',
            action: widget.history.length > 2
                ? (showAllHistory ? '收起' : '全部')
                : null,
            onAction: () =>
                setState(() => showAllHistory = !showAllHistory),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.history.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '暂无最近解析',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : Column(
                    children: [
                      for (var index = 0;
                          index < visibleHistory.length;
                          index++) ...[
                        _ParseHistoryTile(
                          entry: visibleHistory[index],
                          onTap: () => widget.onShowResources(
                            visibleHistory[index].resources,
                          ),
                        ),
                        if (index < visibleHistory.length - 1)
                          Divider(
                            height: 0.5,
                            thickness: 0.5,
                            indent: 92,
                            color: scheme.outlineVariant,
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ParseSectionTitle extends StatelessWidget {
  const _ParseSectionTitle({
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (action != null)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(44, 44),
            onPressed: onAction,
            child: Text(
              action!,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _ParseResultCard extends StatelessWidget {
  const _ParseResultCard({
    required this.parsing,
    required this.resources,
    required this.onTap,
  });

  final bool parsing;
  final List<VideoResource> resources;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (resources.isNotEmpty) {
      final resource = resources.first;
      return Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    CupertinoIcons.play_rectangle_fill,
                    color: scheme.primary,
                    size: 29,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resource.title.trim().isEmpty
                            ? '已解析视频'
                            : resource.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${resources.length} 个可下载资源 · ${_resourceMetadata(resource)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_forward, size: 17),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: parsing
                  ? CircularProgressIndicator(color: scheme.primary)
                  : Icon(
                      CupertinoIcons.link,
                      color: scheme.primary,
                      size: 38,
                    ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            parsing ? '正在解析' : '等待解析',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            parsing
                ? '正在读取网页中的视频信息…'
                : '粘贴视频页面链接后，清晰度、时长和大小会显示在这里',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParseHistoryEntry {
  const _ParseHistoryEntry({
    required this.url,
    required this.title,
    required this.resources,
  });

  final String url;
  final String title;
  final List<VideoResource> resources;
}

class _ParseHistoryTile extends StatelessWidget {
  const _ParseHistoryTile({required this.entry, required this.onTap});

  final _ParseHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resource = entry.resources.first;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      leading: Container(
        width: 62,
        height: 52,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          CupertinoIcons.play_fill,
          color: scheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        entry.title.trim().isEmpty ? '已解析视频' : entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _resourceMetadata(resource),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(CupertinoIcons.chevron_forward, size: 17),
    );
  }
}

String _resourceMetadata(VideoResource resource) {
  final quality = _displayQuality(resource);
  final size = resource.size.trim().isEmpty ? '大小未知' : resource.size;
  final duration = resource.duration > Duration.zero
      ? _formatVideoDuration(resource.duration)
      : '时长未知';
  return '$quality · $duration · $size';
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
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 38),
        prefixIcon: Icon(
          Icons.lock_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        hintText: '搜索或输入网址',
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _DownloadPicker extends StatefulWidget {
  const _DownloadPicker({
    required this.title,
    required this.resources,
    required this.coverUrl,
    required this.loadCoverBytes,
    required this.onProbe,
    required this.onDownload,
  });

  final String title;
  final List<VideoResource> resources;
  final String coverUrl;
  final Future<Uint8List?> Function(String) loadCoverBytes;
  final Future<List<VideoResource>> Function(VideoResource) onProbe;
  final FutureOr<void> Function(VideoResource) onDownload;

  @override
  State<_DownloadPicker> createState() => _DownloadPickerState();
}

class _DownloadPickerState extends State<_DownloadPicker> {
  late List<VideoResource> resources =
      _collapseVideoQualities(widget.resources);
  late VideoResource selected = resources.first;
  Uint8List? coverBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCover());
    unawaited(_enrichResources());
  }

  Future<void> _loadCover() async {
    if (widget.coverUrl.isEmpty) return;
    final bytes = await widget.loadCoverBytes(widget.coverUrl);
    if (mounted && bytes != null) setState(() => coverBytes = bytes);
  }

  Future<void> _enrichResources() async {
    final originals = List<VideoResource>.from(resources);
    final discovered = <VideoResource>[];
    for (final original in originals) {
      try {
        final probed = await widget.onProbe(original);
        discovered.addAll(probed.isEmpty ? [original] : probed);
      } catch (_) {
        discovered.add(original);
      }
    }
    if (!mounted || discovered.isEmpty) return;
    final selectedQuality = _displayQuality(selected);
    final enriched = _collapseVideoQualities(discovered);
    setState(() {
      resources = enriched;
      selected = enriched.firstWhere(
        (resource) => _displayQuality(resource) == selectedQuality,
        orElse: () => enriched.first,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择下载清晰度',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '选择一个视频开始下载',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff747986),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.52,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final resource in resources)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _VideoChoiceTile(
                          resource: resource,
                          coverBytes: coverBytes,
                          selected: resource.url == selected.url,
                          fallbackTitle: widget.title,
                          onTap: () => setState(() => selected = resource),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
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

class _VideoChoiceTile extends StatelessWidget {
  const _VideoChoiceTile({
    required this.resource,
    required this.coverBytes,
    required this.selected,
    required this.fallbackTitle,
    required this.onTap,
  });

  final VideoResource resource;
  final Uint8List? coverBytes;
  final bool selected;
  final String fallbackTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title =
        resource.title.trim().isEmpty ? fallbackTitle : resource.title.trim();
    final quality = _displayQuality(resource);
    final metadata = [
      quality.trim().isEmpty ? '分辨率未知' : quality,
      resource.size.trim().isEmpty ? '大小未知' : resource.size,
      resource.duration > Duration.zero
          ? _formatVideoDuration(resource.duration)
          : '时长未知',
    ].join(' · ');
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.09)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 100,
                  height: 72,
                  child: coverBytes != null
                      ? Image.memory(coverBytes!, fit: BoxFit.cover)
                      : resource.thumbnailUrl.trim().isEmpty
                      ? ColoredBox(color: scheme.surfaceContainerHighest)
                      : Image.network(
                          resource.thumbnailUrl,
                          fit: BoxFit.cover,
                          headers: {
                            if (resource.pageUrl.isNotEmpty)
                              'Referer': resource.pageUrl,
                            if (resource.userAgent.isNotEmpty)
                              'User-Agent': resource.userAgent,
                          },
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: const Icon(
                              Icons.movie_creation_outlined,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        metadata,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
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
    return '$hours小时$minutes分${seconds.toString().padLeft(2, '0')}秒';
  }
  return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
}

String _displayQuality(VideoResource resource) {
  final raw = resource.quality.trim();
  final p = RegExp(r'(\d{3,4})p', caseSensitive: false)
      .firstMatch(raw)
      ?.group(1);
  if (p != null) {
    return '${_normalizedVideoHeight(int.tryParse(p)) ?? p}p';
  }
  final resolution = RegExp(r'\d{3,4}\s*[x×]\s*(\d{3,4})')
      .firstMatch(raw)
      ?.group(1);
  if (resolution != null) return '${resolution}p';
  final number = _normalizedVideoHeight(int.tryParse(raw));
  if (number != null && number >= 144) return '${number}p';
  return raw == '未知' || raw.isEmpty ? resource.displayFormat : raw;
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

List<VideoResource> _collapseVideoQualities(List<VideoResource> resources) {
  final selected = <String, VideoResource>{};
  for (final resource in resources) {
    final quality = _displayQuality(resource);
    final height = RegExp(r'(\d{3,4})p', caseSensitive: false)
        .firstMatch(quality)
        ?.group(1);
    final key = height == null ? resource.normalizedUrl : 'height:$height';
    final current = selected[key];
    if (current == null ||
        _downloadChoiceScore(resource) > _downloadChoiceScore(current)) {
      selected[key] = resource.copyWith(
        quality: height == null ? resource.quality : '${height}p',
      );
    }
  }
  final collapsed = selected.values.toList(growable: false);
  collapsed.sort((a, b) {
    int height(VideoResource resource) =>
        int.tryParse(
          RegExp(r'(\d{3,4})p', caseSensitive: false)
                  .firstMatch(_displayQuality(resource))
                  ?.group(1) ??
              '',
        ) ??
        -1;

    final qualityOrder = height(b).compareTo(height(a));
    if (qualityOrder != 0) return qualityOrder;
    return _downloadChoiceScore(b).compareTo(_downloadChoiceScore(a));
  });
  return collapsed;
}

int _downloadChoiceScore(VideoResource resource) {
  var score = 0;
  if (resource.type == VideoResourceType.mp4) score += 500;
  if (resource.type == VideoResourceType.hls) score += 300;
  if (resource.source.toLowerCase().contains('h264')) score += 120;
  if (resource.source.toLowerCase().contains('av1')) score -= 30;
  if (resource.size != '未知' && resource.size.trim().isNotEmpty) score += 250;
  if (resource.duration > Duration.zero) score += 100;
  if (resource.thumbnailUrl.isNotEmpty) score += 20;
  if (resource.source.contains('media-definition')) score += 50;
  return score;
}

class _BrowserBottomControls extends StatelessWidget {
  const _BrowserBottomControls({
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.tabCount,
    required this.onTabs,
    required this.videoCount,
    required this.detectingVideo,
    required this.notice,
    required this.onDetectVideo,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome;
  final int tabCount;
  final VoidCallback onTabs;
  final int videoCount;
  final bool detectingVideo;
  final String notice;
  final VoidCallback onDetectVideo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
          _BrowserToolSlot(
            tooltip: '后退',
            onPressed: canGoBack ? onBack : null,
            icon: const Icon(CupertinoIcons.back),
          ),
          _BrowserToolSlot(
            tooltip: '主页',
            onPressed: onHome,
            icon: const Icon(CupertinoIcons.house_fill),
          ),
          _BrowserToolSlot(
            tooltip: '前进',
            onPressed: canGoForward ? onForward : null,
            icon: const Icon(CupertinoIcons.forward),
          ),
          _BrowserToolSlot(
            tooltip: '标签页',
            onPressed: onTabs,
            emphasized: true,
            icon: _TabCountBadge(count: tabCount),
          ),
          _BrowserToolSlot(
            tooltip: notice.isNotEmpty
                ? notice
                : videoCount > 0
                    ? '发现 $videoCount 个视频'
                    : '检测视频',
            onPressed: detectingVideo ? null : onDetectVideo,
            emphasized: videoCount > 0,
            icon: detectingVideo
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: videoCount > 0,
                    label: Text('$videoCount'),
                    child: Icon(
                      videoCount > 0
                          ? CupertinoIcons.play_rectangle_fill
                          : notice.isNotEmpty
                              ? CupertinoIcons.info_circle
                              : CupertinoIcons.play_rectangle,
                      color: notice.isNotEmpty ? scheme.tertiary : null,
                    ),
                  ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserToolSlot extends StatelessWidget {
  const _BrowserToolSlot({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.emphasized = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Center(
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: emphasized
                ? scheme.primary.withValues(alpha: 0.09)
                : Colors.transparent,
            foregroundColor: emphasized ? scheme.primary : null,
          ),
          icon: icon,
        ),
      ),
    );
  }
}

PopupMenuItem<String> _browserMenuItem(
  String value,
  IconData icon,
  String label,
) {
  return PopupMenuItem<String>(
    value: value,
    height: 50,
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: AppTheme.blue),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
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
      width: 27,
      height: 27,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(width: 1.8),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            const AppleSectionHeader(title: '浏览器设置'),
            AppleListGroup(
              footer: '过滤在页面加载前启用；个别网站可能需要关闭过滤后重新载入。',
              children: [
                ListTile(
                  leading: const AppleIconTile(
                    icon: CupertinoIcons.shield_fill,
                    color: AppTheme.blue,
                  ),
                  title: const Text('广告拦截'),
                  subtitle: const Text('横幅、广告脚本与常见广告框架'),
                  trailing: CupertinoSwitch(
                    value: adBlockEnabled,
                    activeTrackColor: AppTheme.green,
                    onChanged: onAdBlockChanged,
                  ),
                  onTap: () => onAdBlockChanged(!adBlockEnabled),
                ),
                ListTile(
                  leading: const AppleIconTile(
                    icon: CupertinoIcons.rectangle_on_rectangle_angled,
                    color: AppTheme.orange,
                  ),
                  title: const Text('阻止弹窗与自动跳转'),
                  trailing: CupertinoSwitch(
                    value: blockPopups,
                    activeTrackColor: AppTheme.green,
                    onChanged: onPopupsChanged,
                  ),
                  onTap: () => onPopupsChanged(!blockPopups),
                ),
                ListTile(
                  enabled: adBlockEnabled,
                  leading: const AppleIconTile(
                    icon: CupertinoIcons.hand_raised_fill,
                    color: AppTheme.purple,
                  ),
                  title: const Text('隐私追踪过滤'),
                  trailing: CupertinoSwitch(
                    value: blockTrackers,
                    activeTrackColor: AppTheme.green,
                    onChanged:
                        adBlockEnabled ? onTrackersChanged : null,
                  ),
                  onTap: adBlockEnabled
                      ? () => onTrackersChanged(!blockTrackers)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const AppleListGroup(
              children: [
                AppleListTile(
                  title: '过滤模式',
                  subtitle: '基础过滤 · 去弹窗 · 去追踪',
                  icon: CupertinoIcons.slider_horizontal_3,
                  iconColor: AppTheme.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
