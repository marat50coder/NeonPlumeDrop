enum DailyChallengeType {
  survivePhases,
  collectShards,
  activateGates,
  surviveNoHitSeconds,
}

extension DailyChallengeTypeX on DailyChallengeType {
  String describe(int target) => switch (this) {
        DailyChallengeType.survivePhases =>
          'Survive $target collapse phases in one run',
        DailyChallengeType.collectShards =>
          'Collect $target Crystal Shards in one run',
        DailyChallengeType.activateGates =>
          'Activate $target Energy Gates in one run',
        DailyChallengeType.surviveNoHitSeconds =>
          'Survive $target seconds without taking a hit',
      };
}

class DailyChallenge {
  DailyChallenge({
    required this.dateKey,
    required this.type,
    required this.target,
    this.bestProgress = 0,
    this.claimed = false,
  });

  final String dateKey;
  final DailyChallengeType type;
  final int target;
  int bestProgress;
  bool claimed;

  bool get isComplete => bestProgress >= target;

  static const int rewardNeonEnergy = 800;
  static const int rewardCrystalShards = 25;

  factory DailyChallenge.forDate(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';
    final seed = date.year * 372 + date.month * 31 + date.day;
    final type = DailyChallengeType.values[seed % DailyChallengeType.values.length];
    final target = switch (type) {
      DailyChallengeType.survivePhases => 2 + (seed % 3),
      DailyChallengeType.collectShards => 8 + (seed % 12),
      DailyChallengeType.activateGates => 3 + (seed % 5),
      DailyChallengeType.surviveNoHitSeconds => 20 + (seed % 25),
    };
    return DailyChallenge(dateKey: key, type: type, target: target);
  }

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'type': type.index,
        'target': target,
        'bestProgress': bestProgress,
        'claimed': claimed,
      };

  factory DailyChallenge.fromJson(Map<String, dynamic> json) => DailyChallenge(
        dateKey: json['dateKey'] as String,
        type: DailyChallengeType.values[json['type'] as int],
        target: json['target'] as int,
        bestProgress: json['bestProgress'] as int? ?? 0,
        claimed: json['claimed'] as bool? ?? false,
      );
}
