import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'actions.dart';
import 'app_colors.dart';
import 'calls_tab.dart';
import 'chat_actions.dart';
import 'chats_tab.dart';
import 'contacts_screen.dart';
import 'contacts_service.dart';
import 'new_group_screen.dart';
import 'settings_screen.dart';
import 'status_tab.dart';
import 'utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _query = ValueNotifier<String>('');
  final _selection = ValueNotifier<Set<String>>(<String>{});
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _foreground = true;
  Timer? _heartbeat;
  StreamSubscription? _callSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs.addListener(() {
      if (_tabs.index != 0 && _selection.value.isNotEmpty) _selection.value = <String>{};
      setState(() {});
    });
    _selection.addListener(() {
      if (mounted) setState(() {});
    });
    // يطلب إذن جهات الاتصال مرة واحدة ويحمّل أسماءها لعرضها في المحادثات
    unawaited(ContactsService.load().then((_) {}, onError: (_) {}));
    setPresence(true);
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_foreground) setPresence(true);
    });
    _listenForCalls();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setPresence(_foreground);
  }

  void _listenForCalls() {
    _callSub = fs
        .collection('calls')
        .where('calleeIds', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final d = ch.doc.data();
        if (d == null) continue;
        final ts = d['createdAt'] as Timestamp?;
        final fresh =
            ts != null && DateTime.now().difference(ts.toDate()).inSeconds < 40;
        if (d['status'] == 'ringing' && fresh && mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => IncomingCallDialog(callId: ch.doc.id, data: d),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _callSub?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    _query.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _stopSearch() {
    setState(() => _searching = false);
    _searchCtrl.clear();
    _query.value = '';
  }

  bool get _selecting => _selection.value.isNotEmpty;

  void _clearSelection() => _selection.value = <String>{};

  PreferredSizeWidget _selectionBar() {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
      title: Text('${_selection.value.length}'),
      actions: [
        IconButton(
          tooltip: 'تثبيت',
          icon: const Icon(Icons.push_pin_outlined),
          onPressed: () {
            final ids = {..._selection.value};
            _clearSelection();
            toggleChatFlag(ids, 'pinnedBy');
          },
        ),
        IconButton(
          tooltip: 'أرشفة',
          icon: const Icon(Icons.archive_outlined),
          onPressed: () {
            final ids = {..._selection.value};
            _clearSelection();
            toggleChatFlag(ids, 'archivedBy');
          },
        ),
        IconButton(
          tooltip: 'حذف',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ids = {..._selection.value};
            final done = await deleteChatsConfirm(context, ids);
            if (done) _clearSelection();
          },
        ),
      ],
    );
  }

  Widget? _fab() {
    switch (_tabs.index) {
      case 0:
        return FloatingActionButton(
          heroTag: 'fab_chat',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ContactsScreen())),
          child: const Icon(Icons.chat),
        );
      case 1:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'fab_text_status',
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
              onPressed: () => openTextStatusCreator(context),
              child: const Icon(Icons.edit),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'fab_image_status',
              onPressed: () => postImageStatus(context),
              child: const Icon(Icons.photo_camera),
            ),
          ],
        );
      default:
        return FloatingActionButton(
          heroTag: 'fab_call',
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ContactsScreen(mode: ContactsMode.call))),
          child: const Icon(Icons.add_call),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _clearSelection();
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: _selecting
          ? _selectionBar()
          : AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                    hintText: 'بحث...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none),
                onChanged: (v) => _query.value = v.trim(),
              )
            : const Text('HaiApp', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_searching)
            IconButton(icon: const Icon(Icons.close), onPressed: _stopSearch)
          else ...[
            if (_tabs.index == 0)
              IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _searching = true)),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'group') {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const NewGroupScreen()));
                } else if (v == 'settings') {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                } else if (v == 'logout') {
                  signOutUser();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'group', child: Text('مجموعة جديدة')),
                PopupMenuItem(value: 'settings', child: Text('الإعدادات')),
                PopupMenuItem(value: 'logout', child: Text('تسجيل خروج')),
              ],
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppColors.accent,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'المحادثات'),
            Tab(text: 'الحالة'),
            Tab(text: 'المكالمات'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          ChatsTab(query: _query, selection: _selection),
          const StatusTab(),
          const CallsTab(),
        ],
      ),
      floatingActionButton: _fab(),
    );
  }
}

class IncomingCallDialog extends StatefulWidget {
  final String callId;
  final Map<String, dynamic> data;
  const IncomingCallDialog({super.key, required this.callId, required this.data});

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog> {
  Timer? _timeout;

  DocumentReference<Map<String, dynamic>> get _ref =>
      fs.collection('calls').doc(widget.callId);

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 40), () {
      if (!mounted) return;
      _ref.update({'status': 'missed'}).catchError((_) {});
      Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _answer(bool accept) {
    _timeout?.cancel();
    _ref.update({'status': accept ? 'answered' : 'declined'}).catchError((_) {});
    Navigator.pop(context);
    if (accept) {
      joinCall(widget.data['room'] as String, widget.data['type'] == 'video');
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.data['type'] == 'video';
    final isGroupCall = (widget.data['calleeIds'] as List).length > 1;
    return AlertDialog(
      title: Text(video ? 'مكالمة فيديو واردة' : 'مكالمة صوتية واردة'),
      content: Text(
          '${widget.data['callerName'] ?? ''}${isGroupCall ? ' (مجموعة)' : ''} يتصل بك'),
      actions: [
        TextButton(
          onPressed: () => _answer(false),
          child: Text('رفض', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () => _answer(true),
          child: const Text('قبول'),
        ),
      ],
    );
  }
}
