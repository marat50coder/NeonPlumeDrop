/// Tunable balance constants for a Neon Plume Drop run.
///
/// Values follow section 14 ("ИГРОВОЙ БАЛАНС") of the game design notes:
/// difficulty ramps through named collapse phases by increasing speed,
/// obstacle density and destroyed-track frequency while always leaving the
/// player at least one reachable safe lane.
library;

import 'dart:math';

enum CollapsePhase { phase1, phase2, phase3, overload, criticalCollapse }

extension CollapsePhaseX on CollapsePhase {
  String get label => switch (this) {
        CollapsePhase.phase1 => 'Phase 1',
        CollapsePhase.phase2 => 'Phase 2',
        CollapsePhase.phase3 => 'Phase 3',
        CollapsePhase.overload => 'Overload',
        CollapsePhase.criticalCollapse => 'Critical Collapse',
      };

  int get index1 => switch (this) {
        CollapsePhase.phase1 => 1,
        CollapsePhase.phase2 => 2,
        CollapsePhase.phase3 => 3,
        CollapsePhase.overload => 4,
        CollapsePhase.criticalCollapse => 5,
      };
}

class PhaseBand {
  const PhaseBand({
    required this.phase,
    required this.startSeconds,
    required this.speedStart,
    required this.speedEnd,
    required this.activeOrbits,
    required this.hazardDensity,
    required this.pickupDensity,
    required this.rewardMultiplier,
  });

  final CollapsePhase phase;
  final double startSeconds;
  final double speedStart;
  final double speedEnd;
  final int activeOrbits;

  /// Share of slots carrying something from the danger family.
  final double hazardDensity;

  /// Share of slots carrying a pickup. Held flat across phases -- later phases
  /// pay more per pickup via [rewardMultiplier] rather than burying the field
  /// in more of them.
  final double pickupDensity;

  final double rewardMultiplier;
}

class GameBalance {
  GameBalance._();

  static const int totalOrbits = 5;

  /// Angular slices per lane. Deliberately coarse: at 22 slices the outer lane
  /// carried so many small objects that nothing on it could be told apart at a
  /// glance, which is the readability problem the whole content vocabulary is
  /// built around.
  static const int slotsPerOrbit = 14;

  /// Base angular speed of the ball in radians/second at Phase 1.
  static const double baseAngularSpeed = 1.02;

  /// How far ahead a new lethal may appear, in seconds of travel. Anything
  /// closer would materialise on the ball or leave no time to shift.
  static const double spawnClearanceSeconds = 0.95;

  /// Minimum number of empty slots ahead of the ball on every lane.
  static const int minSpawnAheadSlots = 4;

  /// How many upcoming slots (including the current one) must stay free of
  /// newly planted lethals, given the live [speed] in rad/s.
  static int spawnClearanceSlots(double speed) {
    final width = 2 * pi / slotsPerOrbit;
    final timePerSlot = width / speed.clamp(0.35, 4.0);
    final need = (spawnClearanceSeconds / timePerSlot).ceil();
    return max(minSpawnAheadSlots, min(6, need));
  }

