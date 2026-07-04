import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';
import '../widgets/gradient_button.dart';
import 'webview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('视频解析下载')),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '解析网页视频，保存到本地',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持网页输入和内置浏览器嗅探。m3u8 下载后合并为 mp4。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppCard(
              child: Row(
                children: [
                  _StatItem(label: '视频数量', value: '${state.videos.length}'),
                  _StatItem(
                    label: '总容量',
                    value: _formatBytes(
                      state.videos.fold<int>(0, (sum, item) => sum + item.size),
                    ),
                  ),
                  _StatItem(label: '今日下载', value: '${_todayCount(state)}'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppCard(
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
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              WebViewScreen(initialUrl: controller.text),
                        ),
                      ),
                      icon: const Icon(Icons.language_rounded),
                      label: const Text('用内置 WebView 打开网页'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '最近解析',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final item in state.recentUrls)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => controller.text = item,
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim().isNotEmpty ?? false) {
      setState(() => controller.text = data!.text!.trim());
    }
  }

  Future<void> _parse(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final value = controller.text.trim();
    final state = UiStateScope.of(context);
    if (value.isEmpty) {
      state.clearResources(message: '请输入网页 URL');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入网页 URL')));
      return;
    }
    state.addRecent(value);
    state.clearResources(message: '正在打开网页并嗅探视频');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebViewScreen(
          initialUrl: value,
          autoDiscover: true,
          autoParseOnly: true,
        ),
      ),
    );
  }

  int _todayCount(UiState state) {
    final now = DateTime.now();
    return state.videos.where((item) {
      final value = item.modifiedAt;
      return value.year == now.year &&
          value.month == now.month &&
          value.day == now.day;
    }).length;
  }

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
