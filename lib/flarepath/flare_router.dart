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

  /// Token refresh must not POST config until conversion is in. An early
  /// identity-only body is what locked testers on "No data" / native game
  /// while the developer's already-attributed phone kept opening gray.
  bool _exchangeReady = false;

  /// Firebase re-issues the same push token 2-4× per cold start (APNs
  /// handshake, MessagingHub cache refresh, provisional prompt). Each
  /// `onTokenRefresh` was POSTing an identical body to `config.php`,
  /// so a single install produced 5+ `[NPD.XCHG] response` lines and
  /// wasted the partner's rate budget. Guard against replays.
  String? _lastPostedToken;

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

    // Reachability check first — a 4s FCM wait in airplane mode would
    // hold the splash then dump the user into the native game.
    if (!await probe.quickReach()) {
      flareTrace(() => '[NPD.FLARE] offline at boot → void');
      onProgress(1);
      return const VoidLanding(returnToGame: false);
    }

    // Firebase getInitialMessage MUST resolve before we look for the
    // cold-start URL. With FirebaseAppDelegateProxyEnabled = true
    // (default) Firebase can consume the notification response and
    // SceneDelegate never sees it, so the OrbitTapReader push slot
    // alone returns null on those cold-start-from-tap paths. `_boot()`
    // writes any initial-message URL into the same vault we drain below.
    // Matches the Bolt-of-Aether NovaWarmup order — proven pattern.
    await _warmPulse();
    onProgress(0.22);

    // Now drain BOTH cold-start URL slots:
    //   (a) SceneDelegate push slot (`plume_orbit_push`) — user tapped a
    //       notification from terminated state and iOS forwarded the
    //       response to the scene delegate.
    //   (b) Vault (`_dispatch` stashed it from Firebase's
    //       getInitialMessage during _warmPulse, or a background tap
    //       fired before the router got here).
    // The URL is honoured as-is — no AppsFlyer campaign filter, even for
    // OneLink hosts. Push URLs are always destinations.
    final pushTap = await OrbitTapReader.consumePushTap();
    final vaultUrl = await vault.consumePushUrl();
    final coldPushUrl = pushTap ?? vaultUrl;
    if (coldPushUrl != null && coldPushUrl.isNotEmpty) {
      flareTrace(() => '[NPD.FLARE] cold-start push → $coldPushUrl');
      await vault.saveLane(OrbitLane.portal);
      unawaited(_backgroundDispatch());
      onProgress(1);
      return PortalLanding(coldPushUrl, coldLaunch: true);
    }

    // Universal Link / URL scheme tap (may be a real OneLink click that
    // should feed AppsFlyer attribution rather than open a portal).
    await _pullCampaignTap();

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
    await _pullCampaignTap();
    await attribution.awaitSignals();
    await _pullCampaignTap();
    if (attribution.campaignFallbackUrl == null) {
      flareTrace(() => '[NPD.FLARE] no OneLink tap on this launch');
    }
    _armExchange();
    progress(0.74);
    final reply = await _requestConfig();
    progress(1);
    // Push URL may have arrived via onMessageOpenedApp DURING _requestConfig
    // (Firebase iOS is racy on cold-start-from-tap and can deliver the
    // payload after boot's late-tap window). Prefer it over the base config
    // URL — otherwise a tap on a promo push opens the site's landing page.
    final latePush = await _drainLatePushUrl();
    if (latePush != null) {
      flareTrace(() => '[NPD.FLARE] first: late push tap → $latePush');
      await vault.saveLane(OrbitLane.portal);
      return PortalLanding(latePush, coldLaunch: true);
    }
    flareTrace(
      () => '[NPD.FLARE] first: hasDest=${reply.hasDestination} url=${reply.url} '
          'verdict=${attribution.hasConversionVerdict}',
    );
    if (reply.hasDestination) {
      await vault.saveLane(OrbitLane.portal);
      return PortalLanding(reply.url!);
    }
    final fallback = _campaignWebFallback();
    if (fallback != null) {
      flareTrace(() => '[NPD.FLARE] first: config empty → campaign fallback');
      await vault.saveLane(OrbitLane.portal);
      return PortalLanding(fallback);
    }
    // Bolt: a 404 before conversion must NOT lock the install on game.
    // Next cold start retries with cached GCD.
    if (!attribution.hasConversionVerdict) {
      flareTrace(() => '[NPD.FLARE] first: no AF verdict yet → stay open');
      return const GameLanding();
    }
    // First-launch Organic is often a late OneLink match. Do not lock
    // testers on game — the next cold start re-asks GCD.
    if (attribution.isOrganic && attribution.isFirstLaunch) {
      flareTrace(() => '[NPD.FLARE] first: organic first launch → stay open');
      return const GameLanding();
    }
    await vault.saveLane(OrbitLane.game);
    return const GameLanding();
  }

  Future<FlareLanding> _returningPortal(void Function(double) progress) async {
    if (!await probe.hasInterface()) {
      return const VoidLanding(returnToGame: false);
    }
    await _warmPulse();
    // A fresh push tap on THIS launch wins over config.
    final pending = await vault.consumePushUrl();
    if (pending != null && pending.isNotEmpty) {
      progress(1);
      return PortalLanding(pending);
    }

    final cached = await vault.savedUrl();
    // Offline: the cached config URL is the only fallback so the user is
    // not dumped to the nowifi screen with a live install.
    if (!await probe.canReachNetwork()) {
      if (cached != null && !vault.cachedUrlExpired) {
        progress(1);
        return PortalLanding(cached);
      }
      return const VoidLanding(returnToGame: false);
    }

    // Online: ALWAYS re-ask config so a link changed on the backend takes
    // effect on the next cold start. The cached URL is used only if the
    // request fails — never as a shortcut that pins the old link forever.
    progress(0.5);
    await Future.wait<void>(<Future<void>>[
      attribution.ensureConsent(),
      _warmPulse(),
    ]);
    await _pullCampaignTap();
    await attribution.awaitSignals(
      installTimeout: const Duration(
        milliseconds: FlareConfig.returningSignalTimeoutMs,
      ),
    );
    await _pullCampaignTap();
    _armExchange();
    final reply = await _requestConfig();
    progress(1);
    // See note in `_firstDecision` — a late push tap must win over the
    // cached / config URL, otherwise the promo page never opens.
    final latePush = await _drainLatePushUrl();
    if (latePush != null) {
      flareTrace(() => '[NPD.FLARE] returning: late push tap → $latePush');
      return PortalLanding(latePush, coldLaunch: true);
    }
    if (reply.hasDestination) return PortalLanding(reply.url!);
    final fallback = _campaignWebFallback();
    if (fallback != null) return PortalLanding(fallback);
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
    await _pullCampaignTap();
    await attribution.awaitSignals();
    await _pullCampaignTap();
    _armExchange();
    final reply = await _requestConfig();
    progress(1);
    // See note in `_firstDecision` — pick up a late push tap that raced
    // with the config request so it does not open the base URL instead.
    final latePush = await _drainLatePushUrl();
    if (latePush != null) {
      flareTrace(() => '[NPD.FLARE] game→portal: late push tap → $latePush');
      await vault.saveLane(OrbitLane.portal);
      return PortalLanding(latePush, coldLaunch: true);
    }
    if (reply.hasDestination) {
      flareTrace(() => '[NPD.FLARE] mode flip game → portal');
      await vault.saveLane(OrbitLane.portal);
      return PortalLanding(reply.url!);
    }
    final fallback = _campaignWebFallback();
    if (fallback != null) {
      await vault.saveLane(OrbitLane.portal);
      return PortalLanding(fallback);
    }
    return const GameLanding();
  }

  /// Drain any push URL that was stashed AFTER our initial cold-start
  /// check — covers the race where `onMessageOpenedApp` fires during
  /// `_requestConfig`. Also drains OrbitTapReader for a late Universal
  /// Link tap. Push URLs (from the SceneDelegate push slot and from
  /// Firebase `_dispatch`) always win — the campaign filter is not
  /// applied here because a user-initiated push tap must open as-is.
  Future<String?> _drainLatePushUrl() async {
    final late = await OrbitTapReader.consumePushTap();
    if (late != null && late.isNotEmpty) return late;
    await _pullCampaignTap();
    final url = await vault.consumePushUrl();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Future<void> _pullCampaignTap() async {
    final tap = await OrbitTapReader.consume();
    if (tap == null || tap.isEmpty) return;
    if (_isCampaignHost(tap)) {
      flareTrace(() => '[NPD.FLARE] campaign tap → $tap');
      attribution.ingestCampaignUrl(tap);
      return;
    }
    await vault.stashPushUrl(tap);
  }

  String? campaignWebFallback() => _campaignWebFallback();

  String? _campaignWebFallback() {
    final raw = attribution.campaignFallbackUrl;
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    for (final key in const <String>[
      'af_web_dp',
      'browser_fallback_url',
      'deep_link_value',
    ]) {
      final value = uri.queryParameters[key];
      if (value == null || value.isEmpty) continue;
      final inner = Uri.tryParse(value);
      if (inner != null &&
          (inner.scheme == 'http' || inner.scheme == 'https') &&
          inner.host.isNotEmpty) {
        return inner.toString();
      }
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') return raw;
    return null;
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
      _armExchange();
      await _requestConfig();
    } catch (_) {}
  }

  void _armExchange() {
    _exchangeReady = true;
    pulse.onTokenChanged = _refreshForToken;
  }

  Future<FlareReply> pullConfig({String? token}) => _requestConfig(token: token);

  static bool isCampaignHost(String url) => _isCampaignHost(url);

  static bool _isCampaignHost(String url) {
    final lower = url.toLowerCase();
    final host = FlareConfig.oneLinkHost.toLowerCase();
    return lower.contains('onelink.me') ||
        (host.isNotEmpty && lower.contains(host)) ||
        lower.contains('appsflyer.com') ||
        lower.startsWith('neonplumedrop:');
  }

  Future<void> refreshForToken(String token) => _refreshForToken(token);

  Future<void> _refreshForToken(String token) async {
    if (!_exchangeReady) return;
    if (token.isEmpty) return;
    if (token == _lastPostedToken) return;
    _lastPostedToken = token;
    try {
      await _requestConfig(token: token);
    } catch (_) {}
  }
}
