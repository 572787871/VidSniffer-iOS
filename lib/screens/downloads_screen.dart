import 'package:flutter/material.dart';

import '../models/mock_models.dart';
import '../services/ui_state.dart';
import '../widgets/app_card.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('下载任务')),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          itemBuilder: (context, index) => _DownloadCard(task: state.downloads[index]),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: state.downloads.length,
        ),
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.task});

  final MockDownloadTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: task.completed ? scheme.primaryContainer : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(task.completed ? Icons.check_rounded : Icons.downloading_rounded, color: task.completed ? scheme.primary : scheme.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${task.type} · ${task.speed} · 剩余 ${task.remaining}', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(value: task.progress, minHeight: 8, borderRadius: BorderRadius.circular(99)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!task.completed) ...[
                FilledButton.tonalIcon(onPressed: () {}, icon: Icon(task.paused ? Icons.play_arrow_rounded : Icons.pause_rounded), label: Text(task.paused ? '继续' : '暂停')),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.close_rounded), label: const Text('取消')),
              ] else
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(title: task.title))),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
