/// Central registry of every asset path used by Neon Plume Drop.
library;

class GameAssets {
  GameAssets._();

  static const String _extra = 'assets/Neon_Plume_Drop_additional_assets';
  static const String _play = 'assets/Neon_Plume_Drop_gameplay_assets';
  static const String _sfx = 'assets/Neon_Plume_Drop_sounds_assets';

  static const String gameLogo = '$_extra/Game_Name.webp';
  static const String loadingVertical = '$_extra/Vertical_Loading_Screen.webp';
  static const String loadingHorizontal =
      '$_extra/Horizontal_Loading_Screen.webp';

  static const String bgDeepNeonSpace =
      '$_play/Deep_Neon_Space_Background_asset.webp';
  static const String bgCrystalGalaxy =
      '$_play/Crystal_Galaxy_Background_asset.webp';
  static const String bgDigitalVoid =
      '$_play/Digital_Void_Background_asset.webp';
  static const String bgPrismNebula =
      '$_play/Prism_Nebula_Background_asset.webp';
  static const String bgPlasmaUniverse =
      '$_play/Plasma_Universe_Background_asset.webp';
  static const String bgHolographicCosmos =
      '$_play/Holographic_Cosmos_Background_asset.webp';

  static const String centralEnergyCores =
      '$_play/Central_Energy_Cores_Set_asset.webp';
  static const String energyBalls1 = '$_play/Energy_Balls_Set_1_asset.webp';
  static const String energyBalls2 = '$_play/Energy_Balls_Set_2_asset.webp';
  static const String energyObstacles1 =
      '$_play/Energy_Obstacles_Set_1_asset.webp';
  static const String energyObstacles2 =
      '$_play/Energy_Obstacles_Set_2_asset.webp';
  static const String energyDrones = '$_play/Energy_Drones_Set_asset.webp';
  static const String voidZones = '$_play/Void_Zones_Set_asset.webp';
  static const String energyGates = '$_play/Energy_Gates_Set_asset.webp';
  static const String energyCrystals1 =
      '$_play/Energy_Crystals_Set_1_asset.webp';
  static const String energyCrystals2 =
      '$_play/Energy_Crystals_Set_2_asset.webp';
  static const String floatingCrystals =
      '$_play/Floating_Crystals_Set_asset.webp';
  static const String prismGates = '$_play/Prism_Gates_Set_asset.webp';
  static const String coloredRoutes =
      '$_play/Colored_Energy_Routes_Set_asset.webp';
  static const String holographicStructures =
      '$_play/Holographic_Structures_Set_asset.webp';
  static const String energyRings2 = '$_play/Energy_Rings_Set_2_asset.webp';
  static const String energyRings3 = '$_play/Energy_Rings_Set_3_asset.webp';
  static const String orbitalSegments1 =
      '$_play/Orbital_Segments_Set_1_asset.webp';
  static const String crystalShard = '$_play/Crystal_Shard_asset.webp';
  static const String shieldCore = '$_play/Shield_Core_asset.webp';
  static const String rarePrismCore = '$_play/Rare_Prism_Core_asset.webp';
  static const String neonEnergyOrb = '$_play/Neon_Energy_Orb_asset.webp';
  static const String energyChargeCapsule =
      '$_play/Energy_Charge_Capsule_asset.webp';
  static const String cosmicSectorPortal =
      '$_play/Cosmic_Sector_Portal_asset.webp';

  static const String sfxButtonClick = '$_sfx/Button_Click_asset.mp3';
  static const String sfxButtonBack = '$_sfx/Button_Back_asset.mp3';
  static const String sfxMenuOpen = '$_sfx/Menu_Open_asset.mp3';
  static const String sfxMenuClose = '$_sfx/Menu_Close_asset.mp3';
  static const String sfxScreenTransition =
      '$_sfx/Screen_Transition_asset.mp3';
  static const String sfxCollectEnergy = '$_sfx/Collect_Energy_asset.mp3';
  static const String sfxCollectRareCrystal =
      '$_sfx/Collect_Rare_Crystal_asset.mp3';
  static const String sfxOrbitalShift = '$_sfx/Orbital_Shift_asset.mp3';
  static const String sfxEnergyGateActivation =
      '$_sfx/Energy_Gate_Activation_asset.mp3';
  static const String sfxShieldActivation =
      '$_sfx/Shield_Activation_asset.mp3';
  static const String sfxCollision = '$_sfx/Collision_asset.mp3';
  static const String sfxDangerWarning = '$_sfx/Danger_Warning_asset.mp3';
  static const String sfxSectorPortal = '$_sfx/Sector_Portal_asset.mp3';
  static const String sfxDefeat = '$_sfx/Defeat_asset.mp3';
  static const String sfxVictory = '$_sfx/Victory_asset.mp3';

  /// Sheets decoded into [ui.Image]s for the custom-painted play field.
  static const List<String> allGameplayImages = [
    centralEnergyCores,
    energyBalls1,
    energyBalls2,
    energyObstacles1,
    energyObstacles2,
    energyDrones,
    voidZones,
    energyGates,
    energyCrystals1,
    energyCrystals2,
    floatingCrystals,
    energyRings2,
    energyRings3,
    orbitalSegments1,
    crystalShard,
    shieldCore,
    rarePrismCore,
    neonEnergyOrb,
    cosmicSectorPortal,
  ];
}
