import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
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
  Future<void>? _organicRefresh;
  final Completer<void> _installReady = Completer<void>();
  final Completer<void> _deepLinkReady = Completer<void>();

  Future<void> start() => _startFuture ??= _start();

  /// Consent is its own memoized future — not the SDK start — so a lost
  /// prompt during a route change can be retried after the app is frontmost.
  Future<void> ensureConsent() => _consentFuture ??= _askConsent();

  Future<void> _start() async {
    if (!FlareConfig.grayCredentialsReady) {
      _completeEmpty();
      return;
    }
    try {
      // Start AF before ATT. Waiting for the prompt first is why UDL
      // comes back NOT_FOUND on a OneLink open — the SDK is still dark.
      final sdk = AppsflyerSdk(
        AppsFlyerOptions(
          afDevKey: FlareConfig.appsFlyerKey,
          appId: FlareConfig.iosStoreId,
          showDebug: false,
          timeToWaitForATTUserAuthorization: 60,
          disableAdvertisingIdentifier: false,
          manualStart: true,
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
      try {
        sdk.performOnDeepLinking();
      } catch (_) {}
      sdk.startSDK(
        onSuccess: () => flareTrace(() => '[NPD.ORBIT] start ok'),
        onError: (int code, String msg) =>
            flareTrace(() => '[NPD.ORBIT] start $code $msg'),
      );
      unawaited(_syncAttAfterStart(sdk));
    } catch (error) {
      flareTrace(() => '[NPD.ORBIT] initialization failed: $error');
      _completeEmpty();
    }
  }

  Future<void> _syncAttAfterStart(AppsflyerSdk sdk) async {
    await ensureConsent();
    if (!Platform.isIOS) return;
    try {
      final granted =
          await AppTrackingTransparency.trackingAuthorizationStatus ==
              TrackingStatus.authorized;
      if (!granted) sdk.setDisableAdvertisingIdentifiers(true);
    } catch (_) {}
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
      } else {
        _install = received;
        if (received['af_status'] == 'Organic') {
          _organicRefresh ??= _recheckOrganic(received);
        }
      }
    } catch (error) {
      flareTrace(() => '[NPD.ORBIT] conversion parse error: $error');
      _install = <String, dynamic>{};
    } finally {
      if (!_installReady.isCompleted) _installReady.complete();
    }
  }

  Future<void> _recheckOrganic(Map<String, dynamic> received) async {
    await Future<void>.delayed(
      const Duration(seconds: FlareConfig.organicRecheckSeconds),
    );
    final gcd = await _fetchGcd();
    if (gcd != null && gcd.isNotEmpty) {
      flareTrace(
        () => '[NPD.ORBIT] gcd af_status=${gcd['af_status']} '
            'keys=${gcd.keys.toList()}',
      );
      _install = gcd;
    } else {
      _install = received;
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
    final pid = query['pid'];
    if (pid != null && pid.isNotEmpty) {
      _deepLink!['media_source'] ??= pid;
      _deepLink!['af_status'] = 'Non-organic';
    }
    final campaign = query['c'];
    if (campaign != null && campaign.isNotEmpty) {
      _deepLink!['campaign'] ??= campaign;
    }
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

  Future<Map<String, dynamic>?> _fetchGcd() async {
    final uid = await appsFlyerId();
    if (uid == null || uid.isEmpty) return null;
    try {
      final uri = Uri.parse(
        '${FlareConfig.gcdBase}id${FlareConfig.iosStoreId}?device_id=$uid',
      );
      final response = await _agent
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer ${FlareConfig.appsFlyerKey}',
            },
          )
          .timeout(const Duration(milliseconds: 14200));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
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
    final refresh = _organicRefresh;
    if (refresh != null) {
      await refresh.timeout(const Duration(seconds: 16), onTimeout: () {});
    }
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
    // OneLink query wins over Organic GCD. putIfAbsent left pid / af_status
    // stuck on Organic after a real click that iOS delivered as a URL.
    if (_deepLink != null) {
      _deepLink!.forEach((key, value) {
        if (value != null) body[key] = value;
      });
    }

    body['af_id'] = await appsFlyerId() ?? body['af_id'] ?? '';
    body['bundle_id'] = FlareConfig.bundleId;
    body['os'] = 'iOS';
    body['store_id'] = FlareConfig.storeToken;
    body['locale'] = locale;
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

  void _completeEmpty() {
    if (!_installReady.isCompleted) _installReady.complete();
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }
}
