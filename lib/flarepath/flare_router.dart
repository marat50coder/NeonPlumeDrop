import 'dart:async';
import 'dart:io';

import 'config/flare_config.dart';
import 'core/flare_log.dart';
import 'core/flare_models.dart';
import 'infra/flare_exchange.dart';
import 'infra/flare_pulse.dart';
import 'infra/orbit_agent.dart';
import 'infra/orbit_attribution.dart';
import 'infra/orbit_tap_reader.dart';
import 'infra/plume_vault.dart';
import 'infra/skyline_probe.dart';

class FlareRouter {
  FlareRouter({
    required this.vault,
    required this.probe,
    required this.attribution,
    required this.exchange,
    required this.pulse,
    required this.agent,
    required this.runtimeEnabled,
  });

  final PlumeVault vault;
  final SkylineProbe probe;
  final OrbitAttribution attribution;
  final FlareExchange exchange;
  final FlarePulse pulse;
  final OrbitAgent agent;
  final bool runtimeEnabled;

  bool get enabled => runtimeEnabled && FlareConfig.grayCredentialsReady;

  Future<FlareLanding>? _decideFuture;

  Future<FlareLanding> decide({
    required void Function(double value) onProgress,
  }) =>
      _decideFuture ??= _decide(onProgress: onProgress)
          .whenComplete(() => _decideFuture = null);

  Future<FlareLanding> _decide({
    required void Function(double value) onProgress,
  }) async {
    if (!enabled) {
      flareTrace(
        () => '[NPD.FLARE] gate disabled '
            'runtime=$runtimeEnabled creds=${FlareConfig.grayCredentialsReady}',
      );
      onProgress(1);
      return const GameLanding();
    }

    flareTrace(() => '[NPD.FLARE] decide start lane=${vault.lane}');

    // Reachability BEFORE pulse.boot / getInitialMessage. A 4 s FCM wait
    // while airplane-mode is on would keep the loading bar on screen and
    // then dump the user into the native game. Do not consume a cold-start
    // tap URL here — keep it for the retry once the radio is up.
    if (!await probe.quickReach()) {
      flareTrace(() => '[NPD.FLARE] offline at boot → void');
      onProgress(1);
      return const VoidLanding(returnToGame: false);
    }

    pulse.onTokenChanged = _refreshForToken;

    // Firebase getInitialMessage MUST resolve before we look for a
    // cold-start URL — with FirebaseAppDelegateProxyEnabled=true Firebase
    // eats the notification response and SceneDelegate may never see it,
    // so OrbitTapReader alone returns null on the terminated-tap path.
    // boot() writes any initial-message URL into the vault we drain below.
    await _warmPulse();
    onProgress(0.22);

    // Cold-start push tap consumed FIRST — Bolt AetherWarmup contract:
    // (a) SceneDelegate → OrbitTapReader
    // (b) getInitialMessage → vault.stashPushUrl
    // Drain BOTH before routing so a stale vault copy cannot fire on the
    // next AppLifecycleState.resumed (gray_flow_lessons.md §12).
    final tapUrl = await OrbitTapReader.consume();
    final vaultUrl = await vault.consumePushUrl();
    final coldUrl = (tapUrl != null && tapUrl.isNotEmpty) ? tapUrl : vaultUrl;
    if (coldUrl != null && coldUrl.isNotEmpty) {
      flareTrace(() => '[NPD.FLARE] cold-start push → $coldUrl');
      await vault.saveLane(OrbitLane.portal);
      unawaited(_backgroundDispatch());
      onProgress(1);
      return PortalLanding(coldUrl, coldLaunch: true);
    }

    onProgress(0.34);
    return switch (vault.lane) {
      OrbitLane.open => _firstDecision(onProgress),
      OrbitLane.portal => _returningPortal(onProgress),
      OrbitLane.game => _returningGame(onProgress),
    };
  }

