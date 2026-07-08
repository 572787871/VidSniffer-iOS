import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/parse_record.dart';
import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';
import '../widgets/download_confirm_dialog.dart';
import '../widgets/gradient_button.dart';
import '../widgets/home_sniffer.dart';
import 'resource_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final recentKey = GlobalKey();
  String? sniffUrl;
  int sniffRequestId = 0;

  @override
  void dispose() {
    scrollController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: state,
            builder: (context, _) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
              children: [
                const _HomeHeader(),
                const SizedBox(height: 14),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      AppTextField(
                        controller: controller,
                        hintText: '粘贴网页 URL',
                        onSubmitted: (_) => _parse(context),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _paste,
                              icon: const Icon(Icons.content_paste_rounded),
                              label: const Text('粘贴链接'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GradientButton(
                              label: '开始解析',
                              icon: Icons.search_rounded,
                              onPressed: () => _parse(context),
                            ),
                          ),
                        ],
                      ),
                      if (state.homeSnifferState != HomeSnifferState.idle) ...[
                        const SizedBox(height: 12),
                        _SnifferStatusBar(state: state),
                      ],
                      const SizedBox(height: 14),
                      _QuickEntryGrid(
                        onBrowser: () {
                          final url = controller.text.trim();
                          state.openInBrowser(
                            url.isEmpty ? 'https://www.google.com' : url,
                          );
                        },
                        onDownloads: () => state.selectTab(2),
                        onLibrary: () => state.selectTab(3),
                        onHistory: _scrollToRecent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  key: recentKey,
                  children: [
                    Expanded(
                      child: Text(
                        '最近解析',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed: state.recentParses.isEmpty
                          ? null
                          : () => state.selectTab(1),
                      child: const Text('更多'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (state.recentParses.isEmpty)
                  const AppCard(child: Text('暂无解析记录。输入网页 URL 后会在这里显示视频资源。'))
                else
                  for (final record in state.recentParses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ParseRecordCard(
                        record: record,
                        onRetry: () => _parse(context, url: record.pageUrl),
                        onOpenWeb: () => _openWebView(context, record.pageUrl),
                      ),
                    ),
              ],
            ),
          ),
          if (sniffUrl != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: HomeSniffer(
                key: ValueKey(sniffRequestId),
                initialUrl: sniffUrl!,
                onProgress: state.updateHomeSniffProgress,
                onFound: (record) {
                  unawaited(state.finishHomeSniffFound(record));
                  if (mounted) setState(() => sniffUrl = null);
                },
                onNotFound: (pageUrl, pageTitle) {
                  unawaited(
                    state.finishHomeSniffNotFound(
                      pageUrl: pageUrl,
                      pageTitle: pageTitle,
                    ),
                  );
                  if (mounted) setState(() => sniffUrl = null);
                },
                onFailed: (pageUrl, pageTitle, error) {
                  unawaited(
                    state.finishHomeSniffFailed(
                      pageUrl: pageUrl,
                      pageTitle: pageTitle,
                      error: error,
                    ),
                  );
                  if (mounted) setState(() => sniffUrl = null);
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim().isNotEmpty ?? false) {
      setState(() => controller.text = data!.text!.trim());
    }
  }

  void _parse(BuildContext context, {String? url}) {
    FocusScope.of(context).unfocus();
    final value = (url ?? controller.text).trim();
    final state = UiStateScope.of(context);
    if (value.isEmpty) {
      state.clearResources(message: '请输入网页 URL');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入网页 URL')));
      return;
    }
    controller.text = value;
    state.startHomeSniff(value);
    setState(() {
      sniffUrl = value;
      sniffRequestId++;
    });
  }

  void _openWebView(BuildContext context, String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    UiStateScope.of(context).openInBrowser(value);
  }

  void _scrollToRecent() {
    final context = recentKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.travel_explore_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'VidSniffer Pro',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.64),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 15, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEntryGrid extends StatelessWidget {
  const _QuickEntryGrid({
    required this.onBrowser,
    required this.onDownloads,
    required this.onLibrary,
    required this.onHistory,
  });

  final VoidCallback onBrowser;
  final VoidCallback onDownloads;
  final VoidCallback onLibrary;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickEntryTile(
            icon: Icons.explore_rounded,
            label: '浏览器',
            onTap: onBrowser,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickEntryTile(
            icon: Icons.download_rounded,
            label: '下载',
            onTap: onDownloads,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickEntryTile(
            icon: Icons.video_library_rounded,
            label: '视频库',
            onTap: onLibrary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickEntryTile(
            icon: Icons.history_rounded,
            label: '解析记录',
            onTap: onHistory,
          ),
        ),
      ],
    );
  }
}

class _QuickEntryTile extends StatelessWidget {
  const _QuickEntryTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.46),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: scheme.primary, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnifferStatusBar extends StatelessWidget {
  const _SnifferStatusBar({required this.state});

  final UiState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBusy = state.homeSnifferState == HomeSnifferState.sniffing;
    final icon = switch (state.homeSnifferState) {
      HomeSnifferState.found => Icons.check_circle_rounded,
      HomeSnifferState.notFound => Icons.info_rounded,
      HomeSnifferState.failed => Icons.error_outline_rounded,
      HomeSnifferState.idle || HomeSnifferState.sniffing => Icons.radar_rounded,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.homeSnifferStatus,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParseRecordCard extends StatelessWidget {
  _ParseRecordCard({
    required this.record,
    required this.onRetry,
    required this.onOpenWeb,
  }) : groups = _RecordGroups.from(record);

  final ParseRecord record;
  final VoidCallback onRetry;
  final VoidCallback onOpenWeb;
  final _RecordGroups groups;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = record.sourceSite.isNotEmpty
        ? record.sourceSite
        : (Uri.tryParse(record.pageUrl)?.host ?? '未知来源');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.status == ParseRecordStatus.found
                      ? '来自 $host 的视频资源'
                      : host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                _timeLabel(record.parsedAt),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            record.pageTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (record.status == ParseRecordStatus.found)
            _FoundRecordBody(
              record: record,
              groups: groups,
            )
          else
            _EmptyParseBody(
                record: record, onRetry: onRetry, onOpenWeb: onOpenWeb),
        ],
      ),
    );
  }

  String _timeLabel(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${value.month}/${value.day}';
  }
}

class _RecordGroups {
  _RecordGroups({
    required this.recommended,
    required this.other,
    required this.ads,
    required this.fragments,
  });

  final List<VideoResource> recommended;
  final List<VideoResource> other;
  final List<VideoResource> ads;
  final List<VideoResource> fragments;

  factory _RecordGroups.from(ParseRecord record) {
    return _RecordGroups(
      recommended: record.recommendedResources.take(5).toList(growable: false),
      other: record.otherResources.take(20).toList(growable: false),
      ads: record.adResources.take(20).toList(growable: false),
      fragments: record.fragmentResources.take(50).toList(growable: false),
    );
  }
}

class _FoundRecordBody extends StatelessWidget {
  const _FoundRecordBody({
    required this.record,
    required this.groups,
  });

  final ParseRecord record;
  final _RecordGroups groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResourceSection(
          title: '推荐资源',
          resources: groups.recommended,
          pageUrl: record.pageUrl,
          initiallyExpanded: true,
        ),
        if (groups.other.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ResourceSection(
            title: '其它资源',
            resources: groups.other,
            pageUrl: record.pageUrl,
            initiallyExpanded: true,
          ),
        ],
        if (groups.ads.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ResourceSection(
            title: '广告嫌疑资源',
            resources: groups.ads,
            pageUrl: record.pageUrl,
          ),
        ],
        if (groups.fragments.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ResourceSection(
            title: 'TS/M4S 分片',
            resources: groups.fragments,
            pageUrl: record.pageUrl,
          ),
        ],
      ],
    );
  }
}

