import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/auth_storage.dart';
import '../app.dart';
import 'web_notification_helper.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  ProviderContainer? _container;
  bool _initialized = false;

  // Platform getters using platform-agnostic foundation constants
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isMobile => !kIsWeb && (_isAndroid || _isIOS);

  /// Set Riverpod ProviderContainer to enable routing on notification clicks
  void setContainer(ProviderContainer container) {
    _container = container;
  }

  /// Initialize the Notification Service
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone database
    tz.initializeTimeZones();
    try {
      // Default to Asia/Kolkata since the shop (Shree Ganadhish) is in India
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      debugPrint('[NOTIFICATION SYSTEM] Timezone initialized to Asia/Kolkata');
    } catch (e) {
      debugPrint('[NOTIFICATION SYSTEM] Warning setting local timezone location: $e');
    }

    if (kIsWeb) {
      requestWebNotificationPermission();
      _initialized = true;
      debugPrint('[NOTIFICATION SYSTEM] Web notifications initialized.');
      return;
    }

    if (!_isMobile) {
      debugPrint('[NOTIFICATION SYSTEM] Initialization skipped on current platform.');
      _initialized = true;
      return;
    }

    // Android Configuration
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS Configuration (in case of future support)
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    try {
      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      );

      // Create high/max priority channels for Android
      if (_isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        await androidImplementation?.createNotificationChannel(
          const AndroidNotificationChannel(
            'morning_evening_summary',
            'Daily Summaries',
            description: 'Daily Morning and Evening business summaries',
            importance: Importance.high,
          ),
        );

        await androidImplementation?.createNotificationChannel(
          const AndroidNotificationChannel(
            'stock_alerts',
            'Inventory Alerts',
            description: 'Low stock and out-of-stock inventory alerts',
            importance: Importance.max,
          ),
        );

        // Request permission on Android 13+
        await androidImplementation?.requestNotificationsPermission();
      }

      _initialized = true;
      debugPrint('[NOTIFICATION SYSTEM] Local notifications initialized successfully.');
    } catch (e) {
      debugPrint('[NOTIFICATION SYSTEM] Failed to initialize local notifications: $e');
    }
  }

  /// Handles notification click actions
  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('[NOTIFICATION SYSTEM] Notification clicked with payload: $payload');

    if (payload != null && payload.isNotEmpty) {
      final container = _container;
      if (container != null) {
        try {
          final router = container.read(routerProvider);
          // GoRouter push to the target route/screen
          router.push(payload);
        } catch (e) {
          debugPrint('[NOTIFICATION SYSTEM] Router navigation failed: $e');
        }
      } else {
        debugPrint('[NOTIFICATION SYSTEM] ProviderContainer not set. Navigation deferred.');
      }
    }
  }

  /// Show immediate notification
  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (kIsWeb) {
      showWebNotification(title, body);
      return;
    }

    if (!_isMobile) {
      debugPrint('[NOTIFICATION SYSTEM] Immediate Alert (Non-mobile): $title - $body');
      return;
    }

    try {
      await _notificationsPlugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'stock_alerts',
            'Inventory Alerts',
            channelDescription: 'Low stock and out-of-stock inventory alerts',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NOTIFICATION SYSTEM] Error showing notification: $e');
    }
  }

  /// Schedule a daily recurring notification
  Future<void> _scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
  }) async {
    if (!_isMobile) {
      debugPrint('[NOTIFICATION SYSTEM] Schedule Daily (Non-mobile) $hour:$minute: $title');
      return;
    }

    try {
      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduledDate =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

      // If scheduled time is in the past, move it to tomorrow
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'morning_evening_summary',
            'Daily Summaries',
            channelDescription: 'Daily Morning and Evening business summaries',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
      debugPrint(
          '[NOTIFICATION SYSTEM] Scheduled daily notification ID $id at $hour:$minute. Next run: $scheduledDate');
    } catch (e) {
      debugPrint('[NOTIFICATION SYSTEM] Error scheduling notification ID $id: $e');
    }
  }

  /// Sync statistics and schedule notifications
  Future<void> syncWithBackend() async {
    final authStorage = AuthStorage();
    final token = await authStorage.getToken();
    if (token == null || token.trim().isEmpty) {
      debugPrint('[NOTIFICATION SYSTEM] No authorization token. Skipping sync.');
      return;
    }

    debugPrint('[NOTIFICATION SYSTEM] Syncing notification data from backend...');
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );

      // Fetch dashboard and stock details in parallel
      final results = await Future.wait([
        dio.get('/dashboard/stats'),
        dio.get('/stock', queryParameters: {'limit': 100}),
      ]);

      final statsJson = results[0].data as Map<String, dynamic>;
      final stockJson = results[1].data as Map<String, dynamic>;

      await processStatsAndSchedule(statsJson, stockJson);
    } catch (e) {
      debugPrint('[NOTIFICATION SYSTEM] Failed to sync data: $e');
    }
  }

  /// Process data payload, run duplicate rules, and update alarm schedules
  Future<void> processStatsAndSchedule(
      Map<String, dynamic> statsJson, Map<String, dynamic> stockJson) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Future Settings Architecture: check enabled state
    final bool enabled = prefs.getBool('notifications_enabled') ?? true;
    if (!enabled) {
      if (_isMobile) {
        await _notificationsPlugin.cancelAll();
      }
      debugPrint('[NOTIFICATION SYSTEM] Notifications are disabled by user configuration.');
      return;
    }

    final reminders = statsJson['reminders_summary'] ?? {};
    final payments = statsJson['payments'] ?? {};

    // 1. Calculate Summary notification aggregates
    final int dueToday = reminders['due_today'] as int? ?? 0;
    final int overdue = reminders['overdue'] as int? ?? 0;
    final int pendingUdhari = reminders['pending_udhari_recovery'] as int? ?? 0;

    // Follow-ups = standard reminders (WATER_CHECK, SERVICE, WARRANTY) that are due/overdue
    final int followupsPending = (dueToday + overdue) - pendingUdhari;
    final int udhariPaymentsDue = pendingUdhari;
    final int remindersToday = dueToday;

    // --- MORNING SUMMARY SCHEDULING ---
    final morningTitle = "Good Morning";
    final morningBody = "You have:\n"
        "• ${followupsPending < 0 ? 0 : followupsPending} Follow-ups pending\n"
        "• $udhariPaymentsDue Udhari payments due\n"
        "• $remindersToday Reminders today\n"
        "Tap to review.";

    final morningTimeStr = prefs.getString('morning_notification_time') ?? "09:00";
    final morningParts = morningTimeStr.split(":");
    final morningHour = int.tryParse(morningParts[0]) ?? 9;
    final morningMin = int.tryParse(morningParts[1]) ?? 0;

    await _scheduleDailyNotification(
      id: 1,
      title: morningTitle,
      body: morningBody,
      hour: morningHour,
      minute: morningMin,
      payload: "/dashboard",
    );

    // --- EVENING BUSINESS CHECK SCHEDULING ---
    final double collectionsToday = (payments['today_collections'] as num?)?.toDouble() ?? 0.0;
    final int salesToday = (statsJson['sales'] != null ? statsJson['sales']['sold_today'] : statsJson['today_total_sales_amount']) as int? ?? 0;
    final double pendingUdhariAmt = (statsJson['today_total_pending'] as num?)?.toDouble() ?? 0.0;

    final eveningTitle = "Daily Business Check";
    final eveningBody = "Review today's:\n"
        "• Collections: ₹${collectionsToday.toStringAsFixed(0)}\n"
        "• Sales: $salesToday sold\n"
        "• Pending Udhari: ₹${pendingUdhariAmt.toStringAsFixed(0)}\n"
        "• Follow-ups: ${followupsPending < 0 ? 0 : followupsPending} pending";

    final eveningTimeStr = prefs.getString('evening_notification_time') ?? "19:00";
    final eveningParts = eveningTimeStr.split(":");
    final eveningHour = int.tryParse(eveningParts[0]) ?? 19;
    final eveningMin = int.tryParse(eveningParts[1]) ?? 0;

    await _scheduleDailyNotification(
      id: 2,
      title: eveningTitle,
      body: eveningBody,
      hour: eveningHour,
      minute: eveningMin,
      payload: "/dashboard",
    );

    // --- IMMEDIATE ALERTS SHOWN ONCE PER DAY ---
    final DateTime now = DateTime.now();
    final String todayDateStr =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // Today's Follow-up Warning
    if (followupsPending > 0) {
      final String fupKey = "last_shown_date_followups";
      if (prefs.getString(fupKey) != todayDateStr) {
        await showImmediateNotification(
          id: 3,
          title: "Today's Follow-ups",
          body: "You have $followupsPending customers scheduled for follow-up today.",
          payload: "/follow-ups",
        );
        await prefs.setString(fupKey, todayDateStr);
      }
    }

    // Today's Udhari Payment Warning
    if (udhariPaymentsDue > 0) {
      final String udhariKey = "last_shown_date_udhari";
      if (prefs.getString(udhariKey) != todayDateStr) {
        await showImmediateNotification(
          id: 4,
          title: "Udhari Collection Reminder",
          body: "$udhariPaymentsDue customers have payments due today.",
          payload: "/follow-ups?tab=udhari",
        );
        await prefs.setString(udhariKey, todayDateStr);
      }
    }

    // --- LOW STOCK & OUT OF STOCK DYNAMIC STATE MACHINE ---
    final int configThreshold = prefs.getInt('low_stock_threshold') ?? 3;
    final List<dynamic> stockList = stockJson['data'] ?? [];
    
    int alertIdOffset = 100;
    for (final item in stockList) {
      final String modelName = item['model_name'] as String? ?? '';
      final int qty = item['quantity'] as int? ?? 0;
      final int itemThreshold = item['low_stock_threshold'] as int? ?? configThreshold;

      if (modelName.isEmpty) continue;

      final String lowAlertKey = "stock_alert_low_$modelName";
      final String outAlertKey = "stock_alert_out_$modelName";

      if (qty == 0) {
        final bool alreadyAlertedOut = prefs.getBool(outAlertKey) ?? false;
        if (!alreadyAlertedOut) {
          await showImmediateNotification(
            id: alertIdOffset++,
            title: "Out Of Stock",
            body: "$modelName is completely out of stock.",
            payload: "/stock",
          );
          await prefs.setBool(outAlertKey, true);
          await prefs.setBool(lowAlertKey, false); // clear low alert so it resets when stock grows and falls again
        }
      } else if (qty <= itemThreshold) {
        final bool alreadyAlertedLow = prefs.getBool(lowAlertKey) ?? false;
        if (!alreadyAlertedLow) {
          await showImmediateNotification(
            id: alertIdOffset++,
            title: "Low Stock Alert",
            body: "$modelName stock is running low ($qty remaining).",
            payload: "/stock",
          );
          await prefs.setBool(lowAlertKey, true);
          await prefs.setBool(outAlertKey, false); // clear out of stock state
        }
      } else {
        // Quantity exceeds threshold. Reset alerts so we can trigger again when stock drops later.
        await prefs.remove(lowAlertKey);
        await prefs.remove(outAlertKey);
      }
    }
  }
}
