// ignore_for_file: avoid_print

import 'package:neon_plume_drop/flarepath/config/flare_config.dart';

void main() {
  final checks = <String, String>{
    'endpoint': FlareConfig.endpoint,
    'appsFlyerKey': FlareConfig.appsFlyerKey,
    'firebaseProjectNumber': FlareConfig.firebaseProjectNumber,
    'gcdBase': FlareConfig.gcdBase,
    'oneLinkHost': FlareConfig.oneLinkHost,
    'privacyUrl': FlareConfig.privacyUrl,
    'supportUrl': FlareConfig.supportUrl,
  };
  for (final entry in checks.entries) {
    print('${entry.key}=${entry.value}');
  }
  if (FlareConfig.endpoint != 'https://neonplumedrop.com/config.php') {
    throw StateError('endpoint mismatch');
  }
  if (FlareConfig.appsFlyerKey != '8nyAh9JLozPkfRm2n3f6Nn') {
    throw StateError('appsFlyer mismatch');
  }
  if (FlareConfig.firebaseProjectNumber != '857118764079') {
    throw StateError('firebase mismatch');
  }
  if (!FlareConfig.grayCredentialsReady) {
    throw StateError('gate not ready');
  }
  print('ROUNDTRIP_OK ready=${FlareConfig.grayCredentialsReady}');
}
