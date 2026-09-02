import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../core/audio_service.dart';
import '../../core/profile_service.dart';
import '../config/flare_config.dart';
import '../core/flare_log.dart';
import 'flare_pulse.dart';

/// Shared gray-path boot so an offline first frame can skip Firebase,
/// then Retry can finish the same setup before loading starts.
abstract final class FlareBoot {
  static bool productionReady = false;

  static Future<void> ensureProduction() async {
    if (productionReady) return;
    if (!FlareConfig.grayCredentialsReady) {
      flareTrace(() => '[NPD.BOOT] gray gate DISABLED — white part only');
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      productionReady = true;
      FirebaseMessaging.onBackgroundMessage(flareBackgroundPulse);
      flareTrace(() => '[NPD.BOOT] Firebase.initializeApp OK');
    } catch (error) {
      flareTrace(() => '[NPD.BOOT] Firebase.initializeApp failed: $error');
      return;
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    } catch (error) {
      flareTrace(() => '[NPD.BOOT] AppCheck skipped: $error');
    }
  }

  static Future<void> warmGame() async {
    try {
      await ProfileService.instance.load();
    } catch (_) {}
    try {
      await AudioService.instance.init();
    } catch (_) {}
  }
}
