import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/flare_config.dart';
import '../core/flare_log.dart';
import 'orbit_agent.dart';

class OrbitAttribution {
  OrbitAttribution(this._agent);

  final OrbitAgent _agent;
  AppsflyerSdk? _sdk;
  Map<String, dynamic>? _install;
  Map<String, dynamic>? _reopen;
  Map<String, dynamic>? _deepLink;
  String? campaignFallbackUrl;
  Future<void>? _startFuture;
  Future<void>? _consentFuture;
  final Completer<void> _installReady = Completer<void>();
  final Completer<void> _deepLinkReady = Completer<void>();

  Future<void> start() => _startFuture ??= _start();

  /// True after AppsFlyer (or GCD) actually set `af_status`.
  /// An identity-only POST must not commit the tester to the native game.
  bool get hasConversionVerdict {
    final status = _install?['af_status']?.toString() ?? '';
    return status.isNotEmpty;
  }

  bool get isFirstLaunch {
    final raw = _install?['is_first_launch'];
    return raw == true || raw.toString() == 'true' || raw.toString() == '1';
  }

  bool get isOrganic {
    return _install?['af_status']?.toString() == 'Organic';
  }

  /// Consent is its own memoized future — not the SDK start — so a lost
  /// prompt during a route change can be retried after the app is frontmost.
  Future<void> ensureConsent() => _consentFuture ??= _askConsent();

  Future<void> _start() async {
    if (!FlareConfig.grayCredentialsReady) {
      _completeEmpty();
      return;
    }
    try {
      // Same boot as Featherfield / Embercrest: ATT, then initSdk with no
      // manualStart and IDFA left on. Simulator ATT is usually denied —
      // disableAdvertisingIdentifier there made AF drop the App Store
      // click and lock Organic. timeToWait lets the SDK attach IDFA if
      // the user taps Allow a moment later.
      await ensureConsent();
      final sdk = AppsflyerSdk(
        AppsFlyerOptions(
          afDevKey: FlareConfig.appsFlyerKey,
          appId: FlareConfig.iosStoreId,
          showDebug: kDebugMode,
          timeToWaitForATTUserAuthorization: 60,
        ),
      );
      _sdk = sdk;
      sdk.onInstallConversionData(_acceptInstall);
      sdk.onAppOpenAttribution((raw) {
        _reopen = _flat(raw);
        if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
      });
      sdk.onDeepLinking((result) {
        final event = result.deepLink?.clickEvent;
        flareTrace(
          () => '[NPD.ORBIT] udl status=${result.status} '
              'keys=${event?.keys.toList()}',
        );
        if (event != null && event.isNotEmpty) {
          _deepLink = Map<String, dynamic>.from(event);
        }
        if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
      });
      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
      // `performOnDeepLinking` is an Android-only channel method in the
      // Flutter plugin. On iOS every cold start threw an unhandled
      // MissingPluginException — the sync `try/catch` couldn't see the
      // MethodChannel Future rejection, so the isolate reported a crash
      // even though the SDK itself was fine. Skip on iOS and treat the
      // Future rejection as no-op elsewhere.
      if (!Platform.isIOS) {
        unawaited(
          Future(() => sdk.performOnDeepLinking()).catchError((_) {}),
        );
      }
      flareTrace(() => '[NPD.ORBIT] init ok');
    } catch (error) {
      flareTrace(() => '[NPD.ORBIT] initialization failed: $error');
      _completeEmpty();
    }
  }

