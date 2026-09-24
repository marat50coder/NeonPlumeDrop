import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/notification_service.dart';
import '../config/flare_config.dart';
import '../core/flare_log.dart';
import 'orbit_tap_reader.dart';
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
  /// Used when `onDestination` is not claimed by a live portal — e.g. the
  /// user is in the native game and a background push tap wakes the app.
  /// The router (or the top-level app) sets this so that a `_dispatch`
  /// that would otherwise vanish still opens the intended URL.
  void Function(String url)? onDestinationFallback;
  void Function(String token)? onTokenChanged;

  String? get token => _token;

  /// Completes the first time a push URL is stashed via `_dispatch`.
  /// `_boot()` awaits this on cold-start-from-notification launches so the
  /// router never proceeds to config while Firebase is still delivering
  /// the tap payload via `onMessageOpenedApp`.
  Completer<void>? _lateTapWaiter;

  Future<void> boot() => _bootFuture ??= _boot();

  Future<void> _boot() async {
    flareTrace(() => '[NPD.pulse] boot start (enabled=$enabled)');
    if (!enabled) return;
    if (Firebase.apps.isEmpty) {
      flareTrace(() => '[NPD.pulse] boot skipped — Firebase not ready');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    _messaging = messaging;

    // Listeners FIRST so a tap that arrives while getInitialMessage is
    // still resolving is not dropped on a broadcast with no subscribers.
    try {
      FirebaseMessaging.onBackgroundMessage(flareBackgroundPulse);
    } catch (_) {}

    try {
      NotificationService.instance.onPushBannerTap = (url) {
        flareTrace(() => '[NPD.pulse] local banner tap url=$url');
        unawaited(_dispatch(url));
      };
      unawaited(NotificationService.instance.init());
      FirebaseMessaging.onMessage.listen((msg) {
        flareTrace(() => '[NPD.pulse] onMessage fg payload=${msg.data}');
        _handleForegroundMessage(msg);
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

    // SceneDelegate flags a cold-start-from-notification BEFORE Dart boots.
    // If the flag is set, we know a push tap woke the app and are prepared
    // to wait for its URL — Firebase on iOS occasionally delivers the
    // payload via `onMessageOpenedApp` a beat AFTER getInitialMessage()
    // returns null, which used to cause the router to open config first
    // and the tap URL to arrive too late.
    final coldNotif = await OrbitTapReader.consumeColdNotificationFlag();
    if (coldNotif) {
      final dump = await OrbitTapReader.consumeColdNotificationDump();
      flareTrace(() => '[NPD.pulse] cold notification tap detected');
      if (dump != null && dump.isNotEmpty) {
        flareTrace(() => '[NPD.pulse] cold notification payload=$dump');
      }
    }
    // Always create the waiter so a late `_dispatch` can wake anyone
    // awaiting it. Even without SceneDelegate's flag we sometimes get a
    // tap through `onMessageOpenedApp` — the flag can be missing when
    // Firebase's UNUserNotificationCenter delegate ate the response
    // before the scene connected.
    _lateTapWaiter = Completer<void>();

    // Poll getInitialMessage. Firebase iOS occasionally returns null on
    // the very first call because its internal proxy hasn't stored the
    // message yet — retry with backoff when SceneDelegate confirmed a
    // cold-notification tap. Non-cold-notif launches still probe twice
    // so a stray terminated-tap iOS delivers without setting our flag is
    // still caught.
    await _pollGetInitialMessage(
      messaging,
      retries: coldNotif ? 5 : 2,
    );

    // If getInitialMessage never yielded a URL, give onMessageOpenedApp a
    // window to fire — some iOS launches route the tap through that
    // callback instead of the initial-message API. Wait longer when we
    // know a notification tap woke the app; use a small insurance window
    // otherwise so warm launches do not add extra latency.
    final waiter = _lateTapWaiter;
    if (waiter != null && !waiter.isCompleted) {
      final windowMs = coldNotif ? 3500 : 1200;
      flareTrace(() => '[NPD.pulse] waiting up to ${windowMs}ms for late tap URL');
      await waiter.future.timeout(
        Duration(milliseconds: windowMs),
        onTimeout: () {
          flareTrace(() => '[NPD.pulse] late tap URL never arrived');
        },
      );
    }

    flareTrace(() => '[NPD.pulse] boot complete');
  }

  Future<void> _pollGetInitialMessage(
    FirebaseMessaging messaging, {
    required int retries,
  }) async {
    const List<int> gapsMs = <int>[0, 350, 600, 900, 1200];
    for (var attempt = 0; attempt < retries; attempt++) {
      if (attempt > 0) {
        final gap = gapsMs[attempt < gapsMs.length ? attempt : gapsMs.length - 1];
        await Future<void>.delayed(Duration(milliseconds: gap));
      }
      try {
        final message = await messaging.getInitialMessage().timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
        if (message == null) {
          flareTrace(
            () => '[NPD.pulse] getInitialMessage=null attempt=${attempt + 1}/'
                '$retries',
          );
          continue;
        }
        flareTrace(
          () => '[NPD.pulse] getInitialMessage attempt=${attempt + 1} '
              'payload=${message.data}',
        );
        final url = _extract(message.data);
        if (url != null) {
          flareTrace(() => '[NPD.pulse] getInitialMessage url=$url');
          await _vault.stashPushUrl(url);
          _completeLateTap();
          return;
        }
        flareTrace(
          () => '[NPD.pulse] getInitialMessage: no url in payload '
              '(attempt=${attempt + 1})',
        );
      } catch (error) {
        flareTrace(
          () => '[NPD.pulse] getInitialMessage failed attempt=${attempt + 1}: '
              '$error',
        );
      }
    }
  }

  void _completeLateTap() {
    final waiter = _lateTapWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// iOS suppresses the system banner for data-only pushes even with
  /// `setForegroundNotificationPresentationOptions(alert: true)` — the
  /// alert flag only applies when the payload carries a `notification`
  /// block. Raise a local notification ourselves so a foreground data
  /// -only push (`{data: {url: …}}`) still gives the user something to
  /// tap. If Firebase already handed us a `notification` block, iOS is
  /// showing the banner itself and we must not double it.
  void _handleForegroundMessage(RemoteMessage msg) {
    if (msg.notification != null) return;
    final url = _extract(msg.data);
    if (url == null || url.isEmpty) return;
    final title = _firstNonEmpty(msg.data, const <String>[
      'title',
      'notification_title',
      'aps_title',
    ]);
    final body = _firstNonEmpty(msg.data, const <String>[
      'body',
      'message',
      'text',
      'notification_body',
      'aps_body',
    ]);
    flareTrace(
      () => '[NPD.pulse] foreground data-only push → local banner url=$url',
    );
    unawaited(
      NotificationService.instance.showPushBanner(
        title: title ?? 'Neon Plume Drop',
        body: body ?? '',
        url: url,
      ),
    );
  }

  String? _firstNonEmpty(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  /// Persist FIRST, then the live callback. Covers the race where a
  /// background tap resumes after the current WebView was torn down.
  Future<void> _dispatch(String url) async {
    if (url.isEmpty) return;
    try {
      await _vault.stashPushUrl(url);
    } catch (_) {}
    _completeLateTap();
    final live = onDestination;
    if (live != null) {
      flareTrace(() => '[NPD.pulse] dispatch → live callback');
      try {
        live(url);
      } catch (_) {}
      return;
    }
    final fallback = onDestinationFallback;
    if (fallback != null) {
      flareTrace(() => '[NPD.pulse] dispatch → fallback callback');
      try {
        fallback(url);
      } catch (_) {}
      return;
    }
    flareTrace(() => '[NPD.pulse] dispatch → vault (no live cb)');
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