class _EmptyParseBody extends StatelessWidget {
  const _EmptyParseBody({
    required this.record,
    required this.onRetry,
    required this.onOpenWeb,
  });

  final ParseRecord record;
  final VoidCallback onRetry;
  final VoidCallback onOpenWeb;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(record.message.isEmpty ? '未自动发现视频。' : record.message),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onOpenWeb,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('进入网页播放并嗅探'),
              ),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试解析'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResourceSection extends StatelessWidget {
  const _ResourceSection({
    required this.title,
    required this.resources,
    required this.pageUrl,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<VideoResource> resources;
  final String pageUrl;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) return const SizedBox.shrink();
    final visibleCount = resources.length > 5 ? 5 : resources.length;
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${resources.length} 个资源',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleCount,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final resource = resources[index];
              return RepaintBoundary(
                key: ValueKey(resource.id),
                child: _ResourceRow(resource: resource, pageUrl: pageUrl),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.resource, required this.pageUrl});

  final VideoResource resource;
  final String pageUrl;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(resource.url)?.host ?? '未知来源';
    final meta = [
      resource.displayFormat,
      resource.quality,
      if (resource.duration > Duration.zero) _durationLabel(resource.duration),
      resource.size,
    ].where((item) => item.isNotEmpty && item != '未知').join(' · ');
    final flag = resource.isCurrentPlayback
        ? '当前播放'
        : (resource.isAdSuspect
            ? '广告嫌疑'
            : (resource.recommendation.isNotEmpty ? '推荐' : ''));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ResourceThumb(resource: resource),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        resource.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (flag.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        flag,
                        style: TextStyle(
                          color: resource.isAdSuspect
                              ? scheme.error
                              : scheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  meta.isEmpty ? resource.displayFormat : meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  '$host · ${_sourceLabel(resource.source)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _CompactIconButton(
            tooltip: '预览',
            icon: Icons.play_arrow_rounded,
            onPressed: resource.isPlayable
                ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ResourcePreviewScreen.network(resource: resource),
                      ),
                    )
                : null,
          ),
          const SizedBox(width: 6),
          _CompactIconButton(
            tooltip: '下载',
            icon: Icons.download_rounded,
            filled: true,
            onPressed: resource.isFragment
                ? null
                : () async {
                    final selected =
                        await showDownloadConfirmDialog(context, resource);
                    if (selected == null || !context.mounted) return;
                    state.downloadResource(selected);
                  },
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            iconSize: 20,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'copy', child: Text('复制链接')),
              PopupMenuItem(value: 'browser', child: Text('进入浏览器')),
            ],
            onSelected: (value) {
              if (value == 'copy') {
                Clipboard.setData(ClipboardData(text: resource.url));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制真实资源链接')),
                );
              } else {
                state.openInBrowser(pageUrl.isNotEmpty ? pageUrl : resource.pageUrl);
              }
            },
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('xhr')) return 'XHR';
    if (lower.contains('fetch')) return 'fetch';
    if (lower.contains('dom')) return 'DOM';
    if (lower.contains('video') || lower.contains('media')) return 'video tag';
    return 'resource';
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(
          backgroundColor: filled
              ? scheme.primary
              : scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          foregroundColor: filled ? scheme.onPrimary : scheme.primary,
          disabledBackgroundColor:
              scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: filled
                ? BorderSide.none
                : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
        ),
      ),
    );
  }
}

class _ResourceThumb extends StatelessWidget {
  const _ResourceThumb({required this.resource});

  final VideoResource resource;

  @override
  Widget build(BuildContext context) {
    final thumb = resource.thumbnailUrl;
    if (thumb.startsWith('http://') || thumb.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          thumb,
          width: 72,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _TypeBox(label: resource.displayFormat),
        ),
      );
    }
    return _TypeBox(label: resource.displayFormat);
  }
}

class _TypeBox extends StatelessWidget {
  const _TypeBox({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff2563eb), Color(0xff7c3aed)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}
