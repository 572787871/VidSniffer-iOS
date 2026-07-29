import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/download_task.dart';

class DownloadTaskStore {
  Future<List<DownloadTask>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DownloadTask.fromJson(Map<String, dynamic>.from(item)))
          .where((task) => task.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<DownloadTask> tasks) async {
    final file = await _file();
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final payload = tasks.map((task) => task.toJson()).toList();
    await file.writeAsString(jsonEncode(payload));
  }

  Future<int?> loadMaxConcurrentDownloads() async {
    final file = await _preferencesFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return int.tryParse('${decoded['maxConcurrentDownloads'] ?? ''}');
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMaxConcurrentDownloads(int value) async {
    final file = await _preferencesFile();
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(
      jsonEncode({'maxConcurrentDownloads': value}),
    );
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'download_tasks.json'));
  }

  Future<File> _preferencesFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'download_preferences.json'));
  }
}
