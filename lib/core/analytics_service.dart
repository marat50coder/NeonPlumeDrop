import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import 'appsflyer_config.dart';
import 'attribution.dart';
import 'profile_service.dart';

/// Starts AppsFlyer after ATT, then stores whether the install was organic
/// or non-organic from conversion data.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  AppsflyerSdk? _sdk;
  bool _started = false;
  AttributionSnapshot snapshot = AttributionSnapshot.unknown;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    snapshot = ProfileService.instance.attribution;
    try {
      await _requestTrackingIfNeeded();
      if (!AppsFlyerConfig.isConfigured) return;

      final sdk = AppsflyerSdk(
        AppsFlyerOptions(
          afDevKey: AppsFlyerConfig.devKey,
          appId: AppsFlyerConfig.appleAppId,
          showDebug: kDebugMode,
          timeToWaitForATTUserAuthorization: 15.0,
          manualStart: true,
        ),
      );
      _sdk = sdk;

      sdk.onInstallConversionData((res) {
        final parsed = parseAppsFlyerConversion(res);
        snapshot = parsed;
        ProfileService.instance.setAttribution(parsed);
        if (parsed.kind != AttributionKind.unknown) {
          logEvent('attribution_resolved', {
            'af_status': parsed.kind.analyticsValue,
            'media_source': parsed.mediaSource,
            'campaign': parsed.campaign,
            'is_first_launch': parsed.isFirstLaunch,
          });
        }
      });

      await sdk.initSdk(registerConversionDataCallback: true);
      sdk.startSDK();
      await logEvent('app_open', {'af_status': snapshot.kind.analyticsValue});
    } catch (_) {
      // Attribution must never block launch.
    }
  }

  Future<void> logEvent(String name, Map<String, dynamic> values) async {
    final sdk = _sdk;
    if (sdk == null) return;
    final payload = <String, dynamic>{
      'af_status': snapshot.kind.analyticsValue,
      ...values,
    };
    try {
      await sdk.logEvent(name, payload);
    } catch (_) {}
  }

  Future<void> logRunComplete({
    required double survivalSeconds,
    required int phaseIndex1,
    required int neonEnergyEarned,
  }) {
    return logEvent('run_complete', {
      'survival_seconds': survivalSeconds.round(),
      'phase': phaseIndex1,
      'neon_energy': neonEnergyEarned,
    });
  }

  Future<void> _requestTrackingIfNeeded() async {
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (_) {}
  }
}
