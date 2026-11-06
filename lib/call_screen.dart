import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import 'agora_config.dart';
import 'utils.dart';

/// شاشة المكالمة (صوت/فيديو) داخل التطبيق عبر Agora
class CallScreen extends StatefulWidget {
  final String room;
  final bool video;
  final String title;
  const CallScreen({super.key, required this.room, required this.video, required this.title});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RtcEngine? _engine;
  final _remotes = <int>[];
  bool _joined = false;
  bool _muted = false;
  bool _camOff = false;
  bool _speaker = true;
  String? _error;
  Timer? _timer;
  int _seconds = 0;

  bool get _video => widget.video;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final perms = <Permission>[Permission.microphone, if (_video) Permission.camera];
      final res = await perms.request();
      if (res.values.any((s) => !s.isGranted)) {
        if (mounted) setState(() => _error = 'يلزم السماح بالميكروفون${_video ? ' والكاميرا' : ''} لإجراء المكالمة');
        return;
      }
      // تذكرة دخول مؤقتة من الخادم (بعد التحقق من حسابي)
      var token = '';
      if (kCallsWorkerUrl.isNotEmpty) {
        final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
        final r = await http
            .get(Uri.parse('$kCallsWorkerUrl/agora-token?channel=${widget.room}'),
                headers: {'Authorization': 'Bearer $idToken'})
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) {
          if (mounted) setState(() => _error = 'تعذر الحصول على تصريح المكالمة (${r.statusCode})');
          return;
        }
        token = (jsonDecode(r.body)['token'] ?? '').toString();
      }
      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(const RtcEngineContext(
        appId: kAgoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (conn, elapsed) {
          if (!mounted) return;
          // مسار الصوت لا يُضبط إلا بعد الانضمام للقناة
          engine.setEnableSpeakerphone(_speaker).catchError((_) {});
          setState(() => _joined = true);
          _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted && _remotes.isNotEmpty) setState(() => _seconds++);
          });
        },
        onUserJoined: (conn, uid, elapsed) {
          if (mounted && !_remotes.contains(uid)) setState(() => _remotes.add(uid));
        },
        onUserOffline: (conn, uid, reason) {
          if (mounted) setState(() => _remotes.remove(uid));
        },
        onError: (err, msg) {
          if (mounted && !_joined) setState(() => _error = 'تعذر الاتصال ($err)');
        },
      ));
      await engine.enableAudio();
      if (_video) {
        await engine.enableVideo();
        await engine.startPreview();
      }
      _speaker = _video;
      await engine.joinChannel(
        token: token,
        channelId: widget.room,
        uid: 0,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: _video,
          autoSubscribeAudio: true,
          autoSubscribeVideo: _video,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر بدء المكالمة\n$e');
    }
  }

  Future<void> _hangUp() async {
    _timer?.cancel();
    final e = _engine;
    _engine = null;
    try {
      await e?.leaveChannel();
      await e?.release();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    final e = _engine;
    _engine = null;
    e?.leaveChannel().then((_) => e.release()).catchError((_) {});
    super.dispose();
  }

  Widget _remoteView(int uid) => AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine!,
          canvas: VideoCanvas(uid: uid),
          connection: RtcConnection(channelId: widget.room),
        ),
      );

  Widget _body() {
    final status = _remotes.isEmpty
        ? (_joined ? 'جارٍ الرنين...' : 'جارٍ الاتصال...')
        : mmss(_seconds);
    if (_video && _engine != null && _remotes.isNotEmpty) {
      return Stack(children: [
        Positioned.fill(
          child: _remotes.length == 1
              ? _remoteView(_remotes.first)
              : GridView.count(
                  crossAxisCount: 2,
                  children: [for (final u in _remotes) _remoteView(u)],
                ),
        ),
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Column(children: [
            Text(widget.title,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
            Text(status, style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        if (!_camOff)
          Positioned.directional(
            textDirection: Directionality.of(context),
            end: 16,
            bottom: 16,
            child: SizedBox(
              width: 110,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AgoraVideoView(
                  controller: VideoViewController(
                      rtcEngine: _engine!, canvas: const VideoCanvas(uid: 0)),
                ),
              ),
            ),
          ),
      ]);
    }
    // صوت، أو فيديو قبل انضمام الطرف الآخر
    return Stack(children: [
      if (_video && _engine != null && !_camOff)
        Positioned.fill(
          child: AgoraVideoView(
            controller: VideoViewController(
                rtcEngine: _engine!, canvas: const VideoCanvas(uid: 0)),
          ),
        ),
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: Colors.white24,
            child: Text(
              widget.title.isEmpty ? '?' : widget.title.characters.first,
              style: const TextStyle(fontSize: 44, color: Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          Text(widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(_error ?? status,
              textAlign: TextAlign.center,
              style: TextStyle(color: _error != null ? Colors.redAccent : Colors.white70)),
        ]),
      ),
    ]);
  }

  Widget _btn(IconData icon, VoidCallback onTap, {bool on = false, Color? bg}) => InkResponse(
        onTap: onTap,
        child: CircleAvatar(
          radius: 28,
          backgroundColor: bg ?? (on ? Colors.white : Colors.white24),
          child: Icon(icon, color: bg != null ? Colors.white : (on ? Colors.black87 : Colors.white)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1B2A2A),
        body: SafeArea(
          child: Column(children: [
            Expanded(child: _body()),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _btn(_muted ? Icons.mic_off : Icons.mic, () {
                  setState(() => _muted = !_muted);
                  _engine?.muteLocalAudioStream(_muted);
                }, on: _muted),
                if (_video)
                  _btn(_camOff ? Icons.videocam_off : Icons.videocam, () {
                    setState(() => _camOff = !_camOff);
                    _engine?.muteLocalVideoStream(_camOff);
                  }, on: _camOff),
                if (_video) _btn(Icons.cameraswitch, () => _engine?.switchCamera()),
                _btn(_speaker ? Icons.volume_up : Icons.volume_down, () {
                  setState(() => _speaker = !_speaker);
                  _engine?.setEnableSpeakerphone(_speaker);
                }, on: _speaker),
                _btn(Icons.call_end, _hangUp, bg: Colors.red),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
