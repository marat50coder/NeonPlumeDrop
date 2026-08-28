import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/flare_config.dart';
import '../core/flare_models.dart';

class PlumeVault {
  static const String _laneKey = 'plume.orbit.lane';
  static const String _expiryKey = 'plume.orbit.until';
  static const String _savedAtKey = 'plume.orbit.saved_at';
  static const String _inviteKey = 'plume.orbit.invite.after';
  static const String _permissionKey = 'plume.orbit.push.ok';
  static const String _osDeniedKey = 'plume.orbit.push.blocked';
  static const String _savedUrlKey = 'plume.orbit.dest';
  static const String _pendingUrlKey = 'plume.orbit.hold';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  late SharedPreferences _preferences;

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  OrbitLane get lane => OrbitLane.parse(_preferences.getString(_laneKey));

  Future<void> saveLane(OrbitLane lane) =>
      _preferences.setString(_laneKey, lane.storageValue);

  Future<String?> savedUrl() async {
    try {
      return await _secure.read(key: _savedUrlKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUrl(String url, int? expiresAt) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _secure.write(key: _savedUrlKey, value: url);
      await _preferences.setInt(_savedAtKey, now);
      final expiry = expiresAt ??
          now + FlareConfig.savedUrlExpiryDays * 24 * 60 * 60;
      await _preferences.setInt(_expiryKey, expiry);
    } catch (_) {}
  }

  bool get cachedUrlExpired {
    final expiry = _preferences.getInt(_expiryKey);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiry != null) return now >= expiry;
    final savedAt = _preferences.getInt(_savedAtKey);
    if (savedAt == null) return true;
    return now >= savedAt + FlareConfig.savedUrlExpiryDays * 24 * 60 * 60;
  }

  Future<void> stashPushUrl(String url) async {
    if (url.trim().isEmpty) return;
    try {
      await _secure.write(key: _pendingUrlKey, value: url.trim());
    } catch (_) {}
  }

  Future<String?> consumePushUrl() async {
    try {
      final value = await _secure.read(key: _pendingUrlKey);
      if (value != null) await _secure.delete(key: _pendingUrlKey);
      return value;
    } catch (_) {
      return null;
    }
  }

  bool get pushAllowed => _preferences.getBool(_permissionKey) ?? false;
  bool get pushDeniedByOs => _preferences.getBool(_osDeniedKey) ?? false;

  Future<void> setPushAllowed(bool value) =>
      _preferences.setBool(_permissionKey, value);

  Future<void> markPushDeniedByOs() => _preferences.setBool(_osDeniedKey, true);

  bool get shouldShowPushInvite {
    if (pushAllowed || pushDeniedByOs) return false;
    final after = _preferences.getInt(_inviteKey);
    if (after == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (after - now > FlareConfig.pushSnoozeSeconds) return true;
    return now >= after;
  }

  Future<void> snoozePushInvite(int epochSeconds) =>
      _preferences.setInt(_inviteKey, epochSeconds);
}
