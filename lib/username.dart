import 'package:cloud_firestore/cloud_firestore.dart';

import 'utils.dart';

final _usernameRe = RegExp(r'^[a-z][a-z0-9_]{3,23}$');

/// يرجع نص الخطأ أو null إن كان الاسم صالحاً
String? validateUsername(String name) {
  if (name.length < 4) return 'يجب أن لا يقل عن 4 أحرف';
  if (name.length > 24) return 'يجب أن لا يزيد عن 24 حرفاً';
  if (!RegExp(r'^[a-z]').hasMatch(name)) return 'يبدأ بحرف إنجليزي';
  if (!_usernameRe.hasMatch(name)) return 'أحرف إنجليزية صغيرة وأرقام وشرطة سفلية _ فقط';
  return null;
}

/// الاسم متاح؟ (أو هو اسمي الحالي)
Future<bool> usernameAvailable(String name) async {
  final d = await fs.collection('usernames').doc(name).get();
  if (!d.exists) return true;
  return d.data()?['uid'] == currentUser.uid;
}

class UsernameTakenException implements Exception {}

/// حجز اسم المستخدم (وتحرير القديم) في عملية واحدة
Future<void> saveUsername(String name) async {
  final uid = currentUser.uid;
  final userRef = fs.collection('users').doc(uid);
  final nameRef = fs.collection('usernames').doc(name);
  await fs.runTransaction((tx) async {
    final taken = await tx.get(nameRef);
    if (taken.exists && taken.data()?['uid'] != uid) throw UsernameTakenException();
    final me = await tx.get(userRef);
    final old = (me.data()?['username'] ?? '').toString();
    if (old == name) return;
    if (old.isNotEmpty) tx.delete(fs.collection('usernames').doc(old));
    tx.set(nameRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
    tx.update(userRef, {'username': name});
  });
}

Future<void> removeUsername() async {
  final uid = currentUser.uid;
  final userRef = fs.collection('users').doc(uid);
  final old = ((await userRef.get()).data()?['username'] ?? '').toString();
  final batch = fs.batch();
  if (old.isNotEmpty) batch.delete(fs.collection('usernames').doc(old));
  batch.update(userRef, {'username': FieldValue.delete()});
  await batch.commit();
}
