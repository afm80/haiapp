import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_colors.dart';
import 'auth_screen.dart';
import 'google_config.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';
import 'utils.dart';

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
    scaffoldBackgroundColor: light ? AppColors.bgLight : AppColors.bgDark,
    textTheme: GoogleFonts.cairoTextTheme(ThemeData(brightness: b).textTheme).apply(
      bodyColor: light ? AppColors.textLight : AppColors.textDark,
      displayColor: light ? AppColors.textLight : AppColors.textDark,
    ),
    iconTheme: IconThemeData(color: light ? AppColors.textLight : AppColors.textDark),
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: b).copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      surface: light ? AppColors.bgLight : AppColors.bgDark,
      onSurface: light ? AppColors.textLight : AppColors.textDark,
      onSurfaceVariant: light ? AppColors.mutedLight : AppColors.mutedDark,
      surfaceContainerLowest: light ? AppColors.bgLight : AppColors.bgDark,
      surfaceContainerLow: light ? AppColors.bgLight : AppColors.bgDark,
      surfaceContainer: light ? const Color(0xFFEDEBE8) : AppColors.panelDark,
      surfaceContainerHigh: light ? const Color(0xFFE6E4E0) : const Color(0xFF262B36),
      surfaceContainerHighest: light ? const Color(0xFFE0DEDA) : const Color(0xFF2E3544),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent, foregroundColor: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent, foregroundColor: Colors.white),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primary,
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
      title: 'HaiChat',
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

/// 1) غير مسجل: شاشة واحدة (ترحيب + دخول Google)
/// 2) مسجل بدون ملف شخصي أو بدون رقم موبايل: إعداد الملف
/// 3) مسجل وجاهز: الشاشة الرئيسية
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // إن ضاعت الجلسة عند فتح التطبيق نحاول الدخول بصمت بحساب Google المحفوظ
  bool _trying = true;

  @override
  void initState() {
    super.initState();
    _silent();
  }

  Future<void> _silent() async {
    try {
      // ننتظر حالة الدخول المحفوظة أولاً
      final first = await FirebaseAuth.instance.authStateChanges().first;
      if (first == null) {
        final gs = GoogleSignIn(scopes: ['email'], serverClientId: kGoogleWebClientId);
        final acc = await gs.signInSilently();
        if (acc != null) {
          final auth = await acc.authentication;
          if (auth.idToken != null) {
            await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(
                accessToken: auth.accessToken, idToken: auth.idToken));
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _trying = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        final user = snap.data;
        if (user == null) return _trying ? const SplashScreen() : const LoggedOutFlow();
        return ProfileGate(uid: user.uid);
      },
    );
  }
}

class LoggedOutFlow extends StatelessWidget {
  const LoggedOutFlow({super.key});

  @override
  Widget build(BuildContext context) => const AuthScreen();
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
        final hasPhone = (d?['phone'] ?? '').toString().trim().isNotEmpty;
        return (hasName && hasPhone) ? const HomeScreen() : const ProfileSetupScreen();
      },
    );
  }
}
