import 'dart:math';

import '../core/game_balance.dart';
import '../models/run_summary.dart';
import 'content_tables.dart';
import 'game_models.dart';
import 'run_modifiers.dart';

enum GameSfxEvent {
  orbitalShift,
  shiftDenied,
  collectEnergy,
  collectRare,
  gateActivate,
  shieldActivate,
  collision,
  dangerWarning,
  sectorPortal,
  defeat,
}

/// Pure-Dart simulation of a single Neon Plume Drop run. Knows nothing
/// about Flutter widgets, painting or audio playback -- the game screen
/// drives it with [update] every frame, reads its public fields to render,
/// and drains [drainSfxEvents] to trigger sound/haptics.
class RunController {
  RunController({required this.modifiers, int? seed})
      : rng = Random(seed),
        orbits = List.generate(
          GameBalance.totalOrbits,
          (i) => Orbit(index: i, slotCount: GameBalance.slotsPerOrbit),
        ) {
    final initial = GameBalance.bands.first.activeOrbits;
    _laneRadii = GameBalance.orbitRadiusFractionsFor(initial);
    _laneRadiiFrom = List.of(_laneRadii);
    _laneRadiiTo = List.of(_laneRadii);
    for (final orbit in orbits) {
      _regenEdge[orbit.index] = -pi;
    }
    neonEnergyRun = (modifiers.startingEnergyBonus * 200).round();
    _seedOpeningField();
  }

  final RunModifiers modifiers;
  final Random rng;
  final List<Orbit> orbits;
  final List<Drone> drones = [];
  final List<FloatingText> floatingTexts = [];
  final List<ParticleBurst> particles = [];
  final List<GameSfxEvent> _sfxQueue = [];

  double elapsedSeconds = 0;
  double ballAngle = -pi / 2;
  int ballOrbit = 1;

  bool shifting = false;
  int shiftFrom = 0;
  int shiftTo = 0;
  double shiftT = 0;

  int shields = 0;
  double invulnTimer = 0;
  double phaseGhostTimer = 0;
  double shiftBoostTimer = 0;
  double prismShiftTimer = 0;

  double screenShake = 0;
  bool gameOver = false;

  int neonEnergyRun = 0;
  int crystalShardsRun = 0;
  int gatesActivatedRun = 0;
  double noHitTimer = 0;
  double maxNoHitStreak = 0;

  final Map<int, double> _regenEdge = {};
  final Map<int, int> _lastSlotIndex = {};
  int _lastActiveOrbits = GameBalance.bands.first.activeOrbits;

  // Lane radii re-spread whenever a phase adds a lane, easing between the old
  // and new layout so the arena visibly grows instead of snapping.
  late List<double> _laneRadii;
  late List<double> _laneRadiiFrom;
  late List<double> _laneRadiiTo;
  double _laneReflow = 1.0;

  double? voidGraceTimer;
  int? voidGraceOrbit;
  int? voidGraceSlot;

  // Core collapse state machine ------------------------------------------
  _CoreSub _coreSub = _CoreSub.calm;
  double _coreTimer = 10;
  int _coreSequence = 0;
  CoreState? _activeHazardKind;
  int? _pulseOrbit;
  int _pulseStartSlot = 0;
  int _pulseSlotCount = 3;
  int _expandOrbitCount = 0;
  final List<(int, int)> _collapseCells = [];

  CoreState get coreVisualState => _activeHazardKind ?? CoreState.stable;
  bool get coreWarning => _coreSub == _CoreSub.warning;

  PhaseBand get band => GameBalance.bandFor(elapsedSeconds);

  /// Live lane radii as fractions of the field radius, mid-reflow included.
  List<double> get laneRadii => _laneRadii;

  double laneRadius(int orbitIndex) =>
      _laneRadii[orbitIndex.clamp(0, _laneRadii.length - 1)];

  double get speed =>
      GameBalance.baseAngularSpeed *
      GameBalance.speedMultiplierFor(elapsedSeconds);

