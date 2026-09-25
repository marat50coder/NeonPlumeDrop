import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrbitTapReader {
  /// Universal Link / URL scheme tap (may be OneLink → campaign filter).
  static const String dartKey = 'plume_orbit_tap';
  /// Cold-start push notification tap. ALWAYS a destination — never
  /// routed through the AppsFlyer campaign filter, even if it happens
  /// to be a OneLink URL sent through FCM.
  static const String pushKey = 'plume_orbit_push';
  static const String coldNotifKey = 'plume_orbit_cold_notification';
  static const String coldNotifDumpKey =
      'plume_orbit_cold_notification_dump';

  /// Native channel that reads directly from Swift memory / UserDefaults
  /// with no `shared_preferences` cache in the way. Firebase's own
  /// `getInitialMessage()` becomes unreliable after ~10s of the app
  /// being killed, so we go straight to what SceneDelegate captured.
  static const MethodChannel _pushChannel = MethodChannel('npd/push');

  static Future<String?> consume() async {
    if (!Platform.isIOS) return null;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final value = preferences.getString(dartKey)?.trim();
      if (value == null || value.isEmpty) return null;
      await preferences.remove(dartKey);
      return value;
    } catch (_) {
      return null;
    }
  }

  /// Consume a cold-start PUSH notification URL. Callers must treat the
  /// result as a destination and open it as-is, regardless of host.
  ///
  /// Tries the native `npd/push` channel first (reads Swift memory or
  /// UserDefaults directly — bypasses the SharedPreferences in-process
  /// cache) and falls back to SharedPreferences for backwards
  /// compatibility with older AppDelegate builds still installed on the
  /// device.
  static Future<String?> consumePushTap() async {
    if (!Platform.isIOS) return null;
    try {
      final native = await _pushChannel.invokeMethod<String>('consume');
      if (native != null && native.trim().isNotEmpty) {
        return native.trim();
      }
    } catch (_) {}
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final value = preferences.getString(pushKey)?.trim();
      if (value == null || value.isEmpty) return null;
      await preferences.remove(pushKey);
      return value;
    } catch (_) {
      return null;
    }
  }

  /// True when SceneDelegate flagged a cold-start-from-notification.
  /// Consumed once so lifecycle resumes on the same session do not
  /// trip the "wait for late URL" branch again.
  static Future<bool> consumeColdNotificationFlag() async {
    if (!Platform.isIOS) return false;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final flag = preferences.getBool(coldNotifKey) ?? false;
      if (flag) await preferences.remove(coldNotifKey);
      return flag;
    } catch (_) {
      return false;
    }
  }

  /// Full JSON of the payload iOS delivered when SceneDelegate could not
  /// find a URL in the push. Useful only for logs — safe to drop after.
  static Future<String?> consumeColdNotificationDump() async {
    if (!Platform.isIOS) return null;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final value = preferences.getString(coldNotifDumpKey);
      if (value != null) await preferences.remove(coldNotifDumpKey);
      return value;
    } catch (_) {
      return null;
    }
  }
}
