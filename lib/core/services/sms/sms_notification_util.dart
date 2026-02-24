import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Utility class for showing local notifications when a transaction is
/// automatically recorded from an incoming SMS.
///
/// Call [initialize] once in `main()` before starting the SMS listener.
class SmsNotificationUtil {
  SmsNotificationUtil._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'sms_tracker_channel';
  static const _channelName = 'SMS Auto-Tracker';
  static const _channelDesc =
      'Notifications for transactions automatically logged from SMS';

  /// Initializes the notification plugin and creates the Android channel.
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(initSettings);

    // Create the notification channel (Android 8+)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.defaultImportance,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _initialized = true;
  }

  /// Shows a status-bar notification informing the user of the auto-logged transaction.
  static Future<void> showTransactionNotification({
    required String type, // 'income' | 'expense'
    required double amount,
    required String category,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    final emoji = type == 'income' ? '💰' : '💸';
    final label = type == 'income' ? 'Income' : 'Expense';
    final amountStr = '₹${amount.toStringAsFixed(2)}';

    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '$emoji Auto-Logged $label',
        '$category · $amountStr recorded from your bank SMS',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[SmsNotificationUtil] Failed to show notification: $e');
    }
  }
}
