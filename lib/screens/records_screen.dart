import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/game_assets.dart';
import '../core/game_balance.dart';
import '../core/profile_service.dart';
import '../core/theme.dart';
import '../models/catalog.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/sprite_image.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);
    final bestPhase = profile.bestPhaseIndex1 > 0
        ? CollapsePhase.values[profile.bestPhaseIndex1 - 1].label
        : 'Not set yet';

    final stats = <(String, String, IconData, Color)>[
      ('Best Survival Time', _formatTime(profile.bestSurvivalSeconds), Icons.timer_rounded, NeonColors.cyan),
      ('Best Phase Reached', bestPhase, Icons.bolt_rounded, NeonColors.magenta),
      ('Best Neon Energy (1 run)', '${profile.bestNeonEnergyRun}', Icons.blur_circular_rounded, NeonColors.deepBlue),
      ('Best Crystal Shards (1 run)', '${profile.bestCrystalShardsRun}', Icons.diamond_rounded, NeonColors.violet),
      ('Critical Collapse Clears', '${profile.criticalCollapseClears}', Icons.warning_amber_rounded, NeonColors.danger),
      ('Total Runs Played', '${profile.totalRuns}', Icons.replay_rounded, NeonColors.emerald),
    ];

    return MenuScaffold(
      background: sector.background,
      title: 'Your Records',
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          const SizedBox(
            height: 60,
            child: SpriteImage(
              ref: SpriteRef.single(GameAssets.rarePrismCore),
              cacheWidth: 256,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Personal bests, tracked on this device.',
            style: NeonTextStyles.body.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: stats.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final (label, value, icon, color) = stats[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: NeonColors.neonPanel(color: color, opacity: 0.35),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 22),
                      const SizedBox(width: 14),
                      Expanded(child: Text(label, style: NeonTextStyles.body.copyWith(color: Colors.white))),
                      Text(value, style: NeonTextStyles.stat(size: 16, color: color)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