  double get shiftDurationSeconds {
    final base = GameBalance.shiftDurationMs / 1000 * modifiers.shiftDurationMult;
    return shiftBoostTimer > 0 ? base * 0.55 : base;
  }

  /// Radius of the ball right now, following the shift arc between lanes.
  double get ballRadiusFraction {
    if (!shifting) return laneRadius(ballOrbit);
    final t = _easeInOutQuad(shiftT);
    return laneRadius(shiftFrom) + (laneRadius(shiftTo) - laneRadius(shiftFrom)) * t;
  }

  /// First lethal on the ball's lane at or ahead of it. The painter uses this
  /// to breathe a red ping on the next mine, so the player can read it at a
  /// glance without scanning the whole ring.
  int? get nearestLethalAhead {
    if (ballOrbit < 0 || ballOrbit >= band.activeOrbits) return null;
    final orbit = orbits[ballOrbit];
    final current = orbit.slotIndexForAngle(ballAngle);
    for (int k = 0; k < orbit.slotCount; k++) {
      final s = (current + k) % orbit.slotCount;
      if (_isLethal(orbit.slots[s])) return s;
    }
    return null;
  }

  static double _easeInOutQuad(double t) {
    return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2;
  }

  List<GameSfxEvent> drainSfxEvents() {
    final events = List<GameSfxEvent>.from(_sfxQueue);
    _sfxQueue.clear();
    return events;
  }

  void attemptShift(int direction) {
    if (gameOver || shifting) return;
    final activeOrbits = band.activeOrbits;
    final target = ballOrbit + direction;
    if (target < 0 || target >= activeOrbits) {
      _sfxQueue.add(GameSfxEvent.shiftDenied);
      return;
    }
    shifting = true;
    shiftFrom = ballOrbit;
    shiftTo = target;
    shiftT = 0;
    // Committing to a shift is committing to leaving this lane, so a Void
    // Well the player is currently escaping can no longer claim them -- the
    // shift outlasts the shift i-frames, which used to leave a short window
    // where reacting in time still killed you.
    _clearVoidGrace();
    _sfxQueue.add(GameSfxEvent.orbitalShift);
  }

  void update(double dt) {
    if (gameOver) return;
    dt = dt.clamp(0, 0.05);
    elapsedSeconds += dt;
    noHitTimer += dt;
    maxNoHitStreak = max(maxNoHitStreak, noHitTimer);

    if (invulnTimer > 0) invulnTimer = max(0, invulnTimer - dt);
    if (phaseGhostTimer > 0) phaseGhostTimer = max(0, phaseGhostTimer - dt);
    if (shiftBoostTimer > 0) shiftBoostTimer = max(0, shiftBoostTimer - dt);
    if (prismShiftTimer > 0) prismShiftTimer = max(0, prismShiftTimer - dt);
    if (screenShake > 0) screenShake = max(0, screenShake - dt * 2.2);

    final prevAngle = ballAngle;
    ballAngle += speed * dt;

    if (shifting) {
      shiftT += dt / shiftDurationSeconds;
      if (shiftT >= 1) {
        shifting = false;
        shiftT = 1;
        ballOrbit = shiftTo;
        _lastSlotIndex[ballOrbit] = -1;
      }
    }

    _updateCoreStateMachine(dt);
    _handleActiveOrbitsChange();
    _advanceLaneReflow(dt);
    _sweepRegeneration();
    _updateDrones(dt);
    if (!shifting) _resolveCollisions(prevAngle, ballAngle);
    _updateVoidGrace(dt);
    _updateFloatingAndParticles(dt);
  }

  void _handleActiveOrbitsChange() {
    final active = band.activeOrbits;
    if (active == _lastActiveOrbits) return;
    for (int i = _lastActiveOrbits; i < active; i++) {
      for (final slot in orbits[i].slots) {
        slot.kind = SlotKind.safe;
        slot.consumed = false;
      }
      _regenEdge[i] = ballAngle - pi;
    }
    _lastActiveOrbits = active;
    _laneRadiiFrom = List.of(_laneRadii);
    _laneRadiiTo = GameBalance.orbitRadiusFractionsFor(active);
    _laneReflow = 0;
  }

