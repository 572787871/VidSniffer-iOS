import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/pill_button.dart';
import 'app_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.onOpenTab, super.key});

  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);

    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const Text(
              'VidSniffer Pro',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.05),
            ),
            const SizedBox(height: 8),
            const Text(
              '解析网页视频，保存到本地',
              style: TextStyle(fontSize: 16, color: AppTheme.muted),
            ),
            const SizedBox(height: 24),
            GlassCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => state.parse(_controller.text),
                          decoration: const InputDecoration(
                            hintText: '粘贴网页视频链接',
                            prefixIcon: Icon(LucideIcons.link2, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      PillButton(
                        label: '解析',
                        icon: LucideIcons.search,
                        compact: true,
                        onPressed: state.parsing ? null : () => state.parse(_controller.text),
                      ),
                    ],
                  ),
                  if (state.parsing) ...[
                    const SizedBox(height: 18),
                    const LinearProgressIndicator(minHeight: 5, borderRadius: BorderRadius.all(Radius.circular(99))),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 420.ms).slideY(begin: 0.05, end: 0),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _QuickEntry(label: '浏览器嗅探', icon: LucideIcons.radar, onTap: () => widget.onOpenTab(1))),
                const SizedBox(width: 12),
                Expanded(child: _QuickEntry(label: 'm3u8 下载', icon: LucideIcons.fileDown, onTap: () => widget.onOpenTab(2))),
                const SizedBox(width: 12),
                Expanded(child: _QuickEntry(label: '本地视频', icon: LucideIcons.library, onTap: () => widget.onOpenTab(3))),
              ],
            ),
            const SizedBox(height: 26),
            const _SectionHeader(title: '解析结果'),
            const SizedBox(height: 12),
            if (state.parseResults.isEmpty)
              const GlassCard(
                child: EmptyState(
                  title: '等待解析',
                  message: '粘贴网页视频链接后，解析结果会显示在这里。',
                  icon: LucideIcons.sparkles,
                ),
              )
            else
              for (final result in state.parseResults)
                _ResultCard(resource: result, onDownload: () => state.addDownload(result))
                    .animate()
                    .fadeIn(duration: 260.ms)
                    .slideY(begin: 0.06, end: 0),
          ],
        );
      },
    );
  }
}

class _QuickEntry extends StatelessWidget {
  const _QuickEntry({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: AppTheme.electricBlue, size: 24),
          const SizedBox(height: 9),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.resource, required this.onDownload});

  final VideoResource resource;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(gradient: AppTheme.accentGradient, borderRadius: BorderRadius.circular(18)),
            child: const Icon(LucideIcons.video, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(resource.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${resource.quality} · ${resource.size}', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onDownload,
            child: const Icon(LucideIcons.download, color: AppTheme.electricBlue),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900));
  }
}
