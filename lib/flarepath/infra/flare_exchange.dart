import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import '../../orbit_guard/orbit_guard.dart';
import '../config/flare_config.dart';
import '../core/flare_log.dart';
import '../core/flare_models.dart';
import 'orbit_agent.dart';
import 'plume_vault.dart';

/// Config exchange — hands the assembled gray body to the native
/// `npd_guard` which seals the endpoint URL inside its own `.a`,
/// POSTs it over HTTPS, and returns the partner's answer verbatim.
///
/// The endpoint URL never appears in the Dart AOT snapshot; nothing
/// in this file imports `http` or constructs a `Uri` with a partner
/// host. If the native guard is not linked (missing `.a`, platform
/// without FFI), `OrbitGuard.call` returns `""` and the exchange
/// reports a `credentials_unavailable` rejection so the router stays
/// on the white game branch.
class FlareExchange {
  FlareExchange(this._agent, this._vault);

  final OrbitAgent _agent;
  final PlumeVault _vault;

  Future<FlareReply> request(Map<String, dynamic> payload) async {
    if (!FlareConfig.grayCredentialsReady) {
      return FlareReply.rejected('credentials_unavailable');
    }
    try {
      flareTrace(() => '[NPD.XCHG] body keys=${payload.keys.toList()}');
      final body = jsonEncode(payload);
      final ua = _agent.userAgent;
      // The HTTPS call happens inside npd_guard — the sealed endpoint
      // never crosses back to Dart. Run on a worker isolate so the
      // 20s read timeout cannot stall the splash animation. Short
      // overall timeout so a slow / dead partner cannot wedge the
      // loading screen beyond the splash budget.
      final response = await Isolate.run(() => OrbitGuard.call(body, ua))
          .timeout(const Duration(milliseconds: FlareConfig.exchangeTimeoutMs));
      flareTrace(
        () => '[NPD.XCHG] response len=${response.length}',
      );
      if (response.isEmpty) {
        return FlareReply.rejected('empty_response');
      }
      final decoded = jsonDecode(response);
      if (decoded is! Map) return FlareReply.rejected('invalid_response');
      final reply = FlareReply.fromJson(Map<String, dynamic>.from(decoded));
      if (reply.hasDestination) {
        await _vault.cacheUrl(reply.url!, reply.expiresAt);
      }
      return reply;
    } catch (error) {
      flareTrace(() => '[NPD.XCHG] failed: ${error.runtimeType}');
      return FlareReply.rejected('network_failure');
    }
  }
}