  void _advanceLaneReflow(double dt) {
    if (_laneReflow >= 1) return;
    _laneReflow = min(1, _laneReflow + dt / GameBalance.laneReflowSeconds);
    final t = _easeInOutQuad(_laneReflow);
    _laneRadii = List.generate(
      _laneRadiiTo.length,
      (i) => _laneRadiiFrom[i] + (_laneRadiiTo[i] - _laneRadiiFrom[i]) * t,
    );
  }

  /// Fills the half-orbit ahead of the ball so the opening seconds of a run
  /// already have pickups, gates and hazards to read, instead of a blank rail.
  void _seedOpeningField() {
    final active = band.activeOrbits;
    final rollMods = RollModifiers(
      shieldChanceBonus: modifiers.shieldChanceBonus,
      prismChanceBonus: modifiers.prismChanceBonus,
    );
    for (int i = 0; i < active; i++) {
      final orbit = orbits[i];
      final innerness = active <= 1 ? 1.0 : 1 - (i / (active - 1));
      final current = orbit.slotIndexForAngle(ballAngle);
      for (int s = 0; s < orbit.slotCount; s++) {
        final ahead = (s - current + orbit.slotCount) % orbit.slotCount;
        if (ahead < GameBalance.minSpawnAheadSlots ||
            ahead > orbit.slotCount ~/ 2 + 1) {
          continue;
        }
        _plantSlot(
          i,
          s,
          rollSlot(
            rng: rng,
            innerness: innerness,
            band: band,
            mods: rollMods,
          ),
          active,
        );
      }
      _preventLethalCluster(i, 0);
    }
    for (int s = 0; s < GameBalance.slotsPerOrbit; s++) {
      _guaranteeEscapeLane(0, s, active);
    }
  }

  void _sweepRegeneration() {
    final activeOrbits = band.activeOrbits;
    final rollMods = RollModifiers(
      shieldChanceBonus: modifiers.shieldChanceBonus,
      prismChanceBonus: modifiers.prismChanceBonus,
      hazardScale: prismShiftTimer > 0 ? 1.15 : 1.0,
      rewardScale: prismShiftTimer > 0 ? 1.6 : 1.0,
    );
    final trailing = ballAngle - pi;
    for (int i = 0; i < activeOrbits; i++) {
      final orbit = orbits[i];
      final width = orbit.slotAngleWidth();
      double edge = _regenEdge[i] ?? (ballAngle - pi);
      final innerness = activeOrbits <= 1 ? 1.0 : 1 - (i / (activeOrbits - 1));
      int safety = 0;
      while (edge < trailing && safety < orbit.slotCount + 2) {
        final idx = orbit.slotIndexForAngle(edge);
        if (!_inSpawnClearance(idx)) {
          _plantSlot(
            i,
            idx,
            rollSlot(
              rng: rng,
              innerness: innerness,
              band: band,
              mods: rollMods,
            ),
            activeOrbits,
          );
        }
        edge += width;
        safety++;
      }
      _regenEdge[i] = edge;
    }
  }

  /// True when [slotIndex] is the cell the ball is on, the one it just left,
  /// or one it will reach before a player can react and shift.
  bool _inSpawnClearance(int slotIndex) {
    final count = GameBalance.slotsPerOrbit;
    final current = orbits[ballOrbit].slotIndexForAngle(ballAngle);
    final ahead = (slotIndex - current + count) % count;
    final need = GameBalance.spawnClearanceSlots(speed);
    return ahead <= need || ahead >= count - 1;
  }

