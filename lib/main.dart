import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/config/app_secrets.dart';
import 'core/services/sms/sms_listener_service.dart';
import 'core/services/sms/sms_notification_util.dart';
import 'features/ledger/presentation/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file (contains GEMINI_API_KEY)
  await dotenv.load(fileName: '.env');

  // Initialize date formatting
  await initializeDateFormatting();

  // Initialize Supabase
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // Initialize local notifications channel
  await SmsNotificationUtil.initialize();

  // Create a shared ProviderContainer so the SMS service and UI share state.
  // ProviderScope receives this container via the `parent` param below.
  final container = ProviderContainer();

  // Initialize and start the SMS listener (no-op on non-Android platforms).
  SmsListenerService.initialize(container);
  unawaited(SmsListenerService.startListening());

  runApp(ProviderScope(parent: container, child: const CyberFinanceApp()));
}

class CyberFinanceApp extends StatelessWidget {
  const CyberFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stardust - Sci-Fi Finance',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        primaryColor: const Color(0xFF00D9FF), // Cyan
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D9FF), // Cyan
          secondary: Color(0xFF00B8D4), // Darker cyan
          background: Color(0xFF0A0E27), // Dark space
          surface: Color(0xFF1A1F3A), // Dark panel
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onBackground: Color(0xFFE0FFFF), // Light cyan
          onSurface: Color(0xFFE0FFFF),
        ),
        textTheme: TextTheme(
          displayLarge: GoogleFonts.orbitron(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFE0FFFF),
            letterSpacing: 2,
          ),
          displayMedium: GoogleFonts.orbitron(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFE0FFFF),
            letterSpacing: 1.5,
          ),
          titleLarge: GoogleFonts.orbitron(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF00D9FF),
            letterSpacing: 1,
          ),
          bodyLarge: GoogleFonts.roboto(
            fontSize: 16,
            color: const Color(0xFFE0FFFF),
          ),
          bodyMedium: GoogleFonts.roboto(
            fontSize: 14,
            color: const Color(0xFFBBDEFF),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF0A0E27),
          elevation: 0,
          titleTextStyle: GoogleFonts.orbitron(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF00D9FF),
            letterSpacing: 1,
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}
