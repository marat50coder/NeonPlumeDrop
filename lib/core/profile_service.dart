import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../models/daily_challenge.dart';

/// Persisted player progression: currencies, unlocks, upgrades, records and
/// settings. A single JSON blob is stored under [_kKey] for simplicity.
class ProfileService extends ChangeNotifier {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  static const String _kKey = 'neon_plume_drop.profile.v1';

  SharedPreferences? _prefs;
  bool _ready = false;
  bool get ready => _ready;

  int neonEnergy = 0;
  int crystalShards = 0;

  double bestSurvivalSeconds = 0;
  int bestPhaseIndex1 = 0; // 1..5
  int bestNeonEnergyRun = 0;
  int bestCrystalShardsRun = 0;
  int totalRuns = 0;
  int criticalCollapseClears = 0;

  String selectedBallId = 'cyan_pulse';
  Set<String> unlockedBallIds = {'cyan_pulse'};

  String selectedSectorId = 'deep_neon_space';
  Set<String> unlockedSectorIds = {'deep_neon_space'};
  Set<String> unlockedMedalIds = {};

  Map<String, int> upgradeLevels = {};

  double sfxVolume = 0.9;
  bool vibrationEnabled = true;
  bool tutorialCompleted = false;

  DailyChallenge? dailyChallenge;

