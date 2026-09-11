import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Same two-step check as Bolt-of-Aether `NetProbe`.
/// Radio flag first, then a real DNS lookup. Do not use cleartext HTTP:
/// iOS ATS blocks `http://1.1.1.1` and the app then sits on nowifi
/// even when the WAN is up.
class SkylineProbe {
  final Connectivity _connectivity = Connectivity();

  Future<bool> hasInterface() async {
    try {
      final status = await _connectivity.checkConnectivity();
      return status.any((value) => value != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _dnsOpen({
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    for (final host in const <String>['gstatic.com', 'apple.com']) {
      try {
        final records = await InternetAddress.lookup(host).timeout(timeout);
        if (records.any((record) => record.rawAddress.isNotEmpty)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<bool> quickReach() async {
    if (!await hasInterface()) return false;
    return _dnsOpen();
  }

  Future<bool> canReachNetwork() async {
    if (!await hasInterface()) return false;
    return _dnsOpen(timeout: const Duration(milliseconds: 1500));
  }

  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;
}
