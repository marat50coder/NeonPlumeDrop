import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'profile_service.dart';

/// Daily local reminder to come back into a run. Honours the Settings toggle.
///
/// Also doubles as the local-notification presenter for foreground data-only
/// FCM pushes — iOS suppresses banners for pushes that carry no `notification`
/// block, so `FlarePulse.onMessage` asks us to raise one manually so the user
/// still sees the alert and can tap it to open the URL.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int _dailyId = 1001;
  static const int _pushBannerBaseId = 2000;

  /// Fired when the user taps a local banner we raised on behalf of a data
  /// -only push. Payload is the URL extracted from the FCM `data` map.
  void Function(String url)? onPushBannerTap;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _bannerCounter = 0;

  Future<void> init() async {
    if (_ready) return;
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(iOS: ios, macOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        onPushBannerTap?.call(payload);
      },
    );
    _ready = true;
  }

  /// Raise a local banner mirroring a data-only foreground push. The tap
  /// handler routes to [url] through [onPushBannerTap] so the WebView opens
  /// the same destination it would from a normal notification tap.
  Future<void> showPushBanner({
    required String title,
    required String body,
    required String url,
  }) async {
    if (url.isEmpty) return;
    await init();
    _bannerCounter++;
    final id = _pushBannerBaseId + (_bannerCounter & 0x0FFF);
    await _plugin.show(
      id,
      title.isEmpty ? 'Neon Plume Drop' : title,
      body,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: url,
    );
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
