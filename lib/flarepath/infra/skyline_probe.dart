import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

class SkylineProbe {
  final Connectivity _connectivity = Connectivity();

  Future<bool> hasInterface() async {
    try {
      final status = await _connectivity.checkConnectivity();
      if (status.isEmpty) return false;
      if (status.every((value) => value == ConnectivityResult.none)) {
        return false;
      }
      return status.any(
        (value) =>
            value == ConnectivityResult.wifi ||
            value == ConnectivityResult.mobile ||
            value == ConnectivityResult.ethernet,
      );
    } catch (_) {
      return false;
    }
  }

  /// HTTP to a raw IP. DNS cache and a stale Wi-Fi path (common after the
  /// app was installed / last opened online) must not count as reachable.
  Future<bool> _httpOpen() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 320)
      ..idleTimeout = const Duration(milliseconds: 320);
    try {
      final request = await client
          .getUrl(Uri.parse('http://1.1.1.1'))
          .timeout(const Duration(milliseconds: 320));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(milliseconds: 320),
      );
      await response.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> quickReach() async {
    if (!await hasInterface()) return false;
    return _httpOpen();
  }

  Future<bool> canReachNetwork() => quickReach();

  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;
}
