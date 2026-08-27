import '../core/game_balance.dart';

class RunSummary {
  RunSummary({
    required this.survivalSeconds,
    required this.phaseReached,
    required this.neonEnergyEarned,
    required this.crystalShardsEarned,
    required this.gatesActivated,
    required this.isNewBestTime,
    required this.isNewBestPhase,
  });

  final double survivalSeconds;
  final CollapsePhase phaseReached;
  final int neonEnergyEarned;
  final int crystalShardsEarned;
  final int gatesActivated;
  final bool isNewBestTime;
  final bool isNewBestPhase;

  String get formattedTime {
    final total = survivalSeconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Raw numbers gathered directly from a finished [RunController] run,
/// before persistence-layer "new record" flags are known.
class RawRunStats {
  RawRunStats({
    required this.survivalSeconds,
    required this.phaseIndex1,
    required this.neonEnergyEarned,
    required this.crystalShardsEarned,
    required this.gatesActivated,
    required this.maxNoHitStreak,
  });

  final double survivalSeconds;
  final int phaseIndex1;
  final int neonEnergyEarned;
  final int crystalShardsEarned;
  final int gatesActivated;
  final double maxNoHitStreak;
}
