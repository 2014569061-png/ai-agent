import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

/// 附件播放器（A6）：消息气泡内嵌播放音频 / 视频附件。
/// [source] 为本地文件路径；[mime] 用于区分音频（audio/*）与视频（video/*）。
class AttachmentPlayer extends StatefulWidget {
  const AttachmentPlayer({super.key, required this.source, required this.mime});

  final String source;
  final String mime;

  @override
  State<AttachmentPlayer> createState() => _AttachmentPlayerState();
}

class _AttachmentPlayerState extends State<AttachmentPlayer> {
  final AudioPlayer _audio = AudioPlayer();
  VideoPlayerController? _video;
  bool _audioReady = false;
  bool _playing = false;
  String? _error;

  bool get _isVideo => widget.mime.startsWith('video/');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final file = File(widget.source);
      if (!await file.exists()) {
        setState(() => _error = '文件不存在');
        return;
      }
      if (_isVideo) {
        final controller = VideoPlayerController.file(file);
        _video = controller;
        await controller.initialize();
        if (mounted) setState(() => _audioReady = true);
      } else {
        await _audio.setFilePath(widget.source);
        if (mounted) setState(() => _audioReady = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '播放失败');
    }
  }

  Future<void> _toggle() async {
    if (_isVideo) {
      final video = _video;
      if (video == null) return;
      if (video.value.isPlaying) {
        await video.pause();
      } else {
        await video.play();
      }
      if (mounted) setState(() => _playing = video.value.isPlaying);
    } else {
      if (_audio.playing) {
        await _audio.pause();
      } else {
        await _audio.play();
      }
      if (mounted) setState(() => _playing = _audio.playing);
    }
  }

  @override
  void dispose() {
    _audio.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text('[$_error]',
          style: const TextStyle(fontSize: 12, color: Color(0xFF9AA5B1)));
    }
    final icon =
        _isVideo ? Icons.play_circle_outline : Icons.volume_up_outlined;
    if (_isVideo && _video != null && _video!.value.isInitialized) {
      return SizedBox(
        width: 220,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
                aspectRatio: _video!.value.aspectRatio,
                child: VideoPlayer(_video!)),
          ),
          IconButton(
              icon: Icon(
                  _video!.value.isPlaying
                      ? Icons.pause_circle
                      : Icons.play_circle,
                  size: 32),
              onPressed: _toggle),
        ]),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon: Icon(_audioReady
            ? (_playing ? Icons.pause_circle : icon)
            : Icons.hourglass_empty),
        onPressed: _audioReady ? _toggle : null,
      ),
      const Text('音频附件', style: TextStyle(fontSize: 12)),
    ]);
  }
}
