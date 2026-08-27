import 'package:flutter_test/flutter_test.dart';

import 'package:neon_plume_drop/core/game_balance.dart';
import 'package:neon_plume_drop/game/game_models.dart';
import 'package:neon_plume_drop/game/run_controller.dart';
import 'package:neon_plume_drop/game/run_modifiers.dart';

void main() {
  test('phase bands advance with elapsed time', () {
    expect(GameBalance.bandFor(0).startSeconds, 0);
    expect(GameBalance.bandFor(19).startSeconds, 0);
    expect(GameBalance.bandFor(20).startSeconds, 20);
    expect(GameBalance.bandFor(40).phase, CollapsePhase.phase2);
    expect(GameBalance.bandFor(80).phase, CollapsePhase.phase3);
    expect(GameBalance.bandFor(100).phase, CollapsePhase.overload);
    expect(GameBalance.bandFor(120).phase, CollapsePhase.criticalCollapse);
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

  test('an obstacle kills after i-frames expire on the same cell', () {
    final run = RunController(modifiers: RunModifiers.none, seed: 4);
    final orbit = run.orbits[run.ballOrbit];
    for (final slot in orbit.slots) {
      slot.kind = SlotKind.safe;
      slot.consumed = false;
    }
    final idx = orbit.slotIndexForAngle(run.ballAngle);
    for (int k = 0; k < 3; k++) {
      orbit.slots[(idx + k) % orbit.slotCount].kind = SlotKind.obstacle;
    }
    run.invulnTimer = 0.08;
    run.update(0.016);
    expect(run.gameOver, isFalse);
    for (int i = 0; i < 6; i++) {
      run.update(0.05);
    }
    expect(run.gameOver, isTrue);
  });

  test('shifting onto a mine is fatal once the shift lands', () {
    final run = RunController(modifiers: RunModifiers.none, seed: 8);
    final dest = run.orbits[0];
    for (final slot in dest.slots) {
      slot.kind = SlotKind.obstacle;
      slot.consumed = false;
    }
    run.attemptShift(-1);
    for (int i = 0; i < 25; i++) {
      run.update(0.02);
    }
    expect(run.gameOver, isTrue);
  });

  test('lethals never spawn on or just ahead of the ball', () {
    bool isLethalKind(SlotKind kind, bool consumed) =>
        !consumed &&
        (kind == SlotKind.obstacle ||
            kind == SlotKind.breach ||
            kind == SlotKind.voidZone);

    for (final seed in [2, 9, 21]) {
      final run = RunController(modifiers: RunModifiers.none, seed: seed);
      for (int step = 0; step < 500; step++) {
        if (run.gameOver) break;
        final count = GameBalance.slotsPerOrbit;
        final current = run.orbits[0].slotIndexForAngle(run.ballAngle);
        final snap = <(int, int), (SlotKind, bool)>{};
        for (int o = 0; o < run.band.activeOrbits; o++) {
          for (int s = 0; s < count; s++) {
            final slot = run.orbits[o].slots[s];
            snap[(o, s)] = (slot.kind, slot.consumed);
          }
        }
        run.update(0.03);
        if (run.gameOver) break;
        final need = GameBalance.spawnClearanceSlots(run.speed);
        for (int o = 0; o < run.band.activeOrbits; o++) {
          for (int s = 0; s < count; s++) {
            final before = snap[(o, s)]!;
            final now = run.orbits[o].slots[s];
            final spawned = isLethalKind(now.kind, now.consumed) &&
                !isLethalKind(before.$1, before.$2) &&
                before.$1 != SlotKind.cracked;
            if (!spawned) continue;
            final ahead = (s - current + count) % count;
            expect(
              ahead > need && ahead < count - 1,
              isTrue,
              reason: 'seed $seed: lethal appeared at orbit $o slot $s '
                  '(ahead=$ahead, need=$need)',
            );
          }
        }
      }
    }
  });

  test('sprites keep a slot of space around them', () {
    final run = RunController(modifiers: RunModifiers.none, seed: 19);
    for (int i = 0; i < 400; i++) {
      run.update(0.04);
    }
    final active = run.band.activeOrbits;
    for (int o = 0; o < active; o++) {
      final orbit = run.orbits[o];
      for (int s = 0; s < orbit.slotCount; s++) {
        if (!orbit.slots[s].hasContent) continue;
        expect(orbit.slots[(s + 1) % orbit.slotCount].hasContent, isFalse);
        if (o + 1 < active) {
          expect(run.orbits[o + 1].slots[s].hasContent, isFalse);
        }
      }
    }
  });

  test('a sealed column always leaves one obstacle-free escape', () {
    bool isLethal(TrackSlot slot) =>
        slot.isDeadly || (slot.kind == SlotKind.voidZone && !slot.consumed);

    for (final seed in [1, 8, 17]) {
      final run = RunController(modifiers: RunModifiers.none, seed: seed);
      for (int i = 0; i < 400; i++) {
        run.update(0.04);
        if (run.gameOver) break;
      }
      final active = run.band.activeOrbits;
      for (int s = 0; s < GameBalance.slotsPerOrbit; s++) {
        final openOrbits = <int>[];
        for (int o = 0; o < active; o++) {
          if (!isLethal(run.orbits[o].slots[s])) {
            openOrbits.add(o);
          }
        }
        expect(
          openOrbits,
          isNotEmpty,
          reason: 'seed $seed: every live lane is lethal at slot $s',
        );
        if (openOrbits.length == 1) {
          expect(
            isLethal(run.orbits[openOrbits.single].slots[s]),
            isFalse,
            reason: 'seed $seed: last open lane at slot $s still has a hazard',
          );
        }
      }
    }
  });

  test('lethals are never adjacent on a live lane', () {
    final run = RunController(modifiers: RunModifiers.none, seed: 11);
    for (int i = 0; i < 500; i++) {
      run.update(0.04);
    }
    bool isLethal(TrackSlot slot) =>
        slot.isDeadly || (slot.kind == SlotKind.voidZone && !slot.consumed);
    for (final orbit in run.orbits.take(run.band.activeOrbits)) {
      for (int s = 0; s < orbit.slotCount; s++) {
        expect(
          isLethal(orbit.slots[s]) &&
              isLethal(orbit.slots[(s + 1) % orbit.slotCount]),
          isFalse,
        );
      }
    }
  });
}
