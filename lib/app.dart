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
    // Push tap is always a user-selected destination. Do NOT run it
    // through the campaign filter — a partner promo URL on OneLink is
    // still a destination when delivered via a notification the user
    // explicitly tapped.
    // Flip lane BEFORE `_openPortal` so a resume-driven `_catchCampaign`
    // that races with this dispatch sees `lane == portal` and does not
    // replace our portal with a base-config URL.
    try {
      await router.vault.saveLane(OrbitLane.portal);
    } catch (_) {}
    _openPortal(router, url);
  }

  /// On resume we do ONE thing only — pick up a Universal Link / URL
  /// scheme that iOS delivered while we were backgrounded. Everything
  /// push-related is routed by `_dispatch` (live callback when the
  /// portal is mounted, `_onBackgroundPushUrl` fallback when the user
  /// was on the native game). Polling the vault or re-POSTing config
  /// here would race with the portal that `_dispatch` just told to
  /// navigate — the user saw that as a broken double-load / "flip
  /// back to the first page".
  Future<void> _catchCampaign() async {
    final router = widget.router;
    if (router == null) return;
    try {
      await router.vault.initialize();
    } catch (_) {
      return;
    }

    final tap = await OrbitTapReader.consume();
    if (tap == null || tap.isEmpty) return;
    if (FlareRouter.isCampaignHost(tap)) {
      router.attribution.ingestCampaignUrl(tap);
    } else {
      _openPortal(router, tap);
    }
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
