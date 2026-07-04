import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/resource_sheet.dart';
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
              decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(28)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 42),
                  const SizedBox(height: 18),
                  Text('解析网页视频，保存到本地', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('支持网页输入和内置浏览器嗅探。m3u8 下载后合并为 mp4。', style: TextStyle(color: Colors.white.withOpacity(0.86), height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppCard(
              child: Column(
                children: [
                  AppTextField(controller: controller, hintText: '粘贴网页 URL', onSubmitted: (_) => _parse(context)),
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
                      Expanded(child: GradientButton(label: '开始解析', icon: Icons.search_rounded, onPressed: () => _parse(context))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WebViewScreen(initialUrl: controller.text))),
                      icon: const Icon(Icons.language_rounded),
                      label: const Text('用内置 WebView 打开网页'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('最近解析', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
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
                      Expanded(child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis)),
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

  void _parse(BuildContext context) {
    FocusScope.of(context).unfocus();
    final state = UiStateScope.of(context);
    state.addRecent(controller.text);
    showResourceSheet(context, state.resources);
  }
}
