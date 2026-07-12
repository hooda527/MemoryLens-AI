import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:memorylens_ai/app_theme.dart';
import 'package:memorylens_ai/screens/dashboard_screen.dart';
import 'package:memorylens_ai/screens/capture_screen.dart';
import 'package:memorylens_ai/screens/settings_screen.dart';
import 'package:memorylens_ai/screens/search_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (safely catch if config options aren't fully linked yet)
  try {
    await Firebase.initializeApp();
    // Auto Sign-In anonymously for hackathon ease
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    debugPrint("Firebase init warning: $e. Using local simulation if offline.");
  }

  // Initialize Window Manager on Desktop
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // Frameless window
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    const ProviderScope(
      child: MemoryLensApp(),
    ),
  );
}

class MemoryLensApp extends StatelessWidget {
  const MemoryLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MemoryLens AI',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: '/dashboard',
      routes: {
        '/dashboard': (_) => const DashboardScreen(),
        '/capture': (_) => const CaptureScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/search': (_) => const SearchScreen(),
      },
    );
  }
}
