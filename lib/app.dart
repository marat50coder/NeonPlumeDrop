import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/profile_service.dart';
import 'core/theme.dart';
import 'flarepath/core/flare_models.dart';
import 'flarepath/flare_router.dart';
import 'flarepath/infra/orbit_tap_reader.dart';
import 'flarepath/pages/ignite_screen.dart';
import 'flarepath/pages/orbit_boot_gate.dart';
import 'flarepath/pages/orbit_portal.dart';

class NeonPlumeDropApp extends StatefulWidget {
  const NeonPlumeDropApp({super.key, this.router});

  final FlareRouter? router;

  @override
  State<NeonPlumeDropApp> createState() => _NeonPlumeDropAppState();
}

class _NeonPlumeDropAppState extends State<NeonPlumeDropApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final router = widget.router;
    if (router != null) {
      // Background push tap on the native game screen has no live
      // `onDestination` (OrbitPortal is not mounted). Wire a fallback so
      // `_dispatch` still opens the intended URL instead of just
      // stashing it in the vault and hoping someone picks it up.
      router.pulse.onDestinationFallback = _onBackgroundPushUrl;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final router = widget.router;
    if (router != null && router.pulse.onDestinationFallback == _onBackgroundPushUrl) {
      router.pulse.onDestinationFallback = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_catchCampaign());
    }
  }

  Future<void> _onBackgroundPushUrl(String url) async {
    final router = widget.router;
    if (router == null || url.isEmpty) return;
    if (FlareRouter.isCampaignHost(url)) {
      router.attribution.ingestCampaignUrl(url);
      return;
    }
    // Flip lane BEFORE `_openPortal` so a resume-driven `_catchCampaign`
    // that races with this dispatch sees `lane == portal` and does not
    // replace our portal with a base-config URL.
    try {
      await router.vault.saveLane(OrbitLane.portal);
    } catch (_) {}
    _openPortal(router, url);
  }

  Future<void> _catchCampaign() async {
    final router = widget.router;
    if (router == null) return;
    try {
      await router.vault.initialize();
    } catch (_) {
      return;
    }

    final tap = await OrbitTapReader.consume();
    if (tap != null && tap.isNotEmpty) {
      if (FlareRouter.isCampaignHost(tap)) {
        router.attribution.ingestCampaignUrl(tap);
      } else {
        _openPortal(router, tap);
        return;
      }
    }

    // Background push tap: Firebase stashes the URL in the vault via
    // `_dispatch` when `onMessageOpenedApp` fires. If we won the race
    // against `_dispatch` (resume callback fired first), give it a short
    // window to deliver — otherwise `pullConfig` below would open the
    // base URL and clobber the promo page the tap was meant to open.
    final pushed = await _awaitBackgroundPushUrl(router);
    if (pushed != null) {
      if (FlareRouter.isCampaignHost(pushed)) {
        router.attribution.ingestCampaignUrl(pushed);
      } else {
        await router.vault.saveLane(OrbitLane.portal);
        _openPortal(router, pushed);
        return;
      }
    }

    // Gray WebView is already up. Re-POSTing config and pushing a new
    // OrbitPortal reloads widget.url (the first partner page) and wipes
    // whatever page the user had reached. Push taps are handled above.
    if (router.vault.lane == OrbitLane.portal) return;
    if (router.vault.lane == OrbitLane.open) return;

    try {
      await router.attribution.awaitSignals(
        installTimeout: const Duration(seconds: 4),
      );
      final reply = await router.pullConfig();
      if (reply.hasDestination) {
        await router.vault.saveLane(OrbitLane.portal);
        _openPortal(router, reply.url!);
        return;
      }
      final fallback = router.campaignWebFallback();
      if (fallback != null && fallback.isNotEmpty) {
        await router.vault.saveLane(OrbitLane.portal);
        _openPortal(router, fallback);
      }
    } catch (_) {}
  }

  /// Poll the vault for a push URL that `_dispatch` may still be about
  /// to write. Immediate check first (zero delay), then up to ~900ms of
  /// short retries — Firebase iOS delivers `onMessageOpenedApp` within a
  /// few hundred ms of the tap-driven resume in practice. Cheap enough
  /// to run on every resume and avoids opening the base config URL on
  /// top of a push tap.
  Future<String?> _awaitBackgroundPushUrl(FlareRouter router) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      final url = await router.vault.consumePushUrl();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  void _openPortal(FlareRouter router, String url) {
    final nav = _nav.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => OrbitPortal(
          url: url,
          vault: router.vault,
          probe: router.probe,
          pulse: router.pulse,
          agent: router.agent,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileService>.value(
      value: ProfileService.instance,
      child: MaterialApp(
        navigatorKey: _nav,
        title: 'Neon Plume Drop',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: NeonColors.cyan,
            brightness: Brightness.dark,
          ).copyWith(surface: Colors.black),
          appBarTheme: const AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.black,
              statusBarBrightness: Brightness.dark,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Colors.black,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,
            ),
          ),
        ),
        builder: (context, child) => ClampedTextScale(child: child!),
        home: widget.router == null
            ? const IgniteScreen()
            : OrbitBootGate(router: widget.router!),
      ),
    );
  }
}
