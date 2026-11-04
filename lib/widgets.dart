import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'utils.dart';

class Avatar extends StatelessWidget {
  final String? photo;
  final String name;
  final double radius;
  final bool isGroup;
  const Avatar({
    super.key,
    this.photo,
    required this.name,
    this.radius = 24,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    if (photo != null && photo!.isNotEmpty) {
      return CircleAvatar(
          radius: radius, backgroundImage: MemoryImage(decodePhoto(photo!)));
    }
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: isGroup
          ? Icon(Icons.group, size: radius)
          : Text(initial(name), style: TextStyle(fontSize: radius * 0.8)),
    );
  }
}

/// يبني واجهة من مستند المستخدم (اسم، صورة، حالة...) بشكل لحظي
class UserBuilder extends StatefulWidget {
  final String uid;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;
  const UserBuilder({super.key, required this.uid, required this.builder});

  @override
  State<UserBuilder> createState() => _UserBuilderState();
}

class _UserBuilderState extends State<UserBuilder> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _stream = _make();

  Stream<DocumentSnapshot<Map<String, dynamic>>> _make() =>
      fs.collection('users').doc(widget.uid).snapshots();

  @override
  void didUpdateWidget(covariant UserBuilder old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _stream = _make();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) =>
          widget.builder(context, snap.data?.data() ?? const {}),
    );
  }
}

class UserAvatar extends StatelessWidget {
  final String uid;
  final double radius;
  const UserAvatar({super.key, required this.uid, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    return UserBuilder(
      uid: uid,
      builder: (_, u) => Avatar(
          photo: u['photo'] as String?,
          name: (u['name'] ?? '?').toString(),
          radius: radius),
    );
  }
}
