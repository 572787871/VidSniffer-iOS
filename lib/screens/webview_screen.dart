import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/ui_state.dart';
import '../widgets/resource_sheet.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({this.initialUrl = '', super.key});

  final String initialUrl;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final TextEditingController addressController;
  late final WebViewController webController;

  @override
  void initState() {
    super.initState();
    addressController = TextEditingController(text: widget.initialUrl.trim().isEmpty ? 'https://' : widget.initialUrl.trim());
    webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..loadRequest(Uri.parse(_normalized(addressController.text)));
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('网页嗅探')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: Row(
                  children: [
                    IconButton.filledTonal(onPressed: webController.goBack, icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                    IconButton.filledTonal(onPressed: webController.goForward, icon: const Icon(Icons.arrow_forward_ios_rounded)),
                    IconButton.filledTonal(onPressed: webController.reload, icon: const Icon(Icons.refresh_rounded)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: addressController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _load(),
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded), hintText: '输入网址'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: WebViewWidget(controller: webController),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: FilledButton.icon(
              onPressed: () => showResourceSheet(context, state.resources),
              icon: const Icon(Icons.video_library_rounded),
              label: const Text('发现视频'),
            ),
          ),
        ],
      ),
    );
  }

  void _load() {
    FocusScope.of(context).unfocus();
    final url = _normalized(addressController.text);
    addressController.text = url;
    webController.loadRequest(Uri.parse(url));
  }

  String _normalized(String value) {
    final text = value.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (text == 'https://' || text.isEmpty) return 'https://example.com';
    return 'https://$text';
  }
}
