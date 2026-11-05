import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'call_screen.dart';
import 'contacts_service.dart';
import 'utils.dart';
import 'widgets.dart';

/// شاشة المكالمة الواردة (كاملة) مثل واتساب
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final Map<String, dynamic> data;
  const IncomingCallScreen({super.key, required this.callId, required this.data});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Timer? _timeout;
  Timer? _buzz;
  bool _done = false;

  DocumentReference<Map<String, dynamic>> get _ref => fs.collection('calls').doc(widget.callId);
  bool get _video => widget.data['type'] == 'video';

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 40), () {
      if (!mounted || _done) return;
      _done = true;
      _ref.update({'status': 'missed'}).catchError((_) {});
      Navigator.pop(context);
    });
    HapticFeedback.vibrate();
    _buzz = Timer.periodic(const Duration(milliseconds: 1500), (_) => HapticFeedback.vibrate());
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _buzz?.cancel();
    super.dispose();
  }

  void _answer(bool accept) {
    if (_done) return;
    _done = true;
    _timeout?.cancel();
    _buzz?.cancel();
    _ref.update({'status': accept ? 'answered' : 'declined'}).catchError((_) {});
    final nav = Navigator.of(context);
    final title = (widget.data['callerName'] ?? '').toString();
    if (accept) {
      nav.pushReplacement(MaterialPageRoute(
          builder: (_) => CallScreen(
              room: widget.data['room'] as String, video: _video, title: title)));
    } else {
      nav.pop();
    }
  }

  Widget _round(IconData icon, Color color, String label, VoidCallback onTap) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkResponse(
            onTap: onTap,
            child: CircleAvatar(radius: 34, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 30)),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final callerId = (widget.data['callerId'] ?? '').toString();
    final group = (widget.data['calleeIds'] as List).length > 1;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F2422),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 56),
              Text(_video ? 'مكالمة فيديو واردة' : 'مكالمة صوتية واردة',
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const Spacer(),
              UserBuilder(
                uid: callerId,
                builder: (_, u) {
                  final name = ValueListenableBuilder<Map<String, String>?>(
                    valueListenable: ContactsService.names,
                    builder: (_, names, __) {
                      final n = u.isEmpty
                          ? (widget.data['callerName'] ?? '').toString()
                          : displayNameOf(callerId, u, names);
                      return Text(group ? '$n (مجموعة)' : n,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600));
                    },
                  );
                  return Column(children: [
                    Avatar(
                        photo: u['photo'] as String?,
                        name: (u['name'] ?? widget.data['callerName'] ?? '?').toString(),
                        radius: 70),
                    const SizedBox(height: 22),
                    name,
                  ]);
                },
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _round(Icons.call_end, Colors.red, 'رفض', () => _answer(false)),
                    _round(_video ? Icons.videocam : Icons.call, const Color(0xFF25D366), 'رد',
                        () => _answer(true)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
