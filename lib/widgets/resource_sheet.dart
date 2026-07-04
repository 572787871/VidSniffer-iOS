import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_resource.dart';
import '../services/ui_state.dart';

Future<void> showResourceSheet(BuildContext context, List<VideoResource> resources) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => ResourceSheet(resources: resources),
  );
}

class ResourceSheet extends StatelessWidget {
  const ResourceSheet({required this.resources, super.key});

  final List<VideoResource> resources;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发现视频资源', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('仅下载你有权访问的视频内容。', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: resources.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = resources[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        _TypePill(label: _typeLabel(item)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(item.source, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '复制链接',
                          onPressed: () => Clipboard.setData(ClipboardData(text: item.url)),
                          icon: const Icon(Icons.copy_rounded),
                        ),
                        IconButton.filled(
                          tooltip: '下载',
                          onPressed: () {
                            state.downloadResource(item);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.download_rounded),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(VideoResource resource) {
    switch (resource.type) {
      case VideoResourceType.hls:
        return 'm3u8';
      case VideoResourceType.ts:
        return 'ts';
      case VideoResourceType.mp4:
        return resource.source.toLowerCase().contains('unknown') ? 'unknown' : 'mp4';
    }
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xff2563eb), Color(0xff7c3aed)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}