  static const List<PhaseBand> bands = [
    PhaseBand(
      phase: CollapsePhase.phase1,
      startSeconds: 0,
      speedStart: 0.88,
      speedEnd: 0.94,
      activeOrbits: 3,
      hazardDensity: 0.07,
      pickupDensity: 0.14,
      rewardMultiplier: 1.0,
    ),
    PhaseBand(
      phase: CollapsePhase.phase1,
      startSeconds: 20,
      speedStart: 0.96,
      speedEnd: 1.04,
      activeOrbits: 3,
      hazardDensity: 0.11,
      pickupDensity: 0.13,
      rewardMultiplier: 1.05,
    ),
    PhaseBand(
      phase: CollapsePhase.phase2,
      startSeconds: 40,
      speedStart: 1.06,
      speedEnd: 1.14,
      activeOrbits: 3,
      hazardDensity: 0.15,
      pickupDensity: 0.12,
      rewardMultiplier: 1.15,
    ),
    PhaseBand(
      phase: CollapsePhase.phase2,
      startSeconds: 60,
      speedStart: 1.16,
      speedEnd: 1.26,
      activeOrbits: 4,
      hazardDensity: 0.19,
      pickupDensity: 0.12,
      rewardMultiplier: 1.25,
    ),
    PhaseBand(
      phase: CollapsePhase.phase3,
      startSeconds: 80,
      speedStart: 1.28,
      speedEnd: 1.40,
      activeOrbits: 4,
      hazardDensity: 0.24,
      pickupDensity: 0.11,
      rewardMultiplier: 1.4,
    ),
    PhaseBand(
      phase: CollapsePhase.overload,
      startSeconds: 100,
      speedStart: 1.44,
      speedEnd: 1.58,
      activeOrbits: 5,
      hazardDensity: 0.29,
      pickupDensity: 0.11,
      rewardMultiplier: 1.6,
    ),
    PhaseBand(
      phase: CollapsePhase.criticalCollapse,
      startSeconds: 120,
      speedStart: 1.64,
      speedEnd: 1.82,
      activeOrbits: 5,
      hazardDensity: 0.35,
      pickupDensity: 0.10,
      rewardMultiplier: 1.9,
    ),
    PhaseBand(
      phase: CollapsePhase.criticalCollapse,
      startSeconds: 140,
      speedStart: 1.84,
      speedEnd: 1.98,
      activeOrbits: 5,
      hazardDensity: 0.40,
      pickupDensity: 0.09,
      rewardMultiplier: 2.2,
    ),
  ];

  static PhaseBand bandFor(double elapsedSeconds) {
    PhaseBand current = bands.first;
    for (final band in bands) {
      if (elapsedSeconds >= band.startSeconds) {
        current = band;
      }
    }
    return current;
  }

  static PhaseBand? nextBandAfter(PhaseBand band) {
    final i = bands.indexOf(band);
    if (i < 0 || i == bands.length - 1) return null;
    return bands[i + 1];
  }

  static double speedMultiplierFor(double elapsedSeconds) {
    final band = bandFor(elapsedSeconds);
    final next = nextBandAfter(band);
    final bandDuration = (next?.startSeconds ?? band.startSeconds + 60) -
        band.startSeconds;
    final t = bandDuration <= 0
        ? 1.0
        : ((elapsedSeconds - band.startSeconds) / bandDuration).clamp(0.0, 1.0);
    return band.speedStart + (band.speedEnd - band.speedStart) * t;
  }

  /// Innermost lane radius as a fraction of the play-field radius, clearing
  /// the central core and its glow.
  static const double innermostLane = 0.34;

  /// Outermost lane radius. Leaves room for the ball's own radius plus its
  /// glow so nothing on the outer lane is clipped by the field edge.
  static const double outermostLane = 0.88;

  /// Lane radii as a fraction (0..1) of the play-field radius, innermost
  /// first.
  ///
  /// Crucially these are spread over the lanes that are *live right now*, not
  /// over all [totalOrbits]. Phase 1 runs three lanes, and pre-allocating five
  /// slices left the whole early game crammed into the middle 57% of the field
  /// -- the player was watching the action through a keyhole. Now three lanes
  /// fill the field and the ring spacing tightens as later phases add lanes,
  /// which also reads as the arena growing.
  ///
  /// Entries past [activeOrbits] keep marching outward at the same pitch, so a
  /// stale index never resolves to a nonsense radius.
  static List<double> orbitRadiusFractionsFor(int activeOrbits) {
    final lanes = activeOrbits.clamp(1, totalOrbits);
    final step = lanes == 1 ? 0.0 : (outermostLane - innermostLane) / (lanes - 1);
    return List.generate(totalOrbits, (i) => innermostLane + step * i);
  }

  /// How long the lane spacing takes to settle after a phase adds a lane.
  static const double laneReflowSeconds = 1.1;

  static const double shiftDurationMs = 220;
  static const double voidGraceMs = 900;
  static const double hitInvulnerabilityMs = 1100;

  static const int maxShields = 3;

  // Upgrade caps, per the design notes (section 14, "БАЛАНС УЛУЧШЕНИЙ").
  // Per-upgrade level counts live on each [UpgradeDef] in the catalog.
  static const double energyCapacityMaxBonus = 0.20;
  static const double energyGainMaxBonus = 0.25;
  static const double shieldChanceMaxBonus = 0.10;
  static const double prismChanceMaxBonus = 0.08;
  static const double shiftPowerMaxBonus = 0.35;
  static const double shieldDurationMaxBonus = 0.6;
}
