import 'package:flutter/services.dart';

/// Splash/loading may rotate freely. Every other screen is locked to portrait.
///
/// `UIRequiresFullScreen` is set so iPadOS honours [setPreferredOrientations].
/// Both phone and tablet Info.plist orientation arrays include landscape, so
/// the dedicated landscape loading artwork can appear on iPhone and iPad.
class OrientationController {
  OrientationController._();

  static Future<void> allowAll() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> lockPortrait() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }
}
