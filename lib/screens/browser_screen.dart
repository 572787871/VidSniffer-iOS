import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/pill_button.dart';
import 'app_state.dart';
import 'video_player_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final TextEditingController _addressController;
  late final WebViewController _webController;
  bool _autoSniff = true;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: 'https://example.com/video');
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.midnight)
      ..addJavaScriptChannel('VidSniffer', onMessageReceived: _handleSniffMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_autoSniff) {
              _injectSniffer();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://example.com/video'));
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 210),
              children: [
                const Text('浏览器嗅探', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('打开网页后自动识别视频、m3u8 与媒体分片', style: TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 18),
                GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _ToolIcon(icon: LucideIcons.arrowLeft, onTap: _webController.goBack),
                          _ToolIcon(icon: LucideIcons.arrowRight, onTap: _webController.goForward),
                          _ToolIcon(icon: LucideIcons.refreshCw, onTap: () {
                            _webController.reload();
                            _forceScan();
                          }),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _addressController,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) => _load(state),
                              decoration: const InputDecoration(
                                hintText: '输入网页地址',
                                prefixIcon: Icon(LucideIcons.lock, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(LucideIcons.radar, size: 17, color: AppTheme.electricBlue),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('自动嗅探', style: TextStyle(fontWeight: FontWeight.w800))),
                          CupertinoSwitch(
                            value: _autoSniff,
                            activeColor: AppTheme.electricBlue,
                            onChanged: (value) {
                              setState(() => _autoSniff = value);
                              if (value) {
                                _forceScan();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          height: 430,
                          color: AppTheme.panelStrong,
                          child: Stack(
                            children: [
                              GestureDetector(
                                onLongPress: _forceScan,
                                child: WebViewWidget(controller: _webController),
                              ),
                              if (state.browserLoading)
                                const Align(
                                  alignment: Alignment.topCenter,
                                  child: LinearProgressIndicator(minHeight: 4),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: state.sniffedResources.isEmpty ? 118 : 198,
              child: GestureDetector(
                onTap: _forceScan,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: [BoxShadow(color: AppTheme.electricBlue.withOpacity(0.32), blurRadius: 18, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(LucideIcons.download, color: Colors.white),
                ),
              ).animate(target: state.sniffedResources.isNotEmpty ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.08, 1.08)),
            ),
            if (state.sniffedResources.isNotEmpty)
              Positioned(
                left: 20,
                right: 20,
                bottom: 108,
                child: GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(gradient: AppTheme.accentGradient, borderRadius: BorderRadius.circular(18)),
                        child: const Icon(LucideIcons.radar, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('嗅探到视频资源', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text(
                              '${state.sniffedResources.first.title} · ${state.sniffedResources.first.quality} · ${state.sniffedResources.first.size}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 38,
                            onPressed: () => _playResource(context, state.sniffedResources.first),
                            child: const Icon(LucideIcons.play, color: Colors.white, size: 20),
                          ),
                          PillButton(
                            label: state.sniffedResources.first.isHls ? '保存' : '下载',
                            icon: LucideIcons.download,
                            compact: true,
                            onPressed: () => _queueDownload(context, state, state.sniffedResources.first),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 34,
                            onPressed: () => state.dismissSniffedResource(state.sniffedResources.first),
                            child: const Icon(Icons.close_rounded, color: AppTheme.muted, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.18, end: 0),
              ),
          ],
        );
      },
    );
  }

  void _queueDownload(BuildContext context, AppState state, VideoResource resource) {
    state.addDownload(resource);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已开始下载：${resource.quality}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.electricBlue,
      ),
    );
  }

  void _playResource(BuildContext context, VideoResource resource) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          file: LocalVideo(
            title: resource.title,
            duration: '--:--',
            size: resource.size,
            thumbnail: 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?w=600',
            sourceUrl: resource.url,
          ),
        ),
      ),
    );
  }

  Future<void> _load(AppState state) async {
    var value = _addressController.text.trim();
    if (!value.startsWith('http')) {
      value = 'https://$value';
      _addressController.text = value;
    }
    await _webController.loadRequest(Uri.parse(value));
    await state.loadBrowserUrl(value);
    if (_autoSniff) {
      await _injectSniffer();
    }
  }

  void _handleSniffMessage(JavaScriptMessage message) {
    try {
      final payload = jsonDecode(message.message);
      if (payload is! Map<String, dynamic>) {
        return;
      }
      final url = payload['url'] as String? ?? '';
      final type = payload['type'] as String? ?? 'auto';
      final quality = payload['quality'] as String? ?? (type == 'm3u8' ? 'HLS m3u8' : 'MP4 视频');
      final pageTitle = payload['title'] as String? ?? _addressController.text;
      AppStateScope.of(context).addSniffedResource(
        url: url,
        title: pageTitle,
        quality: quality,
        source: payload['source'] as String? ?? 'JS 嗅探',
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _forceScan() async {
    await _injectSniffer();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在扫描网页视频资源'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _injectSniffer() async {
    final script = _snifferScript();
    await _webController.runJavaScript(script).catchError((_) {});
  }

  String _snifferScript() => '''
(function() {
  if (!window.__vidsnifferInstalled) {
    window.__vidsnifferInstalled = true;
    window.__vidsnifferSeen = new Set();
    window.__vidsnifferTitle = function() {
      return document.title || location.hostname || '网页视频';
    };
    window.__vidsnifferPost = function(url, source) {
      try {
        if (!url || typeof url !== 'string') return;
        var absolute = new URL(url, location.href).href;
        var lower = absolute.toLowerCase();
        if (lower.indexOf('blob:') === 0 || lower.indexOf('data:') === 0 || lower.indexOf('base64') !== -1) return;
        if (lower.indexOf('analytics') !== -1 || lower.indexOf('/ads/') !== -1 || lower.indexOf('doubleclick') !== -1) return;
        if (!(lower.indexOf('.mp4') !== -1 || lower.indexOf('.m3u8') !== -1)) return;
        if (window.__vidsnifferSeen.has(absolute)) return;
        window.__vidsnifferSeen.add(absolute);
        var type = lower.indexOf('.m3u8') !== -1 ? 'm3u8' : 'mp4';
        VidSniffer.postMessage(JSON.stringify({
          type: type,
          url: absolute,
          quality: type === 'm3u8' ? 'HLS m3u8' : 'MP4 视频',
          title: window.__vidsnifferTitle(),
          source: source
        }));
      } catch (e) {}
    };
    window.__vidsnifferScanDom = function() {
      try {
        document.querySelectorAll('video, source, iframe').forEach(function(node) {
          ['src', 'currentSrc', 'data-src'].forEach(function(key) {
            var value = node[key] || node.getAttribute && node.getAttribute(key);
            window.__vidsnifferPost(value, node.tagName.toLowerCase());
          });
        });
      } catch (e) {}
    };
    var nativeFetch = window.fetch;
    if (nativeFetch) {
      window.fetch = function() {
        try {
          var input = arguments[0];
          var url = typeof input === 'string' ? input : input && input.url;
          window.__vidsnifferPost(url, 'fetch');
        } catch (e) {}
        return nativeFetch.apply(this, arguments).then(function(response) {
          try { window.__vidsnifferPost(response.url, 'fetch-response'); } catch (e) {}
          return response;
        });
      };
    }
    var nativeOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      try { window.__vidsnifferPost(url, 'xhr'); } catch (e) {}
      return nativeOpen.apply(this, arguments);
    };
    new MutationObserver(window.__vidsnifferScanDom).observe(document.documentElement || document.body, { childList: true, subtree: true, attributes: true });
    setInterval(function() {
      window.__vidsnifferScanDom();
      try {
        performance.getEntries().forEach(function(entry) {
          window.__vidsnifferPost(entry.name, 'performance');
        });
      } catch (e) {}
    }, 1600);
  }
  window.__vidsnifferScanDom();
  try {
    performance.getEntries().forEach(function(entry) {
      window.__vidsnifferPost(entry.name, 'performance');
    });
  } catch (e) {}
})();
''';
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 38,
      onPressed: onTap,
      child: Icon(icon, size: 20, color: AppTheme.ink),
    );
  }
}