  void _plantSlot(int orbitIndex, int slotIndex, TrackSlot rolled, int active) {
    if (_isLethal(rolled) && _inSpawnClearance(slotIndex)) {
      rolled = TrackSlot(kind: SlotKind.safe);
    }
    if (_isLethal(rolled) && _solePlayableOrbit() == orbitIndex) {
      rolled = TrackSlot(kind: SlotKind.safe);
    }
    orbits[orbitIndex].slots[slotIndex] = rolled;
    _givePersonalSpace(orbitIndex, slotIndex, active);
    _preventLethalCluster(orbitIndex, slotIndex);
    _guaranteeEscapeLane(orbitIndex, slotIndex, active);
  }

  /// Every sprite needs breathing room: no neighbour on the same lane, and no
  /// stacked sprite on the ring inside or outside at the same angle.
  void _givePersonalSpace(int orbitIndex, int slotIndex, int activeOrbits) {
    final orbit = orbits[orbitIndex];
    if (!orbit.slots[slotIndex].hasContent) return;
    final count = orbit.slotCount;
    final prev = orbit.slots[(slotIndex - 1 + count) % count];
    final next = orbit.slots[(slotIndex + 1) % count];
    if (prev.hasContent || next.hasContent) {
      orbit.slots[slotIndex] = TrackSlot(kind: SlotKind.safe);
      return;
    }
    for (final other in [orbitIndex - 1, orbitIndex + 1]) {
      if (other < 0 || other >= activeOrbits) continue;
      if (orbits[other].slots[slotIndex].hasContent) {
        orbit.slots[slotIndex] = TrackSlot(kind: SlotKind.safe);
        return;
      }
    }
  }

  static bool _isLethal(TrackSlot slot) =>
      slot.isDeadly || (slot.kind == SlotKind.voidZone && !slot.consumed);

  /// Two lethals back-to-back on one lane leave no beat to read the red ring
  /// and shift. Clear the newly rolled cell if it would stick to another hit.
  void _preventLethalCluster(int orbitIndex, int slotIndex) {
    final orbit = orbits[orbitIndex];
    final slot = orbit.slots[slotIndex];
    if (!_isLethal(slot)) return;
    final prev = orbit.slots[(slotIndex - 1 + orbit.slotCount) % orbit.slotCount];
    if (_isLethal(prev)) {
      orbit.slots[slotIndex] = TrackSlot(kind: SlotKind.safe);
    }
  }

  /// A lane is sealed at this angle if a core overlay covers it or the slot
  /// itself is lethal. If every live lane but one is sealed, that last lane
  /// has to be empty of obstacles -- otherwise the player has nowhere to go.
  bool _laneSealedAt(int orbitIndex, int slotIndex) {
    if (_orbitSealedByOverlay(orbitIndex, slotIndex)) return true;
    return _isLethal(orbits[orbitIndex].slots[slotIndex]);
  }

  bool _orbitSealedByOverlay(int orbitIndex, int slotIndex) {
    if (_activeHazardKind == null) return false;
    return _overlayCovers(orbitIndex, slotIndex);
  }

  /// While the core is expanding over the inner rings, the leftover playable
  /// orbit -- if there is only one -- must stay free of moving threats too.
  int? _solePlayableOrbit() {
    if (_activeHazardKind != CoreState.expand) return null;
    final remaining = band.activeOrbits - _expandOrbitCount;
    if (remaining != 1) return null;
    return _expandOrbitCount;
  }

  void _clearLethalAt(int orbitIndex, int slotIndex) {
    if (_isLethal(orbits[orbitIndex].slots[slotIndex])) {
      orbits[orbitIndex].slots[slotIndex] = TrackSlot(kind: SlotKind.safe);
    }
  }

  /// Lanes roll their content independently, so nothing stops every live lane
  /// from ending up lethal at the same angle -- an unavoidable death the player
  /// could not have played around. If only one lane is still open, that lane
  /// is cleared of obstacles so the player always has a path through.
  void _guaranteeEscapeLane(int rolledOrbit, int slotIndex, int activeOrbits) {
    final open = <int>[];
    for (int o = 0; o < activeOrbits; o++) {
      if (!_laneSealedAt(o, slotIndex)) open.add(o);
    }
    if (open.isEmpty) {
      orbits[rolledOrbit].slots[slotIndex] = TrackSlot(kind: SlotKind.safe);
      return;
    }
    if (open.length == 1) {
      _clearLethalAt(open.single, slotIndex);
    }
  }

