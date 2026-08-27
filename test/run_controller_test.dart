import 'package:flutter_test/flutter_test.dart';

import 'package:neon_plume_drop/core/game_balance.dart';
import 'package:neon_plume_drop/game/game_models.dart';
import 'package:neon_plume_drop/game/run_controller.dart';
import 'package:neon_plume_drop/game/run_modifiers.dart';

void main() {
  test('phase bands advance with elapsed time', () {
    expect(GameBalance.bandFor(0).phase, CollapsePhase.phase1);
    expect(GameBalance.bandFor(40).phase, CollapsePhase.phase2);
    expect(GameBalance.bandFor(80).phase, CollapsePhase.phase3);
    expect(GameBalance.bandFor(120).phase, CollapsePhase.overload);
    expect(GameBalance.bandFor(160).phase, CollapsePhase.criticalCollapse);
  });

  test('orbital shift stays inside live lanes', () {
    final run = RunController(modifiers: RunModifiers.none, seed: 7);
    expect(run.ballOrbit, 1);
    run.attemptShift(-1);
    for (int i = 0; i < 20; i++) {
      run.update(0.02);
    }
    expect(run.ballOrbit, 0);
    run.attemptShift(-1);
    expect(run.shifting, isFalse);
  });

  test('a finished run reports stats', () {
    final run = RunController(modifiers: RunModifiers.none, seed: 3);
    run.update(0.016);
    final stats = run.collectStats();
    expect(stats.survivalSeconds, greaterThan(0));
    expect(stats.phaseIndex1, 1);
  });

  test('slot families never mix meaning', () {
    expect(SlotKind.obstacle.family, SlotFamily.danger);
    expect(SlotKind.energy.family, SlotFamily.pickup);
    expect(SlotKind.gateEnergy.family, SlotFamily.gate);
    expect(SlotKind.cracked.family, SlotFamily.warning);
  });
}
