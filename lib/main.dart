import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_colors.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';
import 'utils.dart';
import 'welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // يقرأ الإعدادات من google-services.json
  await initializeDateFormatting('ar');
  runApp(const HaiApp());
}

ThemeData _theme(Brightness b) {
  final light = b == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: b),
    appBarTheme: AppBarTheme(
      backgroundColor: light ? AppColors.primary : AppColors.darkBar,
      foregroundColor: Colors.white,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
    ),
  );
}

class HaiApp extends StatelessWidget {
  const HaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HaiApp',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const AuthGate(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset('assets/icon/icon.png', width: 120, height: 120),
        ),
      ),
    );
  }
}

/// 1) غير مسجل: ترحيب ← تسجيل
/// 2) مسجل بدون ملف شخصي: إعداد الملف
/// 3) مسجل وجاهز: الشاشة الرئيسية
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        final user = snap.data;
        if (user == null) return const LoggedOutFlow();
        return ProfileGate(uid: user.uid);
      },
    );
  }
}

class LoggedOutFlow extends StatefulWidget {
  const LoggedOutFlow({super.key});

  @override
  State<LoggedOutFlow> createState() => _LoggedOutFlowState();
}

class _LoggedOutFlowState extends State<LoggedOutFlow> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return _accepted
        ? const AuthScreen()
        : WelcomeScreen(onContinue: () => setState(() => _accepted = true));
  }
}

class ProfileGate extends StatefulWidget {
  final String uid;
  const ProfileGate({super.key, required this.uid});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stream =
      fs.collection('users').doc(widget.uid).snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const SplashScreen();
        final d = snap.data!.data();
        final hasName = (d?['name'] ?? '').toString().trim().isNotEmpty;
        return hasName ? const HomeScreen() : const ProfileSetupScreen();
      },
    );
  }
}
