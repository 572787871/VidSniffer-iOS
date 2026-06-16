import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final handler = await AudioService.init<AudioBookAudioHandler>(
    builder: AudioBookAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.ai_audiobook.playback',
      androidNotificationChannelName: 'AI 听书',
      androidNotificationOngoing: true,
    ),
  );
  runApp(AiAudioBookApp(handler: handler));
}

class AiAudioBookApp extends StatelessWidget {
  const AiAudioBookApp({required this.handler, super.key});

  final AudioBookAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 听书',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2563eb),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: HomePage(handler: handler),
    );
  }
}

class BookChapter {
  const BookChapter({
    required this.title,
    required this.text,
    required this.startOffset,
  });

  final String title;
  final String text;
  final int startOffset;

  Map<String, Object?> toJson() => {
        'title': title,
        'text': text,
        'startOffset': startOffset,
      };

  static BookChapter fromJson(Map<String, Object?> json) => BookChapter(
        title: json['title'] as String? ?? '未命名章节',
        text: json['text'] as String? ?? '',
        startOffset: json['startOffset'] as int? ?? 0,
      );
}

class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.voice,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String voice;

  ApiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? voice,
  }) {
    return ApiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      voice: voice ?? this.voice,
    );
  }

  Map<String, Object?> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'voice': voice,
      };

  static ApiConfig fromPrefs(SharedPreferences prefs) => ApiConfig(
        baseUrl: prefs.getString('apiBaseUrl') ?? 'https://api.openai.com/v1',
        apiKey: prefs.getString('apiKey') ?? '',
        model: prefs.getString('apiModel') ?? 'gpt-4o-mini-tts',
        voice: prefs.getString('apiVoice') ?? 'alloy',
      );
}

class HomePage extends StatefulWidget {
  const HomePage({required this.handler, super.key});

  final AudioBookAudioHandler handler;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _chaptersKey = 'chapters';
  static const _bookTitleKey = 'bookTitle';
  static const _chapterIndexKey = 'chapterIndex';
  static const _chapterPositionKey = 'chapterPositionMs';
  static const _speedKey = 'speed';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _chapterScrollController = ScrollController();

  SharedPreferences? _prefs;
  List<BookChapter> _chapters = const [];
  ApiConfig _apiConfig = const ApiConfig(
    baseUrl: 'https://api.openai.com/v1',
    apiKey: '',
    model: 'gpt-4o-mini-tts',
    voice: 'alloy',
  );
  String _bookTitle = '未导入书籍';
  int _currentChapter = 0;
  double _speed = 1;
  bool _loading = true;
  bool _preparing = false;
  String? _status;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mediaItemSub?.cancel();
    _chapterScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedChapters = prefs.getString(_chaptersKey);
    final chapters = encodedChapters == null
        ? <BookChapter>[]
        : (jsonDecode(encodedChapters) as List<dynamic>)
            .map((item) => BookChapter.fromJson(Map<String, Object?>.from(item as Map)))
            .toList();

    setState(() {
      _prefs = prefs;
      _apiConfig = ApiConfig.fromPrefs(prefs);
      _chapters = chapters;
      _bookTitle = prefs.getString(_bookTitleKey) ?? '未导入书籍';
      _currentChapter = min(
        prefs.getInt(_chapterIndexKey) ?? 0,
        max(chapters.length - 1, 0),
      );
      _speed = prefs.getDouble(_speedKey) ?? 1;
      _loading = false;
    });

    await widget.handler.setSpeed(_speed);
    _positionSub = AudioService.position.listen((position) {
      _prefs?.setInt(_chapterPositionKey, position.inMilliseconds);
    });
    _mediaItemSub = widget.handler.mediaItem.listen((item) {
      final nextIndex = item?.extras?['chapterIndex'] as int?;
      if (nextIndex == null || nextIndex == _currentChapter || !mounted) {
        return;
      }
      _prefs?.setInt(_chapterIndexKey, nextIndex);
      _prefs?.setInt(_chapterPositionKey, 0);
      setState(() => _currentChapter = nextIndex);
    });

