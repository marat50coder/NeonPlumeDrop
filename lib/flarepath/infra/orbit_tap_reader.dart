import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class OrbitTapReader {
  static const String dartKey = 'plume_orbit_tap';

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
}
