// Material rather than widgets: the gate glyphs are `Icons` constants, and
// only constant `IconData` survives icon tree-shaking.
import 'package:flutter/material.dart';

import 'game_models.dart';

/// The gameplay palette.
///
/// Saturated colour is reserved for meaning. Lanes themselves are a muted
/// steel blue, so the only vivid things on the field are the ones the player
/// has to act on -- one red for everything that hurts, a distinct bright hue
/// per pickup, and the gate blues. Five differently coloured neon lanes used
/// to compete with all of it at once.
class GameColors {
  GameColors._();

  /// One red, no exceptions. If it is this colour, it costs you.
  static const Color danger = Color(0xFFFF2D55);

  /// Passable, but not for long.
  static const Color warning = Color(0xFFFFB020);

  static const Color energy = Color(0xFF3DEFFF);
  static const Color shard = Color(0xFFFF4FD8);
  static const Color shield = Color(0xFF33FFB0);
  static const Color prism = Color(0xFFFFC85C);

  /// One colour for all three gates. A gate is always good news, so the hue
  /// only has to say "doorway" and the glyph inside says which bonus. Giving
  /// each gate its own colour spent three slots of the palette on a difference
  /// the player never has to act on -- and the old ghost-gate magenta was the
  /// Crystal Shard magenta, which is a difference they very much do.
  static const Color gate = Color(0xFF8A6BFF);

  /// Lane track. Later lanes lighten slightly so the rings still read as
  /// separate depths without introducing another hue.
  static const List<Color> lanes = [
    Color(0xFF5C7A99),
    Color(0xFF6D8BAB),
    Color(0xFF7E9CBD),
    Color(0xFF8FADCF),
    Color(0xFFA0BEE1),
  ];

  static Color lane(int index) => lanes[index % lanes.length];
}

/// How one slot should be drawn: which family silhouette and in which colour.
///
/// Pickups get a silhouette from `pickup_marks.dart`; gates get a [glyph].
/// Neither uses the art pack's illustrations, which all resolve to similar
/// glowing blobs at the ~30px a slot actually gets.
class SlotStyle {
  const SlotStyle({
    required this.family,
    required this.color,
    this.glyph,
  });

  final SlotFamily family;
  final Color color;
  final IconData? glyph;
}

SlotStyle styleForKind(SlotKind kind) => switch (kind) {
      SlotKind.safe =>
        const SlotStyle(family: SlotFamily.empty, color: Color(0x00000000)),
      SlotKind.cracked =>
        const SlotStyle(family: SlotFamily.warning, color: GameColors.warning),
      SlotKind.breach ||
      SlotKind.obstacle ||
      SlotKind.voidZone =>
        const SlotStyle(family: SlotFamily.danger, color: GameColors.danger),
      SlotKind.energy => const SlotStyle(
          family: SlotFamily.pickup,
          color: GameColors.energy,
        ),
      SlotKind.shard => const SlotStyle(
          family: SlotFamily.pickup,
          color: GameColors.shard,
        ),
      SlotKind.shield => const SlotStyle(
          family: SlotFamily.pickup,
          color: GameColors.shield,
        ),
      SlotKind.prism => const SlotStyle(
          family: SlotFamily.pickup,
          color: GameColors.prism,
        ),
      SlotKind.gateEnergy => const SlotStyle(
          family: SlotFamily.gate,
          color: GameColors.gate,
          glyph: Icons.bolt,
        ),
      SlotKind.gateSurge => const SlotStyle(
          family: SlotFamily.gate,
          color: GameColors.gate,
          glyph: Icons.double_arrow,
        ),
      SlotKind.gateGhost => const SlotStyle(
          family: SlotFamily.gate,
          color: GameColors.gate,
          // Deliberately not a shield: that silhouette already means "extra
          // life" as a pickup, and a ghost gate grants no such thing.
          glyph: Icons.blur_on,
        ),
    };

/// Short all-caps name shown in the tutorial legend and in pickup popups.
String labelForKind(SlotKind kind) => switch (kind) {
      SlotKind.safe => 'CLEAR LANE',
      SlotKind.cracked => 'CRACKED',
      SlotKind.breach => 'BREACH',
      SlotKind.obstacle => 'MINE',
      SlotKind.voidZone => 'VOID WELL',
      SlotKind.energy => 'NEON ENERGY',
      SlotKind.shard => 'CRYSTAL SHARD',
      SlotKind.shield => 'SHIELD CORE',
      SlotKind.prism => 'PRISM CORE',
      SlotKind.gateEnergy => 'ENERGY GATE',
      SlotKind.gateSurge => 'SURGE GATE',
      SlotKind.gateGhost => 'GHOST GATE',
    };

/// Blade count for a drone rotor, so the four variants stay visually distinct
/// without changing what they mean.
int droneBlades(int variant) => 3 + variant % 3;
