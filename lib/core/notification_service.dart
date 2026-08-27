import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'profile_service.dart';

/// Daily local reminder to come back into a run. Honours the Settings toggle.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int _dailyId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(iOS: ios, macOS: ios),
    );
    _ready = true;
  }

  Future<void> syncWithProfile() async {
    await init();
    if (ProfileService.instance.notificationsEnabled) {
      await enableDailyReminder();
    } else {
      await disable();
    }
  }

  Future<bool> enableDailyReminder() async {
    await init();
    final granted = await _requestPermission();
    if (!granted) {
      await ProfileService.instance.setNotificationsEnabled(false);
      return false;
    }
    await ProfileService.instance.setNotificationsEnabled(true);
    await _plugin.cancel(_dailyId);
    await _plugin.periodicallyShow(
      _dailyId,
      'Neon Plume Drop',
      'The core is pulsing. Shift back into orbit.',
      RepeatInterval.daily,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  }

  Future<void> disable() async {
    await init();
    await _plugin.cancelAll();
    await ProfileService.instance.setNotificationsEnabled(false);
  }

  Future<bool> _requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final result = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return result ?? true;
  }
}
