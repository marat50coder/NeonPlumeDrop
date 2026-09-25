import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _nativeLog = MethodChannel('npd/log');

void flareTrace(String Function() build) {
  // Release `flutter run` over Wi-Fi does not forward debugPrint.
  // print() + NSLog (via the native channel) is what actually shows up.
  final line = build();
  print(line);
  debugPrint(line);
  unawaited(
    _nativeLog.invokeMethod<void>('line', line).catchError((_) => null),
  );
}