  void _stripSoleEscapeOrbit() {
    final sole = _solePlayableOrbit();
    if (sole == null) return;
    for (int s = 0; s < GameBalance.slotsPerOrbit; s++) {
      _clearLethalAt(sole, s);
    }
    drones.removeWhere((d) => d.orbitIndex == sole);
  }

  /// Walks every slot crossed this frame. Lethals are tested every frame (so
  /// a mine still kills after i-frames fade). Pickups and gates fire once.
  void _resolveCollisions(double fromAngle, double toAngle) {
    final orbit = orbits[ballOrbit];
    var idx = orbit.slotIndexForAngle(fromAngle);
    final end = orbit.slotIndexForAngle(toAngle);
    int guard = 0;
    while (true) {
      final enter = _lastSlotIndex[ballOrbit] != idx;
      if (enter) {
        _collapseCrackedBehind(ballOrbit, _lastSlotIndex[ballOrbit]);
      }
      _touchSlot(ballOrbit, idx, enter: enter);
      _lastSlotIndex[ballOrbit] = idx;
      if (gameOver) return;
      if (idx == end || guard++ > orbit.slotCount) break;
      idx = (idx + 1) % orbit.slotCount;
    }
  }

  void _touchSlot(int orbitIndex, int slotIndex, {required bool enter}) {
    if (_overlayHazardAt(orbitIndex, slotIndex)) {
      _triggerHazard();
      return;
    }

    final orbit = orbits[orbitIndex];
    final slot = orbit.slots[slotIndex];
    if (slot.consumed) return;

    switch (slot.kind) {
      case SlotKind.safe:
        return;
      case SlotKind.cracked:
        return;
      case SlotKind.breach:
      case SlotKind.obstacle:
        _triggerHazard();
        return;
      case SlotKind.voidZone:
        if (voidGraceTimer != null &&
            voidGraceOrbit == orbitIndex &&
            voidGraceSlot == slotIndex) {
          return;
        }
        voidGraceOrbit = orbitIndex;
        voidGraceSlot = slotIndex;
        voidGraceTimer = GameBalance.voidGraceMs / 1000;
        return;
      case SlotKind.energy:
      case SlotKind.shard:
      case SlotKind.shield:
      case SlotKind.prism:
        if (!enter) return;
        _collect(slot.kind);
        slot.consumed = true;
        return;
      case SlotKind.gateEnergy:
      case SlotKind.gateGhost:
      case SlotKind.gateSurge:
        if (!enter) return;
        _activateGate(slot.kind, orbit, slotIndex);
        slot.consumed = true;
        return;
    }
  }

  void _collapseCrackedBehind(int orbitIndex, int? lastIndex) {
    if (lastIndex == null || lastIndex < 0) return;
    final slot = orbits[orbitIndex].slots[lastIndex];
    if (slot.kind != SlotKind.cracked) return;
    slot.kind = SlotKind.breach;
    particles.add(ParticleBurst(
      angle: ballAngle,
      radiusFraction: laneRadius(orbitIndex),
      color: 0xFFFFB020,
      life: 0.5,
    ));
  }

  void _clearVoidGrace() {
    voidGraceTimer = null;
    voidGraceOrbit = null;
    voidGraceSlot = null;
  }

  void _updateVoidGrace(double dt) {
    if (voidGraceTimer == null) return;
    if (voidGraceOrbit != ballOrbit) {
      _clearVoidGrace();
      return;
    }
    final orbit = orbits[ballOrbit];
    final currentSlot = orbit.slotIndexForAngle(ballAngle);
    if (currentSlot != voidGraceSlot) {
      _clearVoidGrace();
      return;
    }
    voidGraceTimer = voidGraceTimer! - dt;
    if (voidGraceTimer! <= 0) {
      voidGraceTimer = null;
      orbit.slots[currentSlot].consumed = true;
      _triggerHazard();
    }
  }