  Future<void> _askConsent() async {
    if (!Platform.isIOS) return;
    var status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status != TrackingStatus.notDetermined) return;
    await _waitUntilFront();
    await Future<void>.delayed(
      const Duration(milliseconds: FlareConfig.attPromptDelayMs),
    );
    status = await AppTrackingTransparency.requestTrackingAuthorization();
    if (status != TrackingStatus.notDetermined) return;
    await _waitUntilFront();
    await AppTrackingTransparency.requestTrackingAuthorization();
  }

  Future<void> _waitUntilFront() async {
    await WidgetsBinding.instance.endOfFrame;
    for (var step = 0; step < 48; step++) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) return;
      await Future<void>.delayed(const Duration(milliseconds: 85));
    }
  }

  Future<void> _acceptInstall(dynamic raw) async {
    try {
      final received = _flat(raw);
      final status = received['status']?.toString().toLowerCase();
      final failed = status == 'failure' ||
          (received['af_status'] == null && received.containsKey('status'));
      flareTrace(
        () => '[NPD.ORBIT] conversion status=$status '
            'af_status=${received['af_status']} keys=${received.keys.toList()}',
      );
      if (failed) {
        _install = <String, dynamic>{};
      } else if (received['af_status'] == 'Organic') {
        _install = await _rescuePaid(received) ?? received;
      } else {
        _install = received;
      }
    } catch (error) {
      flareTrace(() => '[NPD.ORBIT] conversion parse error: $error');
      _install = <String, dynamic>{};
    } finally {
      if (!_installReady.isCompleted) _installReady.complete();
    }
  }

  /// OneLink query (pid, campaign, deep_link_value, …) must reach config even
  /// when AppsFlyer still reports Organic on a reinstall / Xcode build.
  void ingestCampaignUrl(String url) {
    campaignFallbackUrl = url;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final query = Map<String, String>.from(uri.queryParameters);
    if (uri.fragment.contains('=')) {
      query.addAll(Uri.splitQueryString(uri.fragment));
    }
    _deepLink ??= <String, dynamic>{};
    query.forEach((key, value) {
      if (value.isNotEmpty) _deepLink![key] = value;
    });
    if (uri.pathSegments.isNotEmpty) {
      _deepLink!['shortlink'] ??= uri.pathSegments.last;
    }
    final pid = query['pid'];
    if (pid != null && pid.isNotEmpty) {
      _deepLink!['media_source'] = pid;
    }
    final campaign = query['c'];
    if (campaign != null && campaign.isNotEmpty) {
      _deepLink!['campaign'] = campaign;
    }
    flareTrace(
      () => '[NPD.ORBIT] ingested OneLink keys=${_deepLink!.keys.toList()}',
    );
  }

  Map<String, dynamic> _flat(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final map = Map<String, dynamic>.from(raw);
    final payload = map['payload'];
    if (payload is Map) return Map<String, dynamic>.from(payload);
    final out = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is Map) {
        value.forEach((innerKey, innerValue) {
          out['$innerKey'] = innerValue;
        });
      } else {
        out['$key'] = value;
      }
    });
    return out;
  }

  /// First callback is often Organic while the OneLink click is still
  /// settling. Ask GCD again with AF UID and IDFA — the pull API accepts
  /// either as `device_id`. Testers match on IDFA; a UID-only lookup
  /// keeps returning the empty organic row.
  Future<Map<String, dynamic>?> _rescuePaid(
    Map<String, dynamic> organic,
  ) async {
    for (var pass = 0; pass < 3; pass++) {
      await Future<void>.delayed(
        Duration(seconds: FlareConfig.organicRecheckSeconds + pass * 4),
      );
      final gcd = await _fetchGcd();
      flareTrace(
        () => '[NPD.ORBIT] gcd pass=$pass af_status=${gcd?['af_status']} '
            'keys=${gcd?.keys.toList()}',
      );
      if (gcd == null || gcd.isEmpty) continue;
      final status = gcd['af_status']?.toString();
      if (status != null && status.isNotEmpty && status != 'Organic') {
        return gcd;
      }
    }
    return organic;
  }

  Future<String?> _idfa() async {
    if (!Platform.isIOS) return null;
    try {
      if (await AppTrackingTransparency.trackingAuthorizationStatus !=
          TrackingStatus.authorized) {
        return null;
      }
      final idfa = await AppTrackingTransparency.getAdvertisingIdentifier();
      if (idfa.isEmpty || idfa.startsWith('00000000-')) return null;
      return idfa;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchGcd() async {
    final uid = await appsFlyerId();
    final idfa = await _idfa();
    final devices = <String>[
      if (uid != null && uid.isNotEmpty) uid,
      if (idfa != null) idfa,
    ];
    if (devices.isEmpty) return null;
    final base = FlareConfig.gcdBase;
    final sep = base.contains('?') ? '&' : '?';
    final key = FlareConfig.appsFlyerKey;
    final uris = <Uri>[
      for (final device in devices) ...<Uri>[
        Uri.parse(
          '$base${sep}app_id=${FlareConfig.iosStoreId}&device_id=$device'
          '&devkey=$key',
        ),
        Uri.parse(
          '${base}id${FlareConfig.iosStoreId}?device_id=$device&devkey=$key',
        ),
      ],
    ];
    for (final uri in uris) {
      try {
        final response = await _agent
            .get(
              uri,
              headers: <String, String>{
                'Authorization': 'Bearer $key',
              },
            )
            .timeout(const Duration(milliseconds: 14200));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded.isEmpty) continue;
        return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  Future<void> awaitSignals({Duration? installTimeout}) async {
    await start();
    await Future.wait<void>(<Future<void>>[
      _installReady.future.timeout(
        installTimeout ??
            const Duration(milliseconds: FlareConfig.installSignalTimeoutMs),
        onTimeout: () {},
      ),
      _deepLinkReady.future.timeout(
        const Duration(milliseconds: 8200),
        onTimeout: () {},
      ),
    ]);
  }

  Future<String?> appsFlyerId() async {
    try {
      return await _sdk?.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> compose({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    if (_install != null) body.addAll(_install!);
    if (_reopen != null) {
      _reopen!.forEach((key, value) => body.putIfAbsent(key, () => value));
    }
    if (_deepLink != null) {
      _deepLink!.forEach((key, value) {
        if (value == null) return;
        // AppsFlyer UDL payload frequently carries the FULL click schema
        // with EMPTY strings for fields the click didn't fill (campaign,
        // media_source, af_sub1…). If we merge those over `_install` we
        // wipe the real values that `onInstallConversionData` just gave
        // us and the partner sees `sub_id_1=""`, showing its "params
        // mismatch" placeholder instead of the real offer. Only accept a
        // non-empty deep-link value, and never let it downgrade an
        // already-filled install field.
        final text = value.toString().trim();
        if (text.isEmpty) return;
        // Conversion / GCD owns the paid verdict. Do not overwrite it
        // from a URL we parsed ourselves.
        if (key == 'af_status' || key == 'af_message') return;
        final existing = body[key];
        if (existing != null && existing.toString().trim().isNotEmpty) {
          return;
        }
        body[key] = value;
      });
    }

    body['af_id'] = await appsFlyerId() ?? body['af_id'] ?? '';
    body['bundle_id'] = FlareConfig.bundleId;
    body['os'] = 'iOS';
    body['store_id'] = FlareConfig.storeToken;
    body['locale'] = locale;
    _maskTablet(body);
    if (pushToken != null &&
        pushToken.isNotEmpty &&
        FlareConfig.firebaseProjectNumber.isNotEmpty) {
      body['push_token'] = pushToken;
      body['firebase_project_id'] = FlareConfig.firebaseProjectNumber;
    }

    if (Platform.isIOS) {
      try {
        if (await AppTrackingTransparency.trackingAuthorizationStatus ==
            TrackingStatus.authorized) {
          final idfa = await AppTrackingTransparency.getAdvertisingIdentifier();
          if (idfa.isNotEmpty && !idfa.startsWith('00000000-')) {
            body['sub_id_10'] = idfa;
          }
        }
      } catch (_) {}
    }
    flareTrace(() => '[NPD.ORBIT] payload ${jsonEncode(body)}');
    return body;
  }

  /// Partner config drops iPad / tablet rows. AF GCD still forwards
  /// `device_type=iPad` from a real iPad, so the same Non-organic click
  /// that opens gray on iPhone comes back 404 on iPad. Keep the HTTP UA
  /// as iPhone and rewrite the type keys the backend actually reads.
  void _maskTablet(Map<String, dynamic> body) {
    const keys = <String>[
      'device_type',
      'af_device_type',
      'device',
      'model',
      'device_model',
      'hw_model',
    ];
    for (final key in keys) {
      final value = body[key]?.toString().toLowerCase() ?? '';
      if (value.contains('ipad') || value.contains('tablet')) {
        body[key] = 'iPhone';
      }
    }
    body['device_type'] = 'iPhone';
  }

  void _completeEmpty() {
    if (!_installReady.isCompleted) _installReady.complete();
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }
}
