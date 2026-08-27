import '../core/game_assets.dart';
import '../core/sprite_grid.dart';
import '../models/catalog.dart';
import 'game_models.dart';

/// Maps live gameplay objects onto the art pack so the field, HUD and
/// collection all show the same sprites.
class PlaySprites {
  PlaySprites._();

  /// Circular mines only. The tall energy pylon in Obstacles Set 1 sits as a
  /// half-ring once it is rotated onto an orbit, so it is left out.
  static SpriteRef obstacle(int variant) {
    const circular = [
      (GameAssets.energyObstacles1, 0, 0), // spiked mine
      (GameAssets.energyObstacles1, 1, 1), // hex core
      (GameAssets.energyObstacles2, 1, 1), // mechanical orb
      (GameAssets.energyObstacles2, 0, 1), // shard ring
    ];
    final cell = circular[variant % circular.length];
    return SpriteRef(cell.$1, SpriteGrids.grid2x2, cell.$2, cell.$3);
  }

  static SpriteRef drone(int variant) =>
      SpriteRef(GameAssets.energyDrones, SpriteGrids.stripVertical4, 0, variant % 4);

  /// Bottom-left vortex is the canonical void well; other cells are variants.
  static SpriteRef voidZone(int variant) {
    const cells = [
      (0, 1), // vortex
      (1, 1), // glitch diamond
      (1, 0), // rift
      (0, 0), // impact burst
    ];
    final cell = cells[variant % cells.length];
    return SpriteRef(GameAssets.voidZones, SpriteGrids.grid2x2, cell.$1, cell.$2);
  }

  static SpriteRef energy(int variant) {
    final v = variant % 4;
    return SpriteRef(
      GameAssets.energyCrystals1,
      SpriteGrids.grid2x2,
      v % 2,
      v ~/ 2,
    );
  }

  static SpriteRef shard(int variant) {
    final v = variant % 4;
    return SpriteRef(
      GameAssets.floatingCrystals,
      SpriteGrids.grid2x2,
      v % 2,
      v ~/ 2,
    );
  }

  static const SpriteRef crystalShard = SpriteRef.single(GameAssets.crystalShard);
  static const SpriteRef shield = SpriteRef.single(GameAssets.shieldCore);
  static const SpriteRef prism = SpriteRef.single(GameAssets.rarePrismCore);
  static const SpriteRef neonOrb = SpriteRef.single(GameAssets.neonEnergyOrb);

  /// Full circular portals. The Energy Gates sheet is a set of open crescents
  /// that read as half-rings on an orbit, so the play field uses closed rings.
  static SpriteRef gate(SlotKind kind) => switch (kind) {
        SlotKind.gateEnergy =>
          const SpriteRef(GameAssets.energyRings2, SpriteGrids.grid2x2, 0, 0),
        SlotKind.gateSurge =>
          const SpriteRef(GameAssets.energyRings2, SpriteGrids.grid2x2, 1, 0),
        SlotKind.gateGhost =>
          const SpriteRef(GameAssets.energyRings3, SpriteGrids.grid2x1, 1, 0),
        _ => const SpriteRef(GameAssets.energyRings2, SpriteGrids.grid2x2, 0, 1),
      };

  static SpriteRef coreRing(int variant) => SpriteRef(
        GameAssets.energyRings2,
        SpriteGrids.grid2x2,
        variant % 2,
        (variant ~/ 2) % 2,
      );

  static SpriteRef forPickup(SlotKind kind, int variant) => switch (kind) {
        SlotKind.energy => energy(variant),
        SlotKind.shard => shard(variant),
        SlotKind.shield => shield,
        SlotKind.prism => prism,
        _ => energy(0),
      };
}

class ArtifactItem {
  const ArtifactItem({
    required this.id,
    required this.name,
    required this.sprite,
    required this.unlockDescription,
    this.unlockBestPhase = 0,
  });

  final String id;
  final String name;
  final SpriteRef sprite;
  final String unlockDescription;
  final int unlockBestPhase;
}

class ArtifactCatalog {
  ArtifactCatalog._();

  static const List<ArtifactItem> items = [
    ArtifactItem(
      id: 'neon_orb',
      name: 'Neon Energy Orb',
      sprite: SpriteRef.single(GameAssets.neonEnergyOrb),
      unlockDescription: 'Starter core fragment.',
    ),
    ArtifactItem(
      id: 'shield_core',
      name: 'Shield Core',
      sprite: SpriteRef.single(GameAssets.shieldCore),
      unlockDescription: 'Collect a Shield Core in any run.',
      unlockBestPhase: 1,
    ),
    ArtifactItem(
      id: 'crystal_shard',
      name: 'Crystal Shard',
      sprite: SpriteRef.single(GameAssets.crystalShard),
      unlockDescription: 'Collect a Crystal Shard in any run.',
      unlockBestPhase: 1,
    ),
    ArtifactItem(
      id: 'prism_core',
      name: 'Rare Prism Core',
      sprite: SpriteRef.single(GameAssets.rarePrismCore),
      unlockDescription: 'Reach Phase 3 in a single run.',
      unlockBestPhase: 3,
    ),
    ArtifactItem(
      id: 'charge_capsule',
      name: 'Energy Capsule',
      sprite: SpriteRef.single(GameAssets.energyChargeCapsule),
      unlockDescription: 'Reach Overload phase.',
      unlockBestPhase: 4,
    ),
    ArtifactItem(
      id: 'sector_portal',
      name: 'Sector Portal',
      sprite: SpriteRef.single(GameAssets.cosmicSectorPortal),
      unlockDescription: 'Reach Critical Collapse.',
      unlockBestPhase: 5,
    ),
    ArtifactItem(
      id: 'prism_gate_ice',
      name: 'Frost Gate',
      sprite: SpriteRef(GameAssets.prismGates, SpriteGrids.grid2x2, 0, 0),
      unlockDescription: 'Reach Phase 2 in a single run.',
      unlockBestPhase: 2,
    ),
    ArtifactItem(
      id: 'prism_gate_neon',
      name: 'Neon Gate',
      sprite: SpriteRef(GameAssets.prismGates, SpriteGrids.grid2x2, 0, 1),
      unlockDescription: 'Reach Overload phase.',
      unlockBestPhase: 4,
    ),
  ];
}