  /// Where a core-collapse strike stands, for one cell, so the renderer can
  /// telegraph it before it bites.
  ///
  /// The overlay used to be invisible for its whole 1.6s warning and then
  /// lethal without notice, which read as a random death.
  CoreStrike overlayStateFor(int orbitIndex, int slotIndex) {
    if (_activeHazardKind == null || _coreSub == _CoreSub.calm) {
      return CoreStrike.none;
    }
    if (!_overlayCovers(orbitIndex, slotIndex)) return CoreStrike.none;
    return _coreSub == _CoreSub.warning
        ? CoreStrike.telegraph
        : CoreStrike.lethal;
  }

  bool _overlayHazardAt(int orbitIndex, int slotIndex) =>
      overlayStateFor(orbitIndex, slotIndex) == CoreStrike.lethal;

  bool _overlayCovers(int orbitIndex, int slotIndex) {
    switch (_activeHazardKind!) {
      case CoreState.pulse:
        if (orbitIndex != _pulseOrbit) return false;
        final orbit = orbits[orbitIndex];
        for (int k = 0; k < _pulseSlotCount; k++) {
          if ((_pulseStartSlot + k) % orbit.slotCount == slotIndex) return true;
        }
        return false;
      case CoreState.expand:
        return orbitIndex < _expandOrbitCount;
      case CoreState.collapse:
        return _collapseCells.contains((orbitIndex, slotIndex));
      case CoreState.stable:
        return false;
    }
  }

  void _triggerHazard() {
    if (invulnTimer > 0 || phaseGhostTimer > 0) return;
    if (shields > 0) {
      shields -= 1;
      invulnTimer = max(
        invulnTimer,
        GameBalance.hitInvulnerabilityMs / 1000 * modifiers.shieldDurationMult,
      );
      _sfxQueue.add(GameSfxEvent.shieldActivate);
      screenShake = max(screenShake, 0.35);
      _floatReward('SHIELD', 0xFF33FFB0);
      maxNoHitStreak = max(maxNoHitStreak, noHitTimer);
      noHitTimer = 0;
      return;
    }
    maxNoHitStreak = max(maxNoHitStreak, noHitTimer);
    noHitTimer = 0;
    gameOver = true;
    screenShake = 1.0;
    _sfxQueue.add(GameSfxEvent.collision);
    _sfxQueue.add(GameSfxEvent.defeat);
    particles.add(ParticleBurst(
      angle: ballAngle,
      radiusFraction: laneRadius(ballOrbit),
      color: 0xFFFF2D55,
      life: 1.1,
    ));
  }

  /// Every Neon Energy award goes through here so the phase reward curve and
  /// the "Energy Gain" upgrade apply to *all* sources, exactly as the
  /// upgrade describes itself.
  int _awardEnergy(double base) {
    final amount = (base * band.rewardMultiplier * modifiers.energyGainMult).round();
    neonEnergyRun += amount;
    return amount;
  }

  void _collect(SlotKind kind) {
    switch (kind) {
      case SlotKind.energy:
        final amount = _awardEnergy(16);
        _floatReward('+$amount', 0xFF3DEFFF);
        _sfxQueue.add(GameSfxEvent.collectEnergy);
        break;
      case SlotKind.shard:
        final amount = elapsedSeconds > 100 && rng.nextDouble() < 0.3 ? 2 : 1;
        crystalShardsRun += amount;
        _floatReward('+$amount SHARD', 0xFFFF4FD8);
        _sfxQueue.add(GameSfxEvent.collectEnergy);
        break;
      case SlotKind.shield:
        shields = min(GameBalance.maxShields, shields + 1);
        _floatReward('SHIELD +1', 0xFF33FFB0);
        _sfxQueue.add(GameSfxEvent.collectEnergy);
        break;
      case SlotKind.prism:
        crystalShardsRun += 5;
        _awardEnergy(70);
        prismShiftTimer = max(prismShiftTimer, 7.0);
        _floatReward('PRISM SHIFT!', 0xFFFFC85C);
        _sfxQueue.add(GameSfxEvent.collectEnergy);
        break;
      default:
        break;
    }
  }

