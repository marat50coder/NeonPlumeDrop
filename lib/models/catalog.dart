import 'dart:ui' as ui;

import '../core/game_assets.dart';
import '../core/sprite_frames.dart';
import '../core/sprite_grid.dart';

/// Describes one cell inside a sprite-sheet asset, and where that cell's
/// artwork actually is.
class SpriteRef {
  const SpriteRef(this.asset, this.grid, this.column, this.row);

  /// A sheet holding a single sprite.
  const SpriteRef.single(this.asset)
      : grid = SpriteGrids.single,
        column = 0,
        row = 0;

  final String asset;
  final SpriteGrid grid;
  final int column;
  final int row;

  /// Box the artwork occupies, as a fraction of the sheet.
  ///
  /// Falls back to the whole nominal cell for sheets [kSpriteFrames] has not
  /// been generated for, which draws the original transparent padding along
  /// with the sprite.
  ui.Rect get frame {
    final frames = kSpriteFrames[asset];
    if (frames == null) return grid.cellFraction(column, row);
    return frames[row * grid.columns + column];
  }

  /// Width over height of [frame] in real pixels.
  double get aspectRatio {
    final f = frame;
    final size = kSheetSizes[asset] ?? const ui.Size(kSheetWidth, kSheetHeight);
    return (f.width * size.width) / (f.height * size.height);
  }

  /// [frame] in pixels of [image], which may be decoded at a reduced size.
  ui.Rect sourceRectIn(ui.Image image) {
    final f = frame;
    return ui.Rect.fromLTRB(
      f.left * image.width,
      f.top * image.height,
      f.right * image.width,
      f.bottom * image.height,
    );
  }
}

class BallSkin {
  const BallSkin({
    required this.id,
    required this.name,
    required this.sprite,
    required this.unlockDescription,
    this.unlockCrystalCost = 0,
    this.unlockBestPhase = 0,
    this.unlockedByDefault = false,
  });

  final String id;
  final String name;
  final SpriteRef sprite;
  final String unlockDescription;
  final int unlockCrystalCost;
  final int unlockBestPhase;
  final bool unlockedByDefault;
}

class SectorTheme {
  const SectorTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.core,
    required this.unlockDescription,
    this.unlockBestPhase = 0,
    this.unlockedByDefault = false,
  });

  final String id;
  final String name;
  final String background;
  final SpriteRef core;
  final String unlockDescription;
  final int unlockBestPhase;
  final bool unlockedByDefault;
}

enum UpgradeId {
  energyCapacity,
  shiftPower,
  shieldDuration,
  energyGain,
  shieldChance,
  rareDropChance,
}

class UpgradeDef {
  const UpgradeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.maxLevel,
    required this.baseCost,
  });

  final UpgradeId id;
  final String name;
  final String description;
  final int maxLevel;
  final int baseCost;

  int costForLevel(int currentLevel) {
    if (currentLevel >= maxLevel) return -1;
    return (baseCost * (currentLevel + 1) * (currentLevel + 1.6)).round();
  }
}

class GameCatalog {
  GameCatalog._();

  static const List<BallSkin> balls = [
    BallSkin(
      id: 'cyan_pulse',
      name: 'Cyan Pulse',
      sprite: SpriteRef(GameAssets.energyBalls1, SpriteGrids.grid2x2, 0, 0),
      unlockDescription: 'Starter energy ball.',
      unlockedByDefault: true,
    ),
    BallSkin(
      id: 'magenta_flare',
      name: 'Magenta Flare',
      sprite: SpriteRef(GameAssets.energyBalls1, SpriteGrids.grid2x2, 1, 0),
      unlockDescription: 'Reach Phase 2 in a single run.',
      unlockBestPhase: 2,
    ),
    BallSkin(
      id: 'violet_core',
      name: 'Violet Core',
      sprite: SpriteRef(GameAssets.energyBalls1, SpriteGrids.grid2x2, 0, 1),
      unlockDescription: 'Unlock for 400 Crystal Shards.',
      unlockCrystalCost: 400,
    ),
    BallSkin(
      id: 'emerald_spin',
      name: 'Emerald Spin',
      sprite: SpriteRef(GameAssets.energyBalls1, SpriteGrids.grid2x2, 1, 1),
      unlockDescription: 'Reach Phase 3 in a single run.',
      unlockBestPhase: 3,
    ),
    BallSkin(
      id: 'crystal_prism',
      name: 'Crystal Prism',
      sprite: SpriteRef(GameAssets.energyBalls2, SpriteGrids.grid2x2, 0, 0),
      unlockDescription: 'Unlock for 650 Crystal Shards.',
      unlockCrystalCost: 650,
    ),
    BallSkin(
      id: 'rainbow_core',
      name: 'Rainbow Core',
      sprite: SpriteRef(GameAssets.energyBalls2, SpriteGrids.grid2x2, 1, 0),
      unlockDescription: 'Reach Overload phase.',
      unlockBestPhase: 4,
    ),
    BallSkin(
      id: 'holographic_orb',
      name: 'Holographic Orb',
      sprite: SpriteRef(GameAssets.energyBalls2, SpriteGrids.grid2x2, 0, 1),
      unlockDescription: 'Unlock for 900 Crystal Shards.',
      unlockCrystalCost: 900,
    ),
    BallSkin(
      id: 'glitch_core',
      name: 'Glitch Core',
      sprite: SpriteRef(GameAssets.energyBalls2, SpriteGrids.grid2x2, 1, 1),
      unlockDescription: 'Reach Critical Collapse.',
      unlockBestPhase: 5,
    ),
  ];

