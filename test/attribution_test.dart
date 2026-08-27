import 'package:flutter_test/flutter_test.dart';
import 'package:neon_plume_drop/core/attribution.dart';

void main() {
  test('organic conversion data maps to organic', () {
    final snap = parseAppsFlyerConversion({
      'status': 'success',
      'type': 'onInstallConversionDataLoaded',
      'data': {
        'af_status': 'Organic',
        'af_message': 'organic install',
        'is_first_launch': 'true',
      },
    });
    expect(snap.kind, AttributionKind.organic);
    expect(snap.isFirstLaunch, isTrue);
    expect(snap.kind.analyticsValue, 'organic');
  });

  test('non-organic conversion data maps to non_organic', () {
    final snap = parseAppsFlyerConversion({
      'payload': {
        'af_status': 'Non-organic',
        'media_source': 'facebook_ads',
        'campaign': 'orbit_shift_ua',
        'is_first_launch': true,
      },
    });
    expect(snap.kind, AttributionKind.nonOrganic);
    expect(snap.mediaSource, 'facebook_ads');
    expect(snap.campaign, 'orbit_shift_ua');
    expect(snap.kind.analyticsValue, 'non_organic');
  });

  test('missing payload stays unknown', () {
    expect(parseAppsFlyerConversion(null).kind, AttributionKind.unknown);
    expect(parseAppsFlyerConversion({}).kind, AttributionKind.unknown);
  });
}