    if (_chapters.isNotEmpty) {
      await widget.handler.loadBook(
        title: _bookTitle,
        chapters: _chapters,
        apiConfig: _apiConfig,
        initialIndex: _currentChapter,
      );
      final savedPosition = prefs.getInt(_chapterPositionKey) ?? 0;
      if (savedPosition > 0) {
        await widget.handler.seek(Duration(milliseconds: savedPosition));
      }
    }
  }

  Future<void> _importTxt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    final content = _decodeTxt(bytes);
    final chapters = ChapterParser.parse(content);
    final title = file.name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');

    await _prefs?.setString(_bookTitleKey, title);
    await _prefs?.setString(
      _chaptersKey,
      jsonEncode(chapters.map((chapter) => chapter.toJson()).toList()),
    );
    await _prefs?.setInt(_chapterIndexKey, 0);
    await _prefs?.setInt(_chapterPositionKey, 0);

    setState(() {
      _bookTitle = title;
      _chapters = chapters;
      _currentChapter = 0;
      _status = '已识别 ${chapters.length} 章';
    });

    await widget.handler.loadBook(
      title: title,
      chapters: chapters,
      apiConfig: _apiConfig,
      initialIndex: 0,
    );
  }

  String _decodeTxt(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  Future<void> _playChapter(int index, {bool autoplay = true}) async {
    if (_chapters.isEmpty || index < 0 || index >= _chapters.length) {
      return;
    }
    if (_apiConfig.apiKey.trim().isEmpty) {
      setState(() => _status = '请先在 API 配置中填写 API Key');
      _scaffoldKey.currentState?.openEndDrawer();
      return;
    }

    setState(() {
      _preparing = true;
      _status = '正在生成语音...';
    });

    try {
      await widget.handler.playChapter(index, autoplay: autoplay);
      await _prefs?.setInt(_chapterIndexKey, index);
      setState(() {
        _currentChapter = index;
        _status = null;
      });
    } on Object catch (error) {
      setState(() => _status = '语音生成失败：$error');
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
      }
    }
  }

  Future<void> _previousChapter() async {
    await _playChapter(max(_currentChapter - 1, 0));
  }

  Future<void> _nextChapter() async {
    await _playChapter(min(_currentChapter + 1, _chapters.length - 1));
  }

  Future<void> _setSpeed(double speed) async {
    await _prefs?.setDouble(_speedKey, speed);
    await widget.handler.setSpeed(speed);
    setState(() => _speed = speed);
  }

  Future<void> _saveApiConfig(ApiConfig config) async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await prefs.setString('apiBaseUrl', config.baseUrl.trim());
    await prefs.setString('apiKey', config.apiKey.trim());
    await prefs.setString('apiModel', config.model.trim());
    await prefs.setString('apiVoice', config.voice.trim());
    setState(() {
      _apiConfig = config;
      _status = 'API 配置已保存';
    });
    await widget.handler.updateApiConfig(config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('AI 听书'),
        actions: [
          IconButton(
            tooltip: '导入 TXT',
            onPressed: _importTxt,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'API 配置',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      endDrawer: ApiConfigDrawer(
        config: _apiConfig,
        onSave: _saveApiConfig,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  _BookHeader(
                    title: _bookTitle,
                    chapterCount: _chapters.length,
                    status: _status,
                  ),
                  Expanded(
                    child: _chapters.isEmpty
                        ? _EmptyImportView(onImport: _importTxt)
                        : _ChapterList(
                            chapters: _chapters,
                            currentChapter: _currentChapter,
                            controller: _chapterScrollController,
                            onTap: _playChapter,
                          ),
                  ),
                  _PlayerPanel(
                    handler: widget.handler,
                    chapterTitle: _chapters.isEmpty
                        ? '暂无章节'
                        : _chapters[_currentChapter].title,
                    speed: _speed,
                    preparing: _preparing,
                    onPrevious: _previousChapter,
                    onNext: _nextChapter,
                    onSpeedChanged: _setSpeed,
                  ),
                ],
              ),
            ),
    );
  }
}

class ChapterParser {
  static final _chapterHeading = RegExp(
    r'^\s*((第\s*[0-9零一二三四五六七八九十百千万两]+\s*[章节回卷部篇集].*)|([0-9]{1,4}[\.、]\s*.+))\s*$',
    multiLine: true,
  );

  static List<BookChapter> parse(String rawText) {
    final text = rawText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
        .trim();
    if (text.isEmpty) {
      return const [];
    }

    final matches = _chapterHeading.allMatches(text).toList();
    if (matches.isEmpty) {
      return _splitByLength(text);
    }

    final chapters = <BookChapter>[];
    if (matches.first.start > 0) {
      final preface = text.substring(0, matches.first.start).trim();
      if (preface.isNotEmpty) {
        chapters.add(BookChapter(title: '序章', text: preface, startOffset: 0));
      }
    }

    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final block = text.substring(start, end).trim();
      final lines = block.split('\n');
      final title = lines.first.trim();
      final body = lines.skip(1).join('\n').trim();
      chapters.add(BookChapter(
        title: title.isEmpty ? '第 ${i + 1} 章' : title,
        text: body.isEmpty ? block : body,
        startOffset: start,
      ));
    }

