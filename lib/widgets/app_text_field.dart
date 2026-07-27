import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.controller,
    required this.hintText,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      autocorrect: false,
      enableSuggestions: false,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(CupertinoIcons.link),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除',
                onPressed: controller.clear,
                icon: const Icon(CupertinoIcons.clear_thick_circled),
              ),
      ),
    );
  }
}