  Future<FlareLanding> _firstDecision(void Function(double) progress) async {
    if (!await probe.hasInterface()) {
      flareTrace(() => '[NPD.FLARE] first: no interface → void');
      return const VoidLanding(returnToGame: false);
    }
    progress(0.31);
    if (!await probe.canReachNetwork()) {
      flareTrace(() => '[NPD.FLARE] first: probe failed → void');
      return const VoidLanding(returnToGame: false);
    }
    progress(0.48);
    await Future.wait<void>(<Future<void>>[
      attribution.ensureConsent(),
      _warmPulse(),
    ]);
    progress(0.62);
    await attribution.awaitSignals();
    progress(0.74);
    final reply = await _requestConfig();
    progress(1);
    flareTrace(
      () => '[NPD.FLARE] first: hasDest=${reply.hasDestination} url=${reply.url}',
    );
    if (reply.hasDestination) {
      await vault.saveLane(OrbitLane.portal);
      return PortalLanding(reply.url!);
    }
    await vault.saveLane(OrbitLane.game);
    return const GameLanding();
  }

  Future<FlareLanding> _returningPortal(void Function(double) progress) async {
    if (!await probe.hasInterface()) {
      return const VoidLanding(returnToGame: false);
    }
    await _warmPulse();
    unawaited(_backgroundDispatch());
    final pending = await vault.consumePushUrl();
    if (pending != null && pending.isNotEmpty) {
      progress(1);
      return PortalLanding(pending);
    }
    final cached = await vault.savedUrl();
    if (cached != null && !vault.cachedUrlExpired) {
      progress(1);
      return PortalLanding(cached);
    }

    if (!await probe.canReachNetwork()) {
      return const VoidLanding(returnToGame: false);
    }
    progress(0.64);
    await Future.wait<void>(<Future<void>>[
      attribution.ensureConsent(),
      _warmPulse(),
    ]);
    await attribution.awaitSignals(
      installTimeout: const Duration(
        milliseconds: FlareConfig.returningSignalTimeoutMs,
      ),
    );
    final reply = await _requestConfig();
    progress(1);
    if (reply.hasDestination) return PortalLanding(reply.url!);
    if (cached != null && !vault.cachedUrlExpired) return PortalLanding(cached);
    return const VoidLanding(returnToGame: false);
  }

  Future<FlareLanding> _returningGame(void Function(double) progress) async {
    if (!await probe.hasInterface() || !await probe.canReachNetwork()) {
      flareTrace(() => '[NPD.FLARE] returning game offline → void');
      return const VoidLanding(returnToGame: false);
    }
    progress(0.58);
    await Future.wait<void>(<Future<void>>[
      attribution.ensureConsent(),
      _warmPulse(),
    ]);
    await attribution.awaitSignals();
    final reply = await _requestConfig();
    progress(1);
    if (!reply.hasDestination) return const GameLanding();
    flareTrace(() => '[NPD.FLARE] mode flip game → portal');
    await vault.saveLane(OrbitLane.portal);
    return PortalLanding(reply.url!);
  }

  Future<FlareReply> _requestConfig({String? token}) async {
    final body = await attribution.compose(
      locale: Platform.localeName.replaceAll('-', '_'),
      pushToken: token ?? pulse.token,
    );
    return exchange.request(body);
  }

  Future<void> _warmPulse() async {
    try {
      await pulse.boot();
    } catch (_) {}
  }

  Future<void> _backgroundDispatch() async {
    try {
      await Future.wait<void>(<Future<void>>[
        attribution.ensureConsent(),
        _warmPulse(),
      ]);
      await attribution.awaitSignals();
      await _requestConfig();
    } catch (_) {}
  }

  Future<void> refreshForToken(String token) => _refreshForToken(token);

  Future<void> _refreshForToken(String token) async {
    try {
      await _requestConfig(token: token);
    } catch (_) {}
  }
}
