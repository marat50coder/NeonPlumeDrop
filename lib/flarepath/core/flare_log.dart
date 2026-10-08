import 'package:flutter/foundation.dart';

/// Debug-only trace. The `assert` is stripped from `--release`
/// builds, so no `[NPD.*]` line — in particular nothing that
/// contains the endpoint URL, AppsFlyer dev key, Firebase project
/// number, push token or the config body — ever reaches logcat /
/// Console.app on a shipped build. See FINAL_CHECKLIST Part G
/// (log leaks are a release blocker).
void flareTrace(String Function() build) {
  assert(() {
    debugPrint(build());
    return true;
  }());
}
