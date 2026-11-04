import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'utils.dart';

class AudioBubble extends StatefulWidget {
  final String data; // base64
  final int seconds;
  const AudioBubble({super.key, required this.data, required this.seconds});

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final _player = AudioPlayer();
  late final Uint8List _bytes = base64Decode(widget.data);
  final _subs = <StreamSubscription>[];
  bool _playing = false;
  Duration _pos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    }));
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else if (_pos > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(BytesSource(_bytes));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.seconds <= 0 ? 1 : widget.seconds;
    final progress = (_pos.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);
    final shown = _pos > Duration.zero ? _pos.inSeconds : widget.seconds;
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                size: 38, color: AppColors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress.toDouble(),
                  minHeight: 3,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 4),
                Text(mmss(shown), style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
