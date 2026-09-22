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
        _reopen = _normalize(_flat(raw));
        if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
      });
      sdk.onDeepLinking((result) {
        final event = result.deepLink?.clickEvent;
        flareTrace(
          () => '[NPD.ORBIT] udl status=${result.status} '
              'keys=${event?.keys.toList()}',
        );
        if (event != null && event.isNotEmpty) {
          _deepLink = _normalize(Map<String, dynamic>.from(event));
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
      final received = _normalize(_flat(raw));
      final status = received['status']?.toString().toLowerCase();
      final failed = status == 'failure' ||
          (received['af_status'] == null && received.containsKey('status'));
      flareTrace(
        () => '[NPD.ORBIT] conversion status=$status '
            'af_status=${received['af_status']} keys=${received.keys.toList()}',
      );
      if (failed) {
        _install ??= <String, dynamic>{};
      } else {
        // A later Organic / thin callback (is_first_launch=0) must not
        // wipe a Non-organic row — that is how campaign / af_sub* vanished
        // from the config POST.
        _install = _preferRicher(_install, received);
        if (!_isPaid(_install) && received['af_status'] == 'Organic') {
          unawaited(_rescuePaidInBackground(received));
        }
      }
    } catch (error) {
      flareTrace(() => '[NPD.ORBIT] conversion parse error: $error');
      _install ??= <String, dynamic>{};
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
    _deepLink = _normalize(<String, dynamic>{
      ...?_deepLink,
      ...query,
    });
    if (uri.pathSegments.isNotEmpty) {
      _deepLink!['shortlink'] ??= uri.pathSegments.last;
    }
    flareTrace(
      () => '[NPD.ORBIT] ingested OneLink keys=${_deepLink!.keys.toList()}',
    );
  }

  Map<String, dynamic> _flat(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final map = Map<String, dynamic>.from(raw);
    final payload = map['payload'] ?? map['data'];
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

  bool _isBlank(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    if (text.isEmpty) return true;
    final lower = text.toLowerCase();
    return lower == 'null' || lower == '<null>' || lower == 'nil';
  }

  bool _isPaid(Map<String, dynamic>? map) {
    final status = map?['af_status']?.toString();
    return status != null && status.isNotEmpty && status != 'Organic';
  }

  /// Drop AF placeholders and copy OneLink aliases (pid → media_source,
  /// c → campaign) so config.php sees the same keys the dashboard uses.
  Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (_isBlank(value)) return;
      out[key] = value;
    });
    void alias(String from, String to) {
      final value = out[from];
      if (_isBlank(value)) return;
      if (_isBlank(out[to])) out[to] = value;
    }

    alias('pid', 'media_source');
    alias('c', 'campaign');
    alias('af_channel', 'media_source');
    alias('af_adset', 'adset');
    alias('af_c_id', 'campaign_id');
    alias('af_siteid', 'siteid');
    return out;
  }

  Map<String, dynamic> _preferRicher(
    Map<String, dynamic>? current,
    Map<String, dynamic> incoming,
  ) {
    if (current == null || current.isEmpty) return incoming;
    if (_isPaid(current) && !_isPaid(incoming)) {
      final merged = Map<String, dynamic>.from(current);
      incoming.forEach((key, value) {
        if (key == 'af_status' || key == 'af_message') return;
        if (_isBlank(merged[key]) && !_isBlank(value)) merged[key] = value;
      });
      return merged;
    }
    final merged = Map<String, dynamic>.from(current);
    incoming.forEach((key, value) {
      if (_isBlank(value)) return;
      if (key == 'af_status' && _isPaid(current) && !_isPaid(incoming)) {
        return;
      }
      if (_isBlank(merged[key]) || key == 'af_status' || key == 'af_message') {
        merged[key] = value;
      } else if (value.toString().length > merged[key].toString().length) {
        // Keep the longer campaign / sub string when both are filled.
        if (key == 'campaign' ||
            key == 'media_source' ||
            key.startsWith('af_sub') ||
            key.startsWith('deep_link')) {
          merged[key] = value;
        }
      }
    });
    return merged;
  }

  void _fillFrom(Map<String, dynamic> body, Map<String, dynamic> extra) {
    extra.forEach((key, value) {
      if (_isBlank(value)) return;
      if (key == 'af_status' || key == 'af_message') return;
      if (_isBlank(body[key])) body[key] = value;
    });
  }

  /// First callback is often Organic while the OneLink click is still
  /// settling. Ask GCD again with AF UID and IDFA — the pull API accepts
  /// either as `device_id`. Testers match on IDFA; a UID-only lookup
  /// keeps returning the empty organic row.
  Future<void> _rescuePaidInBackground(Map<String, dynamic> organic) async {
    final paid = await _rescuePaid(organic);
    if (paid == null || !_isPaid(paid)) return;
    _install = _preferRicher(_install, _normalize(paid));
    flareTrace(
      () => '[NPD.ORBIT] late paid after organic '
          'af_status=${_install?['af_status']}',
    );
  }

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
    if (_install != null) body.addAll(_normalize(_install!));
    if (_reopen != null) _fillFrom(body, _normalize(_reopen!));
    if (_deepLink != null) _fillFrom(body, _normalize(_deepLink!));

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
