import 'package:flutter/services.dart';

import 'profile_service.dart';

class Haptics {
  Haptics._();

  static void light() {
    if (ProfileService.instance.vibrationEnabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (ProfileService.instance.vibrationEnabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (ProfileService.instance.vibrationEnabled) HapticFeedback.heavyImpact();
  }

  static void selection() {
    if (ProfileService.instance.vibrationEnabled) HapticFeedback.selectionClick();
  }
}
