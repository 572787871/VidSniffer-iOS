import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/progress_ring.dart';
import 'app_state.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const Text('下载任务', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('查看进度、速度并管理正在下载的视频', style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 20),
            if (state.downloads.isEmpty)
              const GlassCard(
                child: EmptyState(title: '暂无下载任务', message: '解析或嗅探到视频后，可以从卡片一键加入下载。', icon: LucideIcons.downloadCloud),
              )
            else
              for (final task in state.downloads)
                _DownloadCard(
                  task: task,
                  onToggle: () => state.toggleDownload(task),
                  onDelete: () => state.deleteDownload(task),
                ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.05, end: 0),
          ],
        );
      },
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.task, required this.onToggle, required this.onDelete});

  final DownloadTask task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          ProgressRing(percent: task.progress),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('${task.quality} · ${task.size} · ${task.speed}', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 12),
                LinearPercentIndicator(
                  padding: EdgeInsets.zero,
                  lineHeight: 7,
                  barRadius: const Radius.circular(999),
                  percent: task.progress.clamp(0.0, 1.0).toDouble(),
                  backgroundColor: Colors.white.withOpacity(0.1),
                  linearGradient: AppTheme.accentGradient,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 38,
                onPressed: onToggle,
                child: Icon(task.paused ? LucideIcons.play : LucideIcons.pause, color: AppTheme.electricBlue, size: 20),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 38,
                onPressed: onDelete,
                child: const Icon(LucideIcons.trash2, color: Color(0xffff6b7a), size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