  int upgradeLevel(UpgradeId id) => upgradeLevels[id.name] ?? 0;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final raw = prefs.getString(_kKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _fromJson(map);
      }
    } catch (_) {
      // Unavailable or corrupt storage: play on with defaults. Progress
      // simply won't survive a restart, which beats refusing to start.
    }
    _ensureDailyChallenge();
    if (_syncTimeMedalsFromBest()) {
      await _persist();
    }
    _ready = true;
    notifyListeners();
  }

  void _ensureDailyChallenge() {
    final today = DateTime.now();
    final key = '${today.year}-${today.month}-${today.day}';
    if (dailyChallenge == null || dailyChallenge!.dateKey != key) {
      dailyChallenge = DailyChallenge.forDate(today);
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(_kKey, jsonEncode(_toJson()));
    } catch (_) {
      // A failed write must not tear down the UI that triggered it.
    }
  }

  Map<String, dynamic> _toJson() => {
    'neonEnergy': neonEnergy,
    'crystalShards': crystalShards,
    'bestSurvivalSeconds': bestSurvivalSeconds,
    'bestPhaseIndex1': bestPhaseIndex1,
    'bestNeonEnergyRun': bestNeonEnergyRun,
    'bestCrystalShardsRun': bestCrystalShardsRun,
    'totalRuns': totalRuns,
    'criticalCollapseClears': criticalCollapseClears,
    'selectedBallId': selectedBallId,
    'unlockedBallIds': unlockedBallIds.toList(),
    'selectedSectorId': selectedSectorId,
    'unlockedSectorIds': unlockedSectorIds.toList(),
    'unlockedMedalIds': unlockedMedalIds.toList(),
    'upgradeLevels': upgradeLevels,
    'sfxVolume': sfxVolume,
    'vibrationEnabled': vibrationEnabled,
    'tutorialCompleted': tutorialCompleted,
    'dailyChallenge': dailyChallenge?.toJson(),
  };

  void _fromJson(Map<String, dynamic> json) {
    neonEnergy = json['neonEnergy'] as int? ?? 0;
    crystalShards = json['crystalShards'] as int? ?? 0;
    bestSurvivalSeconds =
        (json['bestSurvivalSeconds'] as num?)?.toDouble() ?? 0;
    bestPhaseIndex1 = json['bestPhaseIndex1'] as int? ?? 0;
    bestNeonEnergyRun = json['bestNeonEnergyRun'] as int? ?? 0;
    bestCrystalShardsRun = json['bestCrystalShardsRun'] as int? ?? 0;
    totalRuns = json['totalRuns'] as int? ?? 0;
    criticalCollapseClears = json['criticalCollapseClears'] as int? ?? 0;
    selectedBallId = json['selectedBallId'] as String? ?? 'cyan_pulse';
    unlockedBallIds =
        ((json['unlockedBallIds'] as List?)?.cast<String>() ?? ['cyan_pulse'])
            .toSet();
    selectedSectorId = json['selectedSectorId'] as String? ?? 'deep_neon_space';
    unlockedSectorIds =
        ((json['unlockedSectorIds'] as List?)?.cast<String>() ??
                ['deep_neon_space'])
            .toSet();
    unlockedMedalIds =
        ((json['unlockedMedalIds'] as List?)?.cast<String>() ??
                const <String>[])
            .toSet();
    upgradeLevels = Map<String, int>.from(
      (json['upgradeLevels'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    sfxVolume = (json['sfxVolume'] as num?)?.toDouble() ?? 0.9;
    vibrationEnabled = json['vibrationEnabled'] as bool? ?? true;
    tutorialCompleted = json['tutorialCompleted'] as bool? ?? false;
    final dc = json['dailyChallenge'];
    if (dc != null) {
      dailyChallenge = DailyChallenge.fromJson(dc as Map<String, dynamic>);
    }
  }

  // ---- Mutators ---------------------------------------------------------

  Future<void> addCurrencies({int neon = 0, int shards = 0}) async {
    neonEnergy += neon;
    crystalShards += shards;
    await _persist();
    notifyListeners();
  }

  Future<bool> spendCrystalShards(int amount) async {
    if (crystalShards < amount) return false;
    crystalShards -= amount;
    await _persist();
    notifyListeners();
    return true;
  }

  Future<bool> spendNeonEnergy(int amount) async {
    if (neonEnergy < amount) return false;
    neonEnergy -= amount;
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> unlockBall(String id) async {
    unlockedBallIds.add(id);
    await _persist();
    notifyListeners();
  }

  Future<void> selectBall(String id) async {
    selectedBallId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> unlockSector(String id) async {
    unlockedSectorIds.add(id);
    await _persist();
    notifyListeners();
  }

  Future<void> selectSector(String id) async {
    selectedSectorId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> setUpgradeLevel(UpgradeId id, int level) async {
    upgradeLevels[id.name] = level;
    await _persist();
    notifyListeners();
  }

  Future<void> setSfxVolume(double v) async {
    sfxVolume = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setVibrationEnabled(bool v) async {
    vibrationEnabled = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setTutorialCompleted(bool v) async {
    tutorialCompleted = v;
    await _persist();
    notifyListeners();
  }

  Future<void> updateDailyProgress(int progress) async {
    _ensureDailyChallenge();
    final dc = dailyChallenge!;
    if (progress > dc.bestProgress) {
      dc.bestProgress = progress;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> claimDailyChallenge() async {
    _ensureDailyChallenge();
    final dc = dailyChallenge!;
    if (dc.isComplete && !dc.claimed) {
      dc.claimed = true;
      neonEnergy += DailyChallenge.rewardNeonEnergy;
      crystalShards += DailyChallenge.rewardCrystalShards;
      await _persist();
      notifyListeners();
    }
  }

  /// Grants time medals already earned by [bestSurvivalSeconds], so a player
  /// who survived a minute before this update still finds Neon Orbit unlocked.
  bool _syncTimeMedalsFromBest() {
    final before = unlockedMedalIds.length;
    for (final medal in TimeMedal.earnedBy(bestSurvivalSeconds)) {
      unlockedMedalIds.add(medal.id);
    }
    return unlockedMedalIds.length > before;
  }

  /// Applies the outcome of a finished run: currencies, records and unlocks.
  /// Returns whether new best records were set (used by the result screen).
  Future<({bool newTime, bool newPhase, List<TimeMedal> newMedals})>
  applyRunResult({
    required double survivalSeconds,
    required int phaseIndex1,
    required int neonEnergyEarned,
    required int crystalShardsEarned,
  }) async {
    totalRuns += 1;
    neonEnergy += neonEnergyEarned;
    crystalShards += crystalShardsEarned;

    final newTime = survivalSeconds > bestSurvivalSeconds;
    if (newTime) bestSurvivalSeconds = survivalSeconds;

    final newPhase = phaseIndex1 > bestPhaseIndex1;
    if (newPhase) bestPhaseIndex1 = phaseIndex1;

    if (neonEnergyEarned > bestNeonEnergyRun) {
      bestNeonEnergyRun = neonEnergyEarned;
    }
    if (crystalShardsEarned > bestCrystalShardsRun) {
      bestCrystalShardsRun = crystalShardsEarned;
    }
    if (phaseIndex1 >= 5) criticalCollapseClears += 1;

    // Cosmetic unlocks tied to best phase reached.
    for (final ball in GameCatalog.balls) {
      if (ball.unlockBestPhase > 0 &&
          bestPhaseIndex1 >= ball.unlockBestPhase &&
          !unlockedBallIds.contains(ball.id)) {
        unlockedBallIds.add(ball.id);
      }
    }
    for (final sector in GameCatalog.sectors) {
      final needsTwoClears = sector.id == 'holographic_cosmos';
      final requirementMet = needsTwoClears
          ? criticalCollapseClears >= 2
          : (sector.unlockBestPhase > 0 &&
                bestPhaseIndex1 >= sector.unlockBestPhase);
      if (requirementMet && !unlockedSectorIds.contains(sector.id)) {
        unlockedSectorIds.add(sector.id);
      }
    }

    final newlyEarned = <TimeMedal>[];
    for (final medal in TimeMedal.earnedBy(survivalSeconds)) {
      if (unlockedMedalIds.add(medal.id)) newlyEarned.add(medal);
    }

    await _persist();
    notifyListeners();
    return (newTime: newTime, newPhase: newPhase, newMedals: newlyEarned);
  }
}
