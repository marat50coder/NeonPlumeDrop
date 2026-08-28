import 'dart:convert';

import '../config/flare_config.dart';
import '../core/flare_log.dart';
import '../core/flare_models.dart';
import 'orbit_agent.dart';
import 'plume_vault.dart';

class FlareExchange {
  FlareExchange(this._agent, this._vault);

  final OrbitAgent _agent;
  final PlumeVault _vault;

  Future<FlareReply> request(Map<String, dynamic> payload) async {
    if (!FlareConfig.grayCredentialsReady) {
      return FlareReply.rejected('credentials_unavailable');
    }
    try {
      flareTrace(() => '[NPD.XCHG] request ${jsonEncode(payload)}');
      final response = await _agent
          .post(
            Uri.parse(FlareConfig.endpoint),
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(milliseconds: FlareConfig.exchangeTimeoutMs),
          );
      flareTrace(
        () => '[NPD.XCHG] response ${response.statusCode} ${response.body}',
      );
      if (response.statusCode != 200) {
        return FlareReply.rejected('http_${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return FlareReply.rejected('invalid_response');
      final reply = FlareReply.fromJson(Map<String, dynamic>.from(decoded));
      if (reply.hasDestination) {
        await _vault.cacheUrl(reply.url!, reply.expiresAt);
      }
      return reply;
    } catch (error) {
      flareTrace(() => '[NPD.XCHG] failed: $error');
      return FlareReply.rejected('network_failure');
    }
  }
}
