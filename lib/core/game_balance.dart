/// Tunable balance constants for a Neon Plume Drop run.
///
/// Values follow section 14 ("ИГРОВОЙ БАЛАНС") of the game design notes:
/// difficulty ramps through named collapse phases by increasing speed,
/// obstacle density and destroyed-track frequency while always leaving the
/// player at least one reachable safe lane.
library;

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

  /// Base angular speed of the ball in radians/second at Phase 1. Scaled up
  /// alongside the drop in [slotsPerOrbit] to keep the decisions-per-second
  /// pace of a run unchanged.
  static const double baseAngularSpeed = 0.95;

  static const List<PhaseBand> bands = [
    PhaseBand(
      phase: CollapsePhase.phase1,
      startSeconds: 0,
      speedStart: 1.0,
      speedEnd: 1.0,
      activeOrbits: 3,
      hazardDensity: 0.13,
      pickupDensity: 0.15,
      rewardMultiplier: 1.0,
    ),
    PhaseBand(
      phase: CollapsePhase.phase2,
      startSeconds: 35,
      speedStart: 1.08,
      speedEnd: 1.16,
      activeOrbits: 3,
      hazardDensity: 0.18,
      pickupDensity: 0.15,
      rewardMultiplier: 1.15,
    ),
    PhaseBand(
      phase: CollapsePhase.phase3,
      startSeconds: 70,
      speedStart: 1.16,
      speedEnd: 1.24,
      activeOrbits: 4,
      hazardDensity: 0.23,
      pickupDensity: 0.15,
      rewardMultiplier: 1.3,
    ),
    PhaseBand(
      phase: CollapsePhase.overload,
      startSeconds: 105,
      speedStart: 1.28,
      speedEnd: 1.42,
      activeOrbits: 5,
      hazardDensity: 0.29,
      pickupDensity: 0.15,
      rewardMultiplier: 1.55,
    ),
    PhaseBand(
      phase: CollapsePhase.criticalCollapse,
      startSeconds: 150,
      speedStart: 1.48,
      speedEnd: 1.62,
      activeOrbits: 5,
      hazardDensity: 0.35,
      pickupDensity: 0.15,
      rewardMultiplier: 1.9,
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
  static const double shiftInvulnerabilityMs = 140;
  static const double voidGraceMs = 750;
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
