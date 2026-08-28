import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../config/flare_config.dart';
import '../core/flare_log.dart';
import 'plume_vault.dart';

@pragma('vm:entry-point')
Future<void> flareBackgroundPulse(RemoteMessage _) async {}

/// Firebase Messaging + APNs. Three OS entry points, all funneled into
/// `_dispatch` — same contract as Bolt-of-Aether `BoltPulse`:
///
///   1. Terminated → tap:
///      • primary — SceneDelegate writes UserDefaults; OrbitTapReader
///        consumes FIRST in FlareRouter.decide;
///      • fallback — `getInitialMessage()` inside `boot()` (stashed so
///        decide can `consumePushUrl` before choosing a landing).
///   2. Backgrounded → tap: `onMessageOpenedApp` (registered
///      SYNCHRONOUSLY at the start of boot).
///   3. Foreground banner tap: also `onMessageOpenedApp`. A passive
///      `onMessage` arrival must NOT navigate.
class FlarePulse {
  FlarePulse(this._vault, {required this.enabled});

  final PlumeVault _vault;
  final bool enabled;
  FirebaseMessaging? _messaging;
  Future<void>? _bootFuture;
  Future<bool>? _permissionFuture;
  String? _token;

  void Function(String url)? onDestination;
  void Function(String token)? onTokenChanged;

  String? get token => _token;

  Future<void> boot() => _bootFuture ??= _boot();

  Future<void> _boot() async {
    flareTrace(() => '[NPD.pulse] boot start (enabled=$enabled)');
    if (!enabled) return;

    final messaging = FirebaseMessaging.instance;
    _messaging = messaging;

    // Listeners FIRST so a tap that arrives while getInitialMessage is
    // still resolving is not dropped on a broadcast with no subscribers.
    try {
      FirebaseMessaging.onBackgroundMessage(flareBackgroundPulse);
    } catch (_) {}

    try {
      FirebaseMessaging.onMessage.listen((msg) {
        flareTrace(() => '[NPD.pulse] onMessage fg payload=${msg.data}');
      });
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        flareTrace(() => '[NPD.pulse] onMessageOpenedApp payload=${msg.data}');
        final url = _extract(msg.data);
        if (url != null) {
          flareTrace(() => '[NPD.pulse] onMessageOpenedApp url=$url');
          unawaited(_dispatch(url));
        } else {
          flareTrace(() => '[NPD.pulse] onMessageOpenedApp: no url in payload');
        }
      });
      messaging.onTokenRefresh.listen(_rememberToken);
    } catch (error) {
      flareTrace(() => '[NPD.pulse] listener wiring failed: $error');
    }

    try {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    unawaited(_claimToken(messaging));

    try {
      final initial = await messaging.getInitialMessage().timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
      if (initial == null) {
        flareTrace(() => '[NPD.pulse] getInitialMessage=null');
      } else {
        flareTrace(() => '[NPD.pulse] getInitialMessage payload=${initial.data}');
        final url = _extract(initial.data);
        if (url != null) {
          flareTrace(() => '[NPD.pulse] getInitialMessage url=$url');
          await _vault.stashPushUrl(url);
        } else {
          flareTrace(() => '[NPD.pulse] getInitialMessage: no url in payload');
        }
      }
    } catch (error) {
      flareTrace(() => '[NPD.pulse] getInitialMessage failed: $error');
    }

    flareTrace(() => '[NPD.pulse] boot complete');
  }

  /// Persist FIRST, then the live callback. Covers the race where a
  /// background tap resumes after the current WebView was torn down.
  Future<void> _dispatch(String url) async {
    if (url.isEmpty) return;
    try {
      await _vault.stashPushUrl(url);
    } catch (_) {}
    final callback = onDestination;
    if (callback != null) {
      flareTrace(() => '[NPD.pulse] dispatch → live callback');
      try {
        callback(url);
      } catch (_) {}
    } else {
      flareTrace(() => '[NPD.pulse] dispatch → vault (no live cb)');
    }
  }

  Future<void> _claimToken(
    FirebaseMessaging messaging, {
    int? attempts,
    int? stepMs,
  }) async {
    try {
      await _waitForApns(attempts: attempts, stepMs: stepMs);
      final value = await messaging.getToken();
      if (value != null && value.isNotEmpty) _rememberToken(value);
    } catch (_) {}
  }

  void _rememberToken(String value) {
    if (value.isEmpty) return;
    _token = value;
    onTokenChanged?.call(value);
  }

  /// First non-empty string in known keys, plus one level of nested
  /// `data` / `payload`. No scheme filter, no last-resort `://` scan.
  /// `click_url` is first — partner pnsynd payloads use that key.
  static const List<String> _urlKeys = <String>[
    'click_url',
    'clickUrl',
    'target',
    'url',
    'deep_link',
    'link',
    'deeplink',
    'destination',
  ];
  static const List<String> _urlContainers = <String>['data', 'payload'];

  String? _extract(Map<String, dynamic> payload) {
    for (final key in _urlKeys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    for (final container in _urlContainers) {
      final nested = payload[container];
      if (nested is Map) {
        final found = _extract(Map<String, dynamic>.from(nested));
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<void> _waitForApns({int? attempts, int? stepMs}) async {
    if (!Platform.isIOS) return;
    final messaging = _messaging;
    if (messaging == null) return;
    final tries = attempts ?? FlareConfig.apnsPollTries;
    final pause = stepMs ?? FlareConfig.apnsPollStepMs;
    for (var attempt = 0; attempt < tries; attempt++) {
      try {
        if ((await messaging.getAPNSToken())?.isNotEmpty ?? false) return;
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: pause));
    }
  }

  Future<bool> canOfferPermission() async {
    if (!enabled || _vault.pushDeniedByOs) return false;
    try {
      await boot();
    } catch (_) {}
    final messaging = _messaging ?? FirebaseMessaging.instance;
    _messaging ??= messaging;
    final status =
        (await messaging.getNotificationSettings()).authorizationStatus;
    if (status == AuthorizationStatus.denied) {
      await _vault.markPushDeniedByOs();
      return false;
    }
    return status == AuthorizationStatus.notDetermined ||
        status == AuthorizationStatus.provisional;
  }

  Future<bool> askPermission() {
    return _permissionFuture ??= _performPermissionRequest().whenComplete(
      () => _permissionFuture = null,
    );
  }

  Future<bool> _performPermissionRequest() async {
    if (!enabled) return false;
    try {
      await boot();
    } catch (_) {}
    final messaging = _messaging;
    if (messaging == null) return false;
    final result = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final accepted =
        result.authorizationStatus == AuthorizationStatus.authorized ||
        result.authorizationStatus == AuthorizationStatus.provisional;
    await _vault.setPushAllowed(accepted);
    if (!accepted && result.authorizationStatus == AuthorizationStatus.denied) {
      await _vault.markPushDeniedByOs();
    }
    if (accepted) {
      await _claimToken(messaging, attempts: 14, stepMs: 710);
    }
    return accepted;
  }
}