  static const List<SectorTheme> sectors = [
    SectorTheme(
      id: 'deep_neon_space',
      name: 'Deep Neon Space',
      background: GameAssets.bgDeepNeonSpace,
      core: SpriteRef(GameAssets.centralEnergyCores, SpriteGrids.grid2x2, 0, 0),
      unlockDescription: 'Default sector.',
      unlockedByDefault: true,
    ),
    SectorTheme(
      id: 'crystal_galaxy',
      name: 'Crystal Galaxy',
      background: GameAssets.bgCrystalGalaxy,
      core: SpriteRef(GameAssets.centralEnergyCores, SpriteGrids.grid2x2, 1, 0),
      unlockDescription: 'Reach Phase 2 in a single run.',
      unlockBestPhase: 2,
    ),
    SectorTheme(
      id: 'digital_void',
      name: 'Digital Void',
      background: GameAssets.bgDigitalVoid,
      core: SpriteRef(GameAssets.centralEnergyCores, SpriteGrids.grid2x2, 0, 1),
      unlockDescription: 'Reach Phase 3 in a single run.',
      unlockBestPhase: 3,
    ),
    SectorTheme(
      id: 'prism_nebula',
      name: 'Prism Nebula',
      background: GameAssets.bgPrismNebula,
      core: SpriteRef(GameAssets.centralEnergyCores, SpriteGrids.grid2x2, 1, 1),
      unlockDescription: 'Reach Overload phase.',
      unlockBestPhase: 4,
    ),
    SectorTheme(
      id: 'plasma_universe',
      name: 'Plasma Universe',
      background: GameAssets.bgPlasmaUniverse,
      core: SpriteRef(GameAssets.centralEnergyCores, SpriteGrids.grid2x2, 1, 0),
      unlockDescription: 'Reach Critical Collapse.',
      unlockBestPhase: 5,
    ),
    SectorTheme(
      id: 'holographic_cosmos',
      name: 'Holographic Cosmos',
      background: GameAssets.bgHolographicCosmos,
      core: SpriteRef(GameAssets.centralEnergyCores, SpriteGrids.grid2x2, 0, 0),
      unlockDescription: 'Reach Critical Collapse twice.',
      unlockBestPhase: 5,
    ),
  ];

  static const List<UpgradeDef> upgrades = [
    UpgradeDef(
      id: UpgradeId.energyCapacity,
      name: 'Energy Capacity',
      description: 'Increases starting Neon Energy bonus each run.',
      maxLevel: 5,
      baseCost: 400,
    ),
    UpgradeDef(
      id: UpgradeId.shiftPower,
      name: 'Orbital Shift Power',
      description: 'Faster, safer Orbital Shifts with longer i-frames.',
      maxLevel: 5,
      baseCost: 500,
    ),
    UpgradeDef(
      id: UpgradeId.shieldDuration,
      name: 'Shield Duration',
      description: 'Extends invulnerability after taking a hit.',
      maxLevel: 5,
      baseCost: 450,
    ),
    UpgradeDef(
      id: UpgradeId.energyGain,
      name: 'Energy Gain',
      description: 'Increases the value of every Neon Energy pickup.',
      maxLevel: 5,
      baseCost: 350,
    ),
    UpgradeDef(
      id: UpgradeId.shieldChance,
      name: 'Shield Chance',
      description: 'Shield Cores appear more often on every orbit.',
      maxLevel: 5,
      baseCost: 600,
    ),
    UpgradeDef(
      id: UpgradeId.rareDropChance,
      name: 'Rare Drop Chance',
      description: 'Crystal Shards and Rare Prism Cores appear more often.',
      maxLevel: 4,
      baseCost: 750,
    ),
  ];

  static BallSkin ballById(String id) =>
      balls.firstWhere((b) => b.id == id, orElse: () => balls.first);

  static SectorTheme sectorById(String id) =>
      sectors.firstWhere((s) => s.id == id, orElse: () => sectors.first);

  static UpgradeDef upgradeById(UpgradeId id) =>
      upgrades.firstWhere((u) => u.id == id);
}
