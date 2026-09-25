import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/orientation_controller.dart';
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
  print('[NPD.BOOT] dart console alive');
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

  flareTrace(
    () => '[NPD.BOOT] credentialsReady=${FlareConfig.grayCredentialsReady} '
        'endpoint=${FlareConfig.endpoint} '
        'afKeyLen=${FlareConfig.appsFlyerKey.length} '
        'fbNum=${FlareConfig.firebaseProjectNumber}',
  );

  final vault = PlumeVault();
  final agent = OrbitAgent();
  final probe = SkylineProbe();
  final router = FlareRouter(
    vault: vault,
    probe: probe,
    attribution: OrbitAttribution(agent),
    exchange: FlareExchange(agent, vault),
    pulse: FlarePulse(vault, enabled: FlareConfig.grayCredentialsReady),
    agent: agent,
    runtimeEnabled: FlareConfig.grayCredentialsReady,
  );

  // Do not await Firebase / prefs / DNS here. First frame must be nowifi.
  runApp(NeonPlumeDropApp(router: router));
}