    return chapters;
  }

  static List<BookChapter> _splitByLength(String text) {
    const maxLength = 3500;
    final chapters = <BookChapter>[];
    for (var start = 0; start < text.length; start += maxLength) {
      final end = min(start + maxLength, text.length);
      chapters.add(BookChapter(
        title: '自动分段 ${chapters.length + 1}',
        text: text.substring(start, end),
        startOffset: start,
      ));
    }
    return chapters;
  }
}

class AudioBookAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  final _dio = Dio();

  List<BookChapter> _chapters = const [];
  ApiConfig _apiConfig = const ApiConfig(
    baseUrl: 'https://api.openai.com/v1',
    apiKey: '',
    model: 'gpt-4o-mini-tts',
    voice: 'alloy',
  );
  String _bookTitle = 'AI 听书';
  int _chapterIndex = 0;

  AudioBookAudioHandler() {
    _player.playbackEventStream.listen(_broadcastPlaybackState);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed &&
          _chapterIndex + 1 < _chapters.length) {
        playChapter(_chapterIndex + 1);
      }
    });
  }

  Future<void> loadBook({
    required String title,
    required List<BookChapter> chapters,
    required ApiConfig apiConfig,
    required int initialIndex,
  }) async {
    _bookTitle = title;
    _chapters = chapters;
    _apiConfig = apiConfig;
    _chapterIndex = initialIndex;
    if (chapters.isNotEmpty) {
      _setMediaItem(chapters[initialIndex], initialIndex);
    }
  }

  Future<void> updateApiConfig(ApiConfig config) async {
    _apiConfig = config;
  }

  Future<void> playChapter(int index, {bool autoplay = true}) async {
    if (index < 0 || index >= _chapters.length) {
      return;
    }
    _chapterIndex = index;
    final chapter = _chapters[index];
    _setMediaItem(chapter, index);
    final files = await _ttsFilesForChapter(index, chapter.text);
    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: files.map((file) => AudioSource.file(file.path)).toList(),
      ),
    );
    if (autoplay) {
      await _player.play();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToPrevious() async {
    await playChapter(max(_chapterIndex - 1, 0));
  }

  @override
  Future<void> skipToNext() async {
    await playChapter(min(_chapterIndex + 1, _chapters.length - 1));
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<List<File>> _ttsFilesForChapter(int index, String text) async {
    final chunks = _splitForTts(text);
    final files = <File>[];
    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      files.add(await _ttsFileForChunk(index, chunkIndex, chunks[chunkIndex]));
    }
    return files;
  }

  Future<File> _ttsFileForChunk(int index, int chunkIndex, String text) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/tts_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    final signature = base64Url.encode(utf8.encode(
      '${_apiConfig.baseUrl}|${_apiConfig.model}|${_apiConfig.voice}|$index|$chunkIndex|${text.hashCode}',
    ));
    final file = File('${cacheDir.path}/$signature.mp3');
    if (await file.exists() && await file.length() > 0) {
      return file;
    }

    final baseUrl = _apiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await _dio.post<List<int>>(
      '$baseUrl/audio/speech',
      data: {
        'model': _apiConfig.model,
        'voice': _apiConfig.voice,
        'input': text,
        'format': 'mp3',
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Authorization': 'Bearer ${_apiConfig.apiKey}',
          'Content-Type': 'application/json',
        },
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('TTS 接口没有返回音频数据');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  List<String> _splitForTts(String text) {
    const maxChars = 3800;
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxChars) {
      return [compact];
    }
    final chunks = <String>[];
    var start = 0;
    while (start < compact.length) {
      var end = min(start + maxChars, compact.length);
      if (end < compact.length) {
        final punctuation = compact.lastIndexOf(RegExp('[。！？；，,.!?;]'), end);
        if (punctuation > start + 1200) {
          end = punctuation + 1;
        }
      }
      chunks.add(compact.substring(start, end).trim());
      start = end;
    }
    return chunks.where((chunk) => chunk.isNotEmpty).toList();
  }

  void _setMediaItem(BookChapter chapter, int index) {
    mediaItem.add(MediaItem(
      id: '$index',
      album: _bookTitle,
      title: chapter.title,
      artist: 'AI 听书',
      duration: _player.duration,
      extras: {'chapterIndex': index},
    ));
  }

  void _broadcastPlaybackState(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _chapterIndex,
    ));
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }
}

