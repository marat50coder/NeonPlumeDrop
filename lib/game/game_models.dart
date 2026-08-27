import 'dart:math';

/// What kind of statement a slot makes to the player. The renderer gives each
/// family one silhouette and one colour band and never mixes them, so a glance
/// is enough to tell a threat from a prize:
///
///  * [danger] -- red, hard angular edges. Always costs you.
///  * [warning] -- amber, cracked. Safe this once, then it gives way.
///  * [pickup] -- a bright icon inside a soft halo. Always free to take.
///  * [gate] -- a wide lit doorway spanning the lane. Always a buff.
///
/// The previous vocabulary had 23 slot kinds across 10 sprite sheets, several
/// of which resolved to a *random* outcome, so the field was unreadable and at
/// times unfair. Every kind now belongs to exactly one family.
enum SlotFamily { empty, danger, warning, pickup, gate }

/// Everything a track slot can contain.
enum SlotKind {
  safe,

  /// Fractured lane. Passable, but collapses into a [breach] behind you.
  cracked,

  /// The lane is simply gone here. Lethal.
  breach,

  /// A barrier standing on the lane. Lethal.
  obstacle,

  /// A well that holds the ball. Lethal unless you shift away in time.
  voidZone,

  energy,
  shard,
  shield,
  prism,

  gateEnergy,
  gateGhost,
  gateSurge,
}

extension SlotKindX on SlotKind {
  SlotFamily get family => switch (this) {
        SlotKind.safe => SlotFamily.empty,
        SlotKind.cracked => SlotFamily.warning,
        SlotKind.breach ||
        SlotKind.obstacle ||
        SlotKind.voidZone =>
          SlotFamily.danger,
        SlotKind.energy ||
        SlotKind.shard ||
        SlotKind.shield ||
        SlotKind.prism =>
          SlotFamily.pickup,
        SlotKind.gateEnergy ||
        SlotKind.gateGhost ||
        SlotKind.gateSurge =>
          SlotFamily.gate,
      };

  /// Kills on contact with no grace period.
  bool get killsOnContact =>
      this == SlotKind.breach || this == SlotKind.obstacle;
}

const Set<SlotKind> kRepairableKinds = {
  SlotKind.cracked,
  SlotKind.breach,
  SlotKind.voidZone,
};

/// One angular slice of one orbit ring.
class TrackSlot {
  TrackSlot({this.kind = SlotKind.safe, this.variant = 0, this.consumed = false});

  SlotKind kind;
  int variant;
  bool consumed;

  SlotFamily get family => consumed ? SlotFamily.empty : kind.family;

  bool get isDeadly => kind.killsOnContact && !consumed;
  bool get isCollectible => kind.family == SlotFamily.pickup && !consumed;
  bool get isGate => kind.family == SlotFamily.gate && !consumed;
}

/// A full concentric orbit ring made of [TrackSlot]s.
///
/// Carries no radius: lane radii are re-spread whenever a phase adds a lane,
/// so the live values belong to the run, not to the ring.
class Orbit {
  Orbit({required this.index, required int slotCount})
      : slots = List.generate(slotCount, (_) => TrackSlot());

  final int index;
  final List<TrackSlot> slots;

  int get slotCount => slots.length;

  double slotAngleWidth() => 2 * pi / slotCount;

  int slotIndexForAngle(double angle) {
    final norm = angle % (2 * pi);
    final a = norm < 0 ? norm + 2 * pi : norm;
    return (a / slotAngleWidth()).floor() % slotCount;
  }

  TrackSlot slotForAngle(double angle) => slots[slotIndexForAngle(angle)];
}

/// A hunter that sweeps back and forth across a span of one lane.
///
/// Always lethal. Drones used to come in rewarding and lethal flavours drawn
/// from one sheet of near-identical sprites, which meant the player could not
/// tell whether an approaching drone was worth catching or fatal; [variant] now
/// only picks which of the four drone sprites is shown.
class Drone {
  Drone({
    required this.orbitIndex,
    required this.variant,
    required this.minAngle,
    required this.maxAngle,
    required this.angle,
    required this.speed,
    this.direction = 1,
  });

  final int orbitIndex;
  final int variant;
  final double minAngle;
  final double maxAngle;
  double angle;
  double speed;
  int direction;
}

enum CoreState { stable, pulse, expand, collapse }

/// Whether a core-collapse strike is still winding up on a cell or already
/// live.
enum CoreStrike { none, telegraph, lethal }

/// Snapshot of transient reward text (e.g. "+120", "Shield!") floating over
/// the play field.
class FloatingText {
  FloatingText({
    required this.text,
    required this.angle,
    required this.radiusFraction,
    required this.color,
    this.life = 1.0,
  });

  final String text;
  final double angle;
  final double radiusFraction;
  final int color;
  double life;
}

class ParticleBurst {
  ParticleBurst({
    required this.angle,
    required this.radiusFraction,
    required this.color,
    this.life = 0.6,
  }) : maxLife = life;

  final double angle;
  final double radiusFraction;
  final int color;
  double life;
  final double maxLife;
}
