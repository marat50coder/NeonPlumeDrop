import '../core/game_balance.dart';
import '../core/profile_service.dart';
import '../models/catalog.dart';

/// Snapshot of every permanent-upgrade bonus that affects a single run,
/// computed once from [ProfileService] when a run starts.
class RunModifiers {
  const RunModifiers({
    required this.startingEnergyBonus,
    required this.shiftDurationMult,
    required this.shieldDurationMult,
    required this.energyGainMult,
    required this.shieldChanceBonus,
    required this.prismChanceBonus,
  });

  final double startingEnergyBonus;
  final double shiftDurationMult;
  final double shieldDurationMult;
  final double energyGainMult;
  final double shieldChanceBonus;
  final double prismChanceBonus;

  factory RunModifiers.fromProfile(ProfileService profile) {
    double frac(UpgradeId id, double maxBonus) {
      final def = GameCatalog.upgradeById(id);
      final level = profile.upgradeLevel(id);
      return maxBonus * (level / def.maxLevel);
    }

    final shiftBonus = frac(UpgradeId.shiftPower, GameBalance.shiftPowerMaxBonus);
    final shieldDurBonus =
        frac(UpgradeId.shieldDuration, GameBalance.shieldDurationMaxBonus);

    return RunModifiers(
      startingEnergyBonus:
          frac(UpgradeId.energyCapacity, GameBalance.energyCapacityMaxBonus),
      shiftDurationMult: 1.0 - shiftBonus,
      shieldDurationMult: 1.0 + shieldDurBonus,
      energyGainMult:
          1.0 + frac(UpgradeId.energyGain, GameBalance.energyGainMaxBonus),
      shieldChanceBonus:
          frac(UpgradeId.shieldChance, GameBalance.shieldChanceMaxBonus),
      prismChanceBonus:
          frac(UpgradeId.rareDropChance, GameBalance.prismChanceMaxBonus),
    );
  }

  static const RunModifiers none = RunModifiers(
    startingEnergyBonus: 0,
    shiftDurationMult: 1,
    shieldDurationMult: 1,
    energyGainMult: 1,
    shieldChanceBonus: 0,
    prismChanceBonus: 0,
  );
}