  void _activateGate(SlotKind kind, Orbit orbit, int slotIndex) {
    gatesActivatedRun += 1;
    switch (kind) {
      case SlotKind.gateEnergy:
        final amount = _awardEnergy(55);
        _floatReward('+$amount', 0xFF9B5CFF);
        break;
      case SlotKind.gateGhost:
        phaseGhostTimer = max(phaseGhostTimer, 3.5);
        _floatReward('GHOST', 0xFFFF4FD8);
        break;
      case SlotKind.gateSurge:
        shiftBoostTimer = max(shiftBoostTimer, 4.5);
        _repairLaneAround(orbit, slotIndex);
        _floatReward('SURGE', 0xFF4D8BFF);
        break;
      default:
        break;
    }
    _sfxQueue.add(GameSfxEvent.collectEnergy);
  }

  /// Clears damage from the slots either side of [slotIndex], so a Surge Gate
  /// visibly opens up the lane ahead of the player.
  void _repairLaneAround(Orbit orbit, int slotIndex) {
    for (int k = -2; k <= 2; k++) {
      final idx = (slotIndex + k) % orbit.slotCount;
      if (kRepairableKinds.contains(orbit.slots[idx].kind)) {
        orbit.slots[idx] = TrackSlot(kind: SlotKind.safe);
      }
    }
  }

  void _floatReward(String text, int color) {
    floatingTexts.add(FloatingText(
      text: text,
      angle: ballAngle,
      radiusFraction: laneRadius(ballOrbit),
      color: color,
    ));
  }

  void _updateDrones(double dt) {
    final activeOrbits = band.activeOrbits;
    // Drones stay scarce -- they are the only moving threat, and they only
    // read as one while the player can count them at a glance.
    final int targetCount;
    if (elapsedSeconds < 40) {
      targetCount = 0;
    } else if (elapsedSeconds < 60) {
      targetCount = 1;
    } else if (elapsedSeconds < 80) {
      targetCount = 2;
    } else if (elapsedSeconds < 110) {
      targetCount = 3;
    } else {
      targetCount = 4;
    }
    final sole = _solePlayableOrbit();
    if (sole != null) {
      drones.removeWhere((d) => d.orbitIndex == sole);
    }

    drones.removeWhere((d) => d.orbitIndex >= activeOrbits);
    if (drones.length < targetCount) _spawnDrone(activeOrbits);

    for (final drone in drones) {
      drone.angle += drone.speed * drone.direction * dt;
      if (drone.angle > drone.maxAngle) {
        drone.angle = drone.maxAngle;
        drone.direction = -1;
      } else if (drone.angle < drone.minAngle) {
        drone.angle = drone.minAngle;
        drone.direction = 1;
      }

      if (!shifting && drone.orbitIndex == ballOrbit) {
        final diff = _angleDiff(drone.angle, ballAngle);
        final threshold = orbits[drone.orbitIndex].slotAngleWidth() * 0.5;
        if (diff.abs() < threshold) _triggerHazard();
      }
    }
  }

  void _spawnDrone(int activeOrbits) {
    if (activeOrbits <= 0) return;
    final sole = _solePlayableOrbit();
    if (sole != null) return;
    final minLead = orbits[0].slotAngleWidth() *
            GameBalance.spawnClearanceSlots(speed) +
        0.45;
    final start = ballAngle + minLead + rng.nextDouble() * pi * 0.75;
    if (_angleDiff(start, ballAngle).abs() < minLead) return;
    final span = pi * (0.30 + rng.nextDouble() * 0.40);
    drones.add(Drone(
      orbitIndex: rng.nextInt(activeOrbits),
      variant: rng.nextInt(4),
      minAngle: start,
      maxAngle: start + span,
      angle: start,
      speed: 1.05 + rng.nextDouble() * 0.7,
    ));
  }

