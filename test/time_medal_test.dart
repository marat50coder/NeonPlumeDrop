import 'package:flutter_test/flutter_test.dart';
import 'package:neon_plume_drop/models/catalog.dart';

void main() {
  test('time medals unlock at 30, 60, 90 and 120 seconds', () {
    expect(TimeMedal.earnedBy(29.9).map((m) => m.id), isEmpty);
    expect(TimeMedal.earnedBy(30).map((m) => m.id), ['spark_circuit']);
    expect(TimeMedal.earnedBy(60).map((m) => m.id), [
      'spark_circuit',
      'neon_orbit',
    ]);
    expect(TimeMedal.earnedBy(90).map((m) => m.id), [
      'spark_circuit',
      'neon_orbit',
      'deep_surge',
    ]);
    expect(TimeMedal.earnedBy(120).map((m) => m.id), [
      'spark_circuit',
      'neon_orbit',
      'deep_surge',
      'collapse_crown',
    ]);
    expect(TimeMedal.earnedBy(180), hasLength(4));
  });
}
