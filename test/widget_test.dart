import 'package:flutter_test/flutter_test.dart';
import 'package:neon_plume_drop/core/theme.dart';

void main() {
  test('neon palette stays high-contrast', () {
    expect(NeonColors.cyan.toARGB32(), isNonZero);
    expect(NeonColors.magenta.toARGB32(), isNonZero);
    expect(NeonColors.voidBlack.computeLuminance(), lessThan(0.05));
  });
}
