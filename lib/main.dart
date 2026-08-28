import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/audio_service.dart';
import 'core/orientation_controller.dart';
import 'core/profile_service.dart';
import 'flarepath/config/flare_config.dart';
import 'flarepath/core/flare_log.dart';
import 'flarepath/flare_router.dart';
import 'flarepath/infra/flare_exchange.dart';
import 'flarepath/infra/flare_pulse.dart';
import 'flarepath/infra/orbit_agent.dart';
import 'flarepath/infra/orbit_attribution.dart';
import 'flarepath/infra/plume_vault.dart';
import 'flarepath/infra/skyline_probe.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await OrientationController.allowAll();

  final vault = PlumeVault();
  final agent = OrbitAgent();
  await Future.wait<void>(<Future<void>>[
    vault.initialize(),
    agent.prepare(),
    _warmGame(),
  ]);

  flareTrace(
    () => '[NPD.BOOT] credentialsReady=${FlareConfig.grayCredentialsReady} '
        'endpoint=${FlareConfig.endpoint} '
        'afKeyLen=${FlareConfig.appsFlyerKey.length} '
        'fbNum=${FlareConfig.firebaseProjectNumber}',
  );

  var productionServicesReady = false;
  if (FlareConfig.grayCredentialsReady) {
    try {
      await Firebase.initializeApp();
      productionServicesReady = true;
      FirebaseMessaging.onBackgroundMessage(flareBackgroundPulse);
      flareTrace(() => '[NPD.BOOT] Firebase.initializeApp OK');
    } catch (error) {
      flareTrace(() => '[NPD.BOOT] Firebase.initializeApp failed: $error');
    }
    if (productionServicesReady) {
      try {
        await FirebaseAppCheck.instance.activate(
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      } catch (error) {
        flareTrace(() => '[NPD.BOOT] AppCheck skipped: $error');
      }
    }
  } else {
    flareTrace(() => '[NPD.BOOT] gray gate DISABLED — white part only');
  }

  final probe = SkylineProbe();
  final pulse = FlarePulse(vault, enabled: productionServicesReady);
  final attribution = OrbitAttribution(agent);
  final router = FlareRouter(
    vault: vault,
    probe: probe,
    attribution: attribution,
    exchange: FlareExchange(agent, vault),
    pulse: pulse,
    agent: agent,
    runtimeEnabled: FlareConfig.grayCredentialsReady,
  );

  runApp(NeonPlumeDropApp(router: router));
}

Future<void> _warmGame() async {
  try {
    await ProfileService.instance.load();
  } catch (_) {}
  try {
    await AudioService.instance.init();
  } catch (_) {}
}