class _BookHeader extends StatelessWidget {
  const _BookHeader({
    required this.title,
    required this.chapterCount,
    required this.status,
  });

  final String title;
  final int chapterCount;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            chapterCount == 0 ? '等待导入 TXT 文件' : '$chapterCount 个章节',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(status!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
        ],
      ),
    );
  }
}

class _EmptyImportView extends StatelessWidget {
  const _EmptyImportView({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: onImport,
        icon: const Icon(Icons.upload_file),
        label: const Text('导入 TXT 文件'),
      ),
    );
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.chapters,
    required this.currentChapter,
    required this.controller,
    required this.onTap,
  });

  final List<BookChapter> chapters;
  final int currentChapter;
  final ScrollController controller;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      itemCount: chapters.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final selected = index == currentChapter;
        final chapter = chapters[index];
        return ListTile(
          selected: selected,
          leading: CircleAvatar(
            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
          ),
          title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            chapter.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selected ? const Icon(Icons.graphic_eq) : const Icon(Icons.chevron_right),
          onTap: () => onTap(index),
        );
      },
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.handler,
    required this.chapterTitle,
    required this.speed,
    required this.preparing,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeedChanged,
  });

  final AudioBookAudioHandler handler;
  final String chapterTitle;
  final double speed;
  final bool preparing;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<double> onSpeedChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DropdownButton<double>(
                  value: speed,
                  underline: const SizedBox.shrink(),
                  items: const [0.75, 1.0, 1.25, 1.5, 2.0]
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text('${item}x'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      onSpeedChanged(value);
                    }
                  },
                ),
              ],
            ),
            StreamBuilder<Duration>(
              stream: AudioService.position,
              builder: (context, positionSnapshot) {
                return StreamBuilder<MediaItem?>(
                  stream: handler.mediaItem,
                  builder: (context, itemSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final duration = itemSnapshot.data?.duration ?? handler._player.duration ?? Duration.zero;
                    final maxMs = max(duration.inMilliseconds, 1).toDouble();
                    final value = min(position.inMilliseconds.toDouble(), maxMs);
                    return Row(
                      children: [
                        Text(_formatDuration(position)),
                        Expanded(
                          child: Slider(
                            value: value,
                            max: maxMs,
                            onChanged: (next) {
                              handler.seek(Duration(milliseconds: next.round()));
                            },
                          ),
                        ),
                        Text(_formatDuration(duration)),
                      ],
                    );
                  },
                );
              },
            ),
            StreamBuilder<PlaybackState>(
              stream: handler.playbackState,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '上一章',
                      onPressed: onPrevious,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: preparing
                          ? null
                          : () {
                              if (playing) {
                                handler.pause();
                              } else {
                                handler.play();
                              }
                            },
                      icon: preparing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(playing ? Icons.pause : Icons.play_arrow),
                      label: Text(playing ? '暂停' : '播放'),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: '下一章',
                      onPressed: onNext,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class ApiConfigDrawer extends StatefulWidget {
  const ApiConfigDrawer({
    required this.config,
    required this.onSave,
    super.key,
  });

  final ApiConfig config;
  final ValueChanged<ApiConfig> onSave;

  @override
  State<ApiConfigDrawer> createState() => _ApiConfigDrawerState();
}

class _ApiConfigDrawerState extends State<ApiConfigDrawer> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _voice;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.config.baseUrl);
    _apiKey = TextEditingController(text: widget.config.apiKey);
    _model = TextEditingController(text: widget.config.model);
    _voice = TextEditingController(text: widget.config.voice);
  }

  @override
  void didUpdateWidget(covariant ApiConfigDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _baseUrl.text = widget.config.baseUrl;
      _apiKey.text = widget.config.apiKey;
      _model.text = widget.config.model;
      _voice.text = widget.config.voice;
    }
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('API 配置', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _voice,
              decoration: const InputDecoration(
                labelText: 'Voice',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                widget.onSave(ApiConfig(
                  baseUrl: _baseUrl.text,
                  apiKey: _apiKey.text,
                  model: _model.text,
                  voice: _voice.text,
                ));
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

