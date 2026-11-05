import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'utils.dart';

/// رسالة صوتية بأسلوب واتساب: زر تشغيل + موجة صوتية تتلوّن أثناء التشغيل + المدة + سرعة التشغيل
class AudioBubble extends StatefulWidget {
  final String data; // base64
  final int seconds;
  const AudioBubble({super.key, required this.data, required this.seconds});

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  static const _barCount = 34;

  final _player = AudioPlayer();
  late final Uint8List _bytes = base64Decode(widget.data);
  late final List<double> _bars = _makeBars();
  final _subs = <StreamSubscription>[];
  bool _playing = false;
  Duration _pos = Duration.zero;
  double _rate = 1.0;

  /// شكل الموجة ثابت لكل رسالة (مشتق من محتوى التسجيل)
  List<double> _makeBars() {
    var seed = widget.data.length;
    for (var i = 0; i < widget.data.length; i += 97) {
      seed = (seed * 31 + widget.data.codeUnitAt(i)) & 0x7fffffff;
    }
    final r = Random(seed);
    return List.generate(_barCount, (_) => 0.25 + r.nextDouble() * 0.75);
  }

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
        if (_rate != 1.0) await _player.setPlaybackRate(_rate);
      }
    } catch (_) {}
  }

  Future<void> _cycleRate() async {
    final next = _rate == 1.0 ? 1.5 : (_rate == 1.5 ? 2.0 : 1.0);
    setState(() => _rate = next);
    try {
      await _player.setPlaybackRate(next);
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.seconds <= 0 ? 1 : widget.seconds;
    final progress = (_pos.inMilliseconds / (total * 1000)).clamp(0.0, 1.0).toDouble();
    final shown = _pos > Duration.zero ? _pos.inSeconds : widget.seconds;

    final playedColor = dark ? const Color(0xFF53BDEB) : AppColors.primary;
    final idleColor = dark ? Colors.white38 : Colors.black26;
    final iconColor = dark ? Colors.white70 : const Color(0xFF54656F);
    final metaColor = dark ? const Color(0xFF8696A0) : const Color(0xFF667781);

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 34, color: iconColor),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الموجة تُرسم دائماً من اليسار إلى اليمين
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SizedBox(
                    height: 28,
                    child: Row(
                      children: [
                        for (var i = 0; i < _barCount; i++)
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 2.5,
                                height: 5 + 21 * _bars[i],
                                decoration: BoxDecoration(
                                  color: (i + 1) / _barCount <= progress
                                      ? playedColor
                                      : idleColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(mmss(shown), style: TextStyle(fontSize: 11.5, color: metaColor)),
                    const Spacer(),
                    if (_playing || _pos > Duration.zero)
                      GestureDetector(
                        onTap: _cycleRate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: dark ? Colors.white12 : Colors.black12,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _rate == 1.0 ? '1×' : (_rate == 1.5 ? '1.5×' : '2×'),
                            style: TextStyle(fontSize: 11, color: metaColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
