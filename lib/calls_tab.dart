import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'actions.dart';
import 'app_colors.dart';
import 'contacts_service.dart';
import 'utils.dart';
import 'widgets.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = fs
      .collection('calls')
      .where('participants', arrayContains: currentUser.uid)
      .snapshots();

  int _ms(Map<String, dynamic> d) =>
      (d['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
      DateTime.now().millisecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.toList()
          ..sort((a, b) => _ms(b.data()).compareTo(_ms(a.data())));
        if (docs.isEmpty) {
          return const Center(
              child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('لا توجد مكالمات بعد.\nاضغط على الزر لبدء مكالمة.',
                textAlign: TextAlign.center),
          ));
        }
        final shown = docs.take(60).toList();
        return ListView.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) => _tile(context, shown[i].data()),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> d) {
    final uid = currentUser.uid;
    final outgoing = d['callerId'] == uid;
    final video = d['type'] == 'video';
    final callees = List<String>.from(d['calleeIds'] ?? const []);
    final otherId = outgoing ? (callees.isEmpty ? uid : callees.first) : d['callerId'] as String;
    final answered = d['status'] == 'answered';
    final missed = !outgoing && !answered;
    final ts = d['createdAt'] as Timestamp?;

    final statusText = outgoing
        ? (answered ? 'صادرة' : 'لم يتم الرد')
        : (answered ? 'واردة' : 'فائتة');
    final color = missed ? Theme.of(context).colorScheme.error : Colors.grey;
    final icon = outgoing ? Icons.call_made : (missed ? Icons.call_missed : Icons.call_received);

    return UserBuilder(
      uid: otherId,
      builder: (_, u) => ValueListenableBuilder<Map<String, String>?>(
        valueListenable: ContactsService.names,
        builder: (context, names, __) {
          final multi = outgoing && callees.length > 1;
          final shown = displayNameOf(otherId, u, names);
          final name = multi
              ? (d['title'] ?? 'مجموعة').toString()
              : (shown.isNotEmpty
                  ? shown
                  : ((outgoing ? d['title'] : d['callerName']) ?? '').toString());
          return ListTile(
            leading: Avatar(photo: u['photo'] as String?, name: name, radius: 26),
            title: Text(name,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: missed ? Theme.of(context).colorScheme.error : null)),
            subtitle: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text('$statusText · ${ts == null ? '' : '${dayLabel(ts.toDate())} ${hhmm(ts.toDate())}'}'),
              ],
            ),
            trailing: IconButton(
              icon: Icon(video ? Icons.videocam : Icons.call, color: AppColors.primary),
              onPressed: () {
                final targets = outgoing ? callees : [otherId];
                startCall(context, calleeIds: targets, title: name, video: video);
              },
            ),
          );
        },
      ),
    );
  }
}
