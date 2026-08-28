import 'package:flutter/foundation.dart';

void flareTrace(String Function() build) {
  assert(() { debugPrint(build()); return true; }());
}
