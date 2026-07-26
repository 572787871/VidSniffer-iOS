import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BrowserPageRecord {
  const BrowserPageRecord({
    required this.url,
    required this.title,
    required this.updatedAt,
  });

  final String url;
  final String title;
  final DateTime updatedAt;

  BrowserPageRecord copyWith({String? title, DateTime? updatedAt}) {
    return BrowserPageRecord(
      url: url,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory BrowserPageRecord.fromJson(Map<String, dynamic> json) {
    return BrowserPageRecord(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class BrowserData {
  const BrowserData({this.history = const [], this.bookmarks = const []});

  final List<BrowserPageRecord> history;
  final List<BrowserPageRecord> bookmarks;
}

class BrowserDataStore {
  Future<BrowserData> load() async {
    final file = await _file();
    if (!await file.exists()) return const BrowserData();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const BrowserData();
      return BrowserData(
        history: _records(decoded['history']),
        bookmarks: _records(decoded['bookmarks']),
      );
    } catch (_) {
      return const BrowserData();
    }
  }

  Future<void> save({
    required List<BrowserPageRecord> history,
    required List<BrowserPageRecord> bookmarks,
  }) async {
    final file = await _file();
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(
      jsonEncode({
        'history': history.map((item) => item.toJson()).toList(),
        'bookmarks': bookmarks.map((item) => item.toJson()).toList(),
      }),
    );
  }

  List<BrowserPageRecord> _records(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) =>
              BrowserPageRecord.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.url.isNotEmpty)
        .toList();
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'browser_data.json'));
  }
}
