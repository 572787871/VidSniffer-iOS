import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/pill_button.dart';
import 'app_state.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final TextEditingController _addressController;
  late final WebViewController _webController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: 'https://example.com/video');
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.midnight)
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
                          _ToolIcon(icon: LucideIcons.refreshCw, onTap: _webController.reload),
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
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          height: 430,
                          color: AppTheme.panelStrong,
                          child: Stack(
                            children: [
                              WebViewWidget(controller: _webController),
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
                              '${state.sniffedResources.first.title} · ${state.sniffedResources.first.size}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      PillButton(
                        label: '下载',
                        icon: LucideIcons.download,
                        compact: true,
                        onPressed: () => state.addDownload(state.sniffedResources.first),
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

  Future<void> _load(AppState state) async {
    var value = _addressController.text.trim();
    if (!value.startsWith('http')) {
      value = 'https://$value';
      _addressController.text = value;
    }
    await _webController.loadRequest(Uri.parse(value));
    await state.loadBrowserUrl(value);
  }
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
