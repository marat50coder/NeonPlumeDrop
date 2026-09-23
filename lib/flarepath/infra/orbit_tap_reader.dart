import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class OrbitTapReader {
  static const String dartKey = 'plume_orbit_tap';
  static const String coldNotifKey = 'plume_orbit_cold_notification';
  static const String coldNotifDumpKey =
      'plume_orbit_cold_notification_dump';

  static Future<String?> consume() async {
    if (!Platform.isIOS) return null;
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(dartKey)?.trim();
      if (value == null || value.isEmpty) return null;
      await preferences.remove(dartKey);
      return value;
    } catch (_) {
      return null;
    }
  }

  /// True when iOS woke the app up from a notification tap on this cold
  /// start. Consumed once so lifecycle resumes on the same session do not
  /// trip the "wait for late URL" branch again.
  static Future<bool> consumeColdNotificationFlag() async {
    if (!Platform.isIOS) return false;
    try {
      final preferences = await SharedPreferences.getInstance();
      final flag = preferences.getBool(coldNotifKey) ?? false;
      if (flag) await preferences.remove(coldNotifKey);
      return flag;
    } catch (_) {
      return false;
    }
  }

  /// Full JSON of the payload iOS delivered when SceneDelegate could not
  /// find a URL in the push. Useful only for the log — safe to drop after
  /// reading.
  static Future<String?> consumeColdNotificationDump() async {
    if (!Platform.isIOS) return null;
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(coldNotifDumpKey);
      if (value != null) await preferences.remove(coldNotifDumpKey);
      return value;
    } catch (_) {
      return null;
    }
  }
}
