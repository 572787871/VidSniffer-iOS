import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_resource.dart';
import '../services/file_utils.dart';
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
    final height = MediaQuery.sizeOf(context).height * 0.82;
    final recommended = resources
        .where(
          (item) => item.isPlayable && !item.isAdSuspect && !item.isFragment,
        )
        .take(5)
        .toList();
    final all = resources
        .where((item) => !item.isAdSuspect && !item.isFragment)
        .toList();
    final ads = resources.where((item) => item.isAdSuspect).toList();
    final fragments = resources.where((item) => item.isFragment).toList();

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '可下载视频',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '已自动隐藏广告嫌疑和分片资源。',
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
                    length: 4,
                    child: Column(
                      children: [
                        TabBar(
                          isScrollable: true,
                          tabs: [
                            Tab(text: '推荐资源 ${recommended.length}'),
                            Tab(text: '全部资源 ${all.length}'),
                            Tab(text: '广告嫌疑 ${ads.length}'),
                            Tab(text: '分片/高级 ${fragments.length}'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _ResourceList(
                                resources: recommended,
                                emptyText: '没有足够可信的推荐资源，可到“全部资源”查看。',
                              ),
                              _ResourceList(resources: all),
                              _ResourceList(
                                resources: ads,
                                emptyText: '没有广告嫌疑资源。',
                              ),
                              _ResourceList(
                                resources: fragments,
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
      child: const Text('未自动发现视频。部分网站需要先播放视频，请进入网页播放后再点发现视频。'),
    );
  }
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({
    required this.resources,
    this.emptyText = '没有可直接下载的资源。',
  });

  final List<VideoResource> resources;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return Center(child: Text(emptyText, textAlign: TextAlign.center));
    }
    return ListView.separated(
      itemCount: resources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ResourceTile(resource: resources[index]),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({required this.resource});

  final VideoResource resource;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(resource.url);
    final host = uri?.host ?? '未知域名';
    final path = _pathLabel(uri);
    final meta = [
      resource.quality,
      if (resource.bitrate.isNotEmpty) resource.bitrate,
      if (resource.size != '未知') resource.size,
      if (resource.container.isNotEmpty) resource.container,
    ].where((item) => item.trim().isNotEmpty && item != '未知').join(' · ');
    final badge = resource.isAdSuspect
        ? '广告嫌疑'
        : (resource.recommendation.isEmpty
              ? '可能的视频资源'
              : resource.recommendation);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                            meta.isEmpty ? resource.displayFormat : meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        _Badge(label: badge, danger: resource.isAdSuspect),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '域名：$host',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '来源：${_sourceLabel(resource.source)}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    if (resource.codec.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '编码：${resource.codec}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: resource.url));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已复制真实资源链接')));
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制链接'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: resource.isFragment
                    ? null
                    : () async {
                        final selected = await _showDownloadConfirm(
                          context,
                          resource,
                        );
                        if (selected == null || !context.mounted) return;
                        state.downloadResource(selected);
                        Navigator.pop(context);
                      },
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<VideoResource?> _showDownloadConfirm(
    BuildContext context,
    VideoResource resource,
  ) async {
    final controller = TextEditingController(
      text: FileUtils.safeFileName(resource.title, fallback: 'video'),
    );
    final uri = Uri.tryParse(
      resource.pageUrl.isNotEmpty ? resource.pageUrl : resource.url,
    );
    final site = uri?.host ?? '未知来源';
    return showDialog<VideoResource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认下载'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLine('标题', resource.title),
              _InfoLine('来源网站', site),
              _InfoLine('格式', resource.displayFormat),
              _InfoLine('清晰度', resource.quality),
              if (resource.codec.isNotEmpty) _InfoLine('编码', resource.codec),
              if (resource.bitrate.isNotEmpty)
                _InfoLine('码率', resource.bitrate),
              _InfoLine('大小', resource.size),
              const _InfoLine('保存位置', 'Documents/videos/'),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: '文件名'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = FileUtils.safeFileName(
                controller.text,
                fallback: resource.title,
              );
              Navigator.pop(context, resource.copyWith(title: name));
            },
            child: const Text('下载'),
          ),
        ],
      ),
    );
  }

  String _pathLabel(Uri? uri) {
    if (uri == null) return resource.url;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.query.isEmpty ? '' : '?${uri.query}';
    final label = '$path$query';
    return label.length > 120
        ? '...${label.substring(label.length - 120)}'
        : label;
  }

  String _sourceLabel(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('xhr')) return 'XHR';
    if (lower.contains('fetch')) return 'fetch';
    if (lower.contains('dom')) return 'DOM';
    if (lower.contains('play') ||
        lower.contains('current') ||
        lower.contains('media')) {
      return 'video tag';
    }
    return 'resource';
  }

  String _typeLabel(VideoResource resource) {
    switch (resource.type) {
      case VideoResourceType.hls:
        return 'HLS';
      case VideoResourceType.ts:
        return 'TS';
      case VideoResourceType.mp4:
        return resource.displayFormat;
      case VideoResourceType.unknown:
        return resource.url.toLowerCase().contains('.m4s') ? 'M4S' : '未知';
    }
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '未知' : value)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.danger});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: danger ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: danger ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
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
