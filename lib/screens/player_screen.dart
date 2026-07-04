import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.title, this.filePath, super.key});

  final String title;
  final String? filePath;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? controller;
  double speed = 1;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: const Color(0xff111111),
                    child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 76)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: Column(
                children: [
                  Slider(value: 0.38, onChanged: (_) {}),
                  Row(
                    children: [
                      IconButton.filled(onPressed: () {}, icon: const Icon(Icons.play_arrow_rounded)),
                      IconButton(onPressed: () {}, icon: const Icon(Icons.replay_10_rounded, color: Colors.white)),
                      IconButton(onPressed: () {}, icon: const Icon(Icons.forward_10_rounded, color: Colors.white)),
                      const Spacer(),
                      DropdownButton<double>(
                        value: speed,
                        dropdownColor: const Color(0xff222222),
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                          DropdownMenuItem(value: 1, child: Text('1.0x')),
                          DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                          DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                          DropdownMenuItem(value: 2, child: Text('2.0x')),
                        ],
                        onChanged: (value) => setState(() => speed = value ?? 1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
