import 'dart:math';

import '../core/game_balance.dart';
import 'game_models.dart';

class RollModifiers {
  const RollModifiers({
    this.shieldChanceBonus = 0,
    this.prismChanceBonus = 0,
    this.hazardScale = 1.0,
    this.rewardScale = 1.0,
  });

  final double shieldChanceBonus;
  final double prismChanceBonus;
  final double hazardScale;
  final double rewardScale;
}

T weightedPick<T>(Random rng, List<MapEntry<T, double>> weights) {
  final total = weights.fold<double>(0, (sum, e) => sum + e.value);
  double roll = rng.nextDouble() * total;
  for (final entry in weights) {
    if (roll < entry.value) return entry.key;
    roll -= entry.value;
  }
  return weights.last.key;
}

/// How a family's share is split between its members. Fixed ratios, so the
/// phase bands only have to decide *how much* of the field each family covers.
const _dangerSplit = <SlotKind, double>{
  SlotKind.obstacle: 0.42,
  SlotKind.breach: 0.26,
  SlotKind.cracked: 0.18,
  SlotKind.voidZone: 0.14,
};

const _gateSplit = <SlotKind, double>{
  SlotKind.gateEnergy: 0.42,
  SlotKind.gateSurge: 0.33,
  SlotKind.gateGhost: 0.25,
};

/// Baseline share of slots holding a gate. Low on purpose: gates are the
/// moments a run turns on, and they only feel that way if they are rare.
const double _gateDensity = 0.04;

/// Rolls the content for a track slot that is about to re-enter play.
///
/// [innerness] is 0 for the outermost live lane and 1 for the innermost. Inner
/// lanes are the greedy line: more danger, but also the only place the rarest
/// pickups appear.
///
/// The resulting field starts mostly empty and tightens as later bands drop
/// the empty floor. Objects only read as meaningful when there is track
/// between them.
TrackSlot rollSlot({
  required Random rng,
  required double innerness,
  required PhaseBand band,
  required RollModifiers mods,
}) {
  final danger =
      band.hazardDensity * mods.hazardScale * (0.7 + innerness * 0.6);
  final pickups =
      band.pickupDensity * mods.rewardScale * (0.75 + innerness * 0.5);
  final gates = _gateDensity * mods.rewardScale;
  final emptyFloor = band.startSeconds >= 120
      ? 0.16
      : band.startSeconds >= 80
          ? 0.22
          : 0.32;
  final empty = max(emptyFloor, 1.0 - danger - pickups - gates);

  // Pickup mix: energy is the staple, shards the currency, shields the
  // lifeline, prisms the jackpot -- and prisms only spawn on inner lanes.
  final shieldShare = 0.14 * (1 + mods.shieldChanceBonus * 6);
  final prismShare = 0.05 * innerness * (1 + mods.prismChanceBonus * 8);
  final shardShare = 0.26 * (0.5 + innerness * 0.5);
  final energyShare = max(0.1, 1.0 - shieldShare - prismShare - shardShare);

  final weights = <MapEntry<SlotKind, double>>[
    MapEntry(SlotKind.safe, empty),
    for (final entry in _dangerSplit.entries)
      MapEntry(entry.key, danger * entry.value),
    MapEntry(SlotKind.energy, pickups * energyShare),
    MapEntry(SlotKind.shard, pickups * shardShare),
    MapEntry(SlotKind.shield, pickups * shieldShare),
    MapEntry(SlotKind.prism, pickups * prismShare),
    for (final entry in _gateSplit.entries)
      MapEntry(entry.key, gates * entry.value),
  ];

  final kind = weightedPick(rng, weights);
  return TrackSlot(
    kind: kind,
    variant: rng.nextInt(4),
  );
}
