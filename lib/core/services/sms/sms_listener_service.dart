import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telephony/telephony.dart';
import 'package:uuid/uuid.dart';
import '../../database/database.dart';
import '../../../features/ledger/expense_provider.dart';
import '../../../features/ledger/income_provider.dart';
import 'gemini_parser.dart';
import 'sms_notification_util.dart';

// ─── Keywords that suggest a financial SMS ────────────────────────────────────

const _kKeywords = [
  'debited',
  'credited',
  'spent',
  'received',
  'withdrawn',
  'transferred',
  'rs.',
  'inr',
  'payment',
  'transaction',
];

bool _isFinancialSms(String body) {
  final lower = body.toLowerCase();
  return _kKeywords.any((kw) => lower.contains(kw));
}

// ─── Background isolate handler (top-level, no Riverpod) ─────────────────────
// This function is called by Android when the app is killed/backgrounded.
// It cannot access the shared ProviderContainer, so it writes directly to
// AppDatabase — data is persisted via shared_preferences and will appear in
// the UI the next time providers rebuild.

@pragma('vm:entry-point')
void backgroundSmsHandler(SmsMessage message) async {
  final body = message.body ?? '';
  if (!_isFinancialSms(body)) return;

  try {
    final transaction = await GeminiParser().parse(body);
    if (transaction == null) return;

    final db = AppDatabase();
    await db.initialize();

    if (transaction.type == 'expense') {
      await db.addExpense(
        Expense(
          id: const Uuid().v4(),
          amount: transaction.amount,
          category: transaction.category,
          isWant: transaction.isWant,
          timestamp: DateTime.now(),
        ),
      );
    } else {
      await db.addIncome(
        Income(
          id: const Uuid().v4(),
          amount: transaction.amount,
          category: transaction.category,
          timestamp: DateTime.now(),
        ),
      );
    }

    await SmsNotificationUtil.initialize();
    await SmsNotificationUtil.showTransactionNotification(
      type: transaction.type,
      amount: transaction.amount,
      category: transaction.category,
    );

    print(
      '[SMS BG] Recorded ${transaction.type}: ₹${transaction.amount} (${transaction.category})',
    );
  } catch (e) {
    print('[SMS BG] Error handling background SMS: $e');
  }
}

// ─── Foreground service ───────────────────────────────────────────────────────

/// Manages SMS listening in the foreground using a shared [ProviderContainer].
///
/// Usage in `main()`:
/// ```dart
/// final container = ProviderContainer();
/// SmsListenerService.initialize(container);
/// unawaited(SmsListenerService.startListening());
/// runApp(ProviderScope(parent: container, ...));
/// ```
class SmsListenerService {
  SmsListenerService._();

  static ProviderContainer? _container;
  static final _telephony = Telephony.instance;
  static bool _listening = false;

  /// Stores the shared [ProviderContainer] so the foreground handler can
  /// update Riverpod state in real time.
  static void initialize(ProviderContainer container) {
    _container = container;
  }

  /// Requests SMS permission and starts listening for incoming messages.
  /// Safe to call multiple times — subsequent calls are no-ops.
  ///
  /// This method is a no-op on non-Android platforms to preserve
  /// cross-platform compatibility.
  static Future<void> startListening() async {
    if (_listening) return;
    // dart:io Platform is not available on Flutter Web — bail out immediately.
    if (kIsWeb || !Platform.isAndroid) {
      print('[SmsListenerService] SMS listening is only supported on Android.');
      return;
    }

    try {
      final granted = await _telephony.requestPhoneAndSmsPermissions ?? false;
      if (!granted) {
        print(
          '[SmsListenerService] SMS permission denied — listener not started.',
        );
        return;
      }

      _telephony.listenIncomingSms(
        onNewMessage: _handleForegroundSms,
        onBackgroundMessage: backgroundSmsHandler,
        listenInBackground: true,
      );

      _listening = true;
      print('[SmsListenerService] SMS listener started.');
    } catch (e) {
      print('[SmsListenerService] Failed to start SMS listener: $e');
    }
  }

  // ── Foreground handler ──────────────────────────────────────────────────────

  static Future<void> _handleForegroundSms(SmsMessage message) async {
    final body = message.body ?? '';
    if (!_isFinancialSms(body)) return;

    try {
      print('[SmsListenerService] Financial SMS detected: "$body"');

      final transaction = await GeminiParser().parse(body);
      if (transaction == null) {
        print('[SmsListenerService] Gemini could not parse SMS — skipping.');
        return;
      }

      final container = _container;
      if (container == null) {
        print(
          '[SmsListenerService] No ProviderContainer — cannot update providers.',
        );
        return;
      }

      if (transaction.type == 'expense') {
        await container
            .read(expenseProvider.notifier)
            .addExpense(
              transaction.amount,
              transaction.category,
              transaction.isWant,
            );
      } else {
        await container
            .read(incomeProvider.notifier)
            .addIncome(transaction.amount, transaction.category);
      }

      await SmsNotificationUtil.showTransactionNotification(
        type: transaction.type,
        amount: transaction.amount,
        category: transaction.category,
      );

      print(
        '[SmsListenerService] Recorded ${transaction.type}: ₹${transaction.amount} (${transaction.category})',
      );
    } catch (e) {
      // Swallow all errors — never interrupt the main app flow
      print('[SmsListenerService] Error handling foreground SMS: $e');
    }
  }
}
