import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';

Future<void> showResourceSheet(
  BuildContext context,
  List<VideoResource> resources,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => ResourceSheet(resources: resources),
  );
}

class ResourceSheet extends StatelessWidget {
  ResourceSheet({required List<VideoResource> resources, super.key})
      : resources = VideoSniffer().prioritizeResources(resources, limit: 50);

  final List<VideoResource> resources;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final recommended = _recommended(resources);
    final main = _mainResources(resources);
    final fragments = resources.where(_isFragment).toList();

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '发现视频资源',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '仅下载你有权访问的视频内容。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              if (resources.isEmpty)
                _EmptyResources()
              else
                Expanded(
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        TabBar(
                          tabs: [
                            Tab(text: '推荐资源 ${recommended.length}'),
                            Tab(text: '全部资源 ${main.length}'),
                            Tab(text: '分片/高级 ${fragments.length}'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _ResourceList(
                                resources: recommended,
                                recommended: recommended,
                              ),
                              _ResourceList(
                                resources: main,
                                recommended: recommended,
                              ),
                              _ResourceList(
                                resources: fragments,
                                recommended: recommended,
                                emptyText: '没有捕获到 ts/m4s 分片。',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<VideoResource> _recommended(List<VideoResource> values) {
    final playable = values
        .where(
          (item) =>
              item.type == VideoResourceType.hls ||
              item.type == VideoResourceType.mp4,
        )
        .toList();
    if (playable.isEmpty) {
      return const [];
    }
    return playable.take(3).toList();
  }

  List<VideoResource> _mainResources(List<VideoResource> values) {
    final hasPlayable = values.any(
      (item) =>
          item.type == VideoResourceType.hls ||
          item.type == VideoResourceType.mp4,
    );
    if (!hasPlayable) {
      return values.where((item) => !_isFragment(item)).toList();
    }
    return values.where((item) => !_isFragment(item)).toList();
  }

  bool _isFragment(VideoResource resource) {
    final lower = resource.url.toLowerCase();
    return resource.type == VideoResourceType.ts || lower.contains('.m4s');
  }
}

class _EmptyResources extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text('未发现视频资源。请确认网页已加载完成，或先在网页内播放视频后重新嗅探。'),
    );
  }
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({
    required this.resources,
    required this.recommended,
    this.emptyText = '没有可直接下载的资源。',
  });

  final List<VideoResource> resources;
  final List<VideoResource> recommended;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return Center(child: Text(emptyText, textAlign: TextAlign.center));
    }
    return ListView.separated(
      itemCount: resources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = resources[index];
        return _ResourceTile(
          resource: item,
          isRecommended: recommended.any(
            (value) => value.normalizedUrl == item.normalizedUrl,
          ),
        );
      },
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({required this.resource, required this.isRecommended});

  final VideoResource resource;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(resource.url);
    final host = uri?.host ?? '未知域名';
    final path = _pathLabel(uri);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypePill(label: _typeLabel(resource)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (isRecommended)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '推荐下载',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_sourceLabel(resource.source)} · 清晰度 ${resource.quality} · 大小 ${resource.size}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '复制链接',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: resource.url));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制真实资源链接')));
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton.filled(
            tooltip: '下载',
            onPressed: () {
              state.downloadResource(resource);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
    );
  }

  String _pathLabel(Uri? uri) {
    if (uri == null) {
      return resource.url;
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.query.isEmpty ? '' : '?${uri.query}';
    final label = '$path$query';
    return label.length > 96
        ? '...${label.substring(label.length - 96)}'
        : label;
  }

  String _sourceLabel(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('xhr')) return 'XHR';
    if (lower.contains('fetch')) return 'fetch';
    if (lower.contains('dom')) return 'DOM';
    if (lower.contains('video') || lower.contains('media')) return 'video 标签';
    return 'resource';
  }

  String _typeLabel(VideoResource resource) {
    switch (resource.type) {
      case VideoResourceType.hls:
        return 'm3u8';
      case VideoResourceType.ts:
        return 'ts';
      case VideoResourceType.mp4:
        return 'mp4';
      case VideoResourceType.unknown:
        return resource.url.toLowerCase().contains('.m4s') ? 'm4s' : 'unknown';
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
        gradient: const LinearGradient(
          colors: [Color(0xff2563eb), Color(0xff7c3aed)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