  double _angleDiff(double a, double b) {
    double d = (a - b) % (2 * pi);
    if (d > pi) d -= 2 * pi;
    if (d < -pi) d += 2 * pi;
    return d;
  }

  void _updateCoreStateMachine(double dt) {
    _coreTimer -= dt;
    if (_coreTimer > 0) return;
    switch (_coreSub) {
      case _CoreSub.calm:
        final kind = CoreState.values[1 + _coreSequence];
        _coreSequence = (_coreSequence + 1) % 3;
        _activeHazardKind = kind;
        _prepareOverlay(kind);
        _coreSub = _CoreSub.warning;
        _coreTimer = 1.6;
        _sfxQueue.add(GameSfxEvent.dangerWarning);
        break;
      case _CoreSub.warning:
        _coreSub = _CoreSub.active;
        _coreTimer = switch (_activeHazardKind!) {
          CoreState.pulse => 2.2,
          CoreState.expand => 3.0,
          CoreState.collapse => 3.2,
          CoreState.stable => 2.0,
        };
        break;
      case _CoreSub.active:
        _coreSub = _CoreSub.calm;
        _activeHazardKind = null;
        _coreTimer = elapsedSeconds < 50
            ? 7.0 + rng.nextDouble() * 2.2
            : elapsedSeconds < 100
                ? 5.0 + rng.nextDouble() * 2.0
                : 3.6 + rng.nextDouble() * 1.6;
        break;
    }
  }

  void _prepareOverlay(CoreState kind) {
    final activeOrbits = band.activeOrbits;
    switch (kind) {
      case CoreState.pulse:
        final current = orbits[ballOrbit].slotIndexForAngle(ballAngle);
        final lead = GameBalance.spawnClearanceSlots(speed);
        _pulseOrbit = rng.nextInt(activeOrbits);
        _pulseStartSlot =
            (current + lead + rng.nextInt(3)) % GameBalance.slotsPerOrbit;
        _pulseSlotCount = 3 + rng.nextInt(2);
        break;
      case CoreState.expand:
        _expandOrbitCount = min(2, activeOrbits - 1).clamp(1, activeOrbits);
        _stripSoleEscapeOrbit();
        break;
      case CoreState.collapse:
        _collapseCells.clear();
        final count = 2 + band.phase.index1;
        for (int i = 0; i < count; i++) {
          final o = rng.nextInt(activeOrbits);
          final s = rng.nextInt(GameBalance.slotsPerOrbit);
          if (_collapseCells.contains((o, s))) continue;
          if (o == ballOrbit && _inSpawnClearance(s)) continue;
          // Never seal off a whole angular column: one lane at every angle
          // has to stay passable.
          final columnSize = _collapseCells.where((c) => c.$2 == s).length + 1;
          if (columnSize >= activeOrbits) continue;
          _collapseCells.add((o, s));
        }
        for (int s = 0; s < GameBalance.slotsPerOrbit; s++) {
          _guaranteeEscapeLane(0, s, activeOrbits);
        }
        break;
      case CoreState.stable:
        break;
    }
  }

  void _updateFloatingAndParticles(double dt) {
    for (final t in floatingTexts) {
      t.life -= dt * 0.9;
    }
    floatingTexts.removeWhere((t) => t.life <= 0);
    for (final p in particles) {
      p.life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
  }

  RawRunStats collectStats() {
    return RawRunStats(
      survivalSeconds: elapsedSeconds,
      phaseIndex1: band.phase.index1,
      neonEnergyEarned: neonEnergyRun,
      crystalShardsEarned: crystalShardsRun,
      gatesActivated: gatesActivatedRun,
      maxNoHitStreak: maxNoHitStreak,
    );
  }
}

enum _CoreSub { calm, warning, active }
