import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

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

  /// Boot fast-path: radio flag + one DNS lookup, no retry. Offline devices
  /// fail in well under a second so the no-wifi screen can appear before
  /// the loading pipeline (Firebase / AppsFlyer / config POST) starts.
  Future<bool> quickReach() async {
    if (!await hasInterface()) return false;
    try {
      final records = await InternetAddress.lookup(
        'www.ietf.org',
      ).timeout(const Duration(milliseconds: 740));
      return records.any((record) => record.rawAddress.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  Future<bool> canReachNetwork() async {
    if (!await hasInterface()) return false;
    for (final host in const <String>['www.ietf.org', 'www.iana.org']) {
      try {
        final records = await InternetAddress.lookup(
          host,
        ).timeout(const Duration(milliseconds: 4100));
        if (records.any((record) => record.rawAddress.isNotEmpty)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;
}
