import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/local_video.dart';
import 'file_utils.dart';

class LocalLibrary {
  Future<List<LocalVideo>> scan() async {
    final dir = await FileUtils.videosDirectory();
    final files = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
          final ext = p.extension(file.path).toLowerCase();
          return ['.mp4', '.m4v', '.mov'].contains(ext);
        })
        .toList();

    final videos = <LocalVideo>[];
    for (final file in files) {
      final stat = await file.stat();
      videos.add(LocalVideo(
        path: file.path,
        name: p.basename(file.path),
        size: stat.size,
        modifiedAt: stat.modified,
      ));
    }
    videos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return videos;
  }

  Future<void> delete(LocalVideo video) async {
    final file = File(video.path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
