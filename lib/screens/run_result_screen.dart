import 'package:flutter/material.dart';

import '../core/game_assets.dart';
import '../core/game_balance.dart';
import '../core/profile_service.dart';
import '../core/theme.dart';
import '../game/game_models.dart';
import '../models/catalog.dart';
import '../models/run_summary.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/neon_button.dart';
import '../widgets/pickup_icon.dart';
import '../widgets/sprite_image.dart';
import '../widgets/time_medal_badge.dart';
import 'game/game_screen.dart';

class RunResultScreen extends StatelessWidget {
  const RunResultScreen({
    super.key,
    required this.summary,
    required this.dailyChallengeJustCompleted,
  });

  final RunSummary summary;
  final bool dailyChallengeJustCompleted;

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService.instance;
    final sector = GameCatalog.sectorById(profile.selectedSectorId);
    final isRecord = summary.isNewBestTime || summary.isNewBestPhase;

    return PopScope(
      canPop: false,
      child: MenuScaffold(
        background: sector.background,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 76,
                        child: SpriteImage(
                          ref: SpriteRef.single(
                            isRecord
                                ? GameAssets.rarePrismCore
                                : GameAssets.cosmicSectorPortal,
                          ),
                          cacheWidth: 320,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (isRecord)
                        Text(
                          'NEW RECORD!',
                          style: NeonTextStyles.title(
                            size: 28,
                            color: NeonColors.gold,
                          ),
                        )
                      else
                        Text(
                          'RUN COMPLETE',
                          style: NeonTextStyles.heading(size: 22),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Survived ${summary.formattedTime}  •  ${summary.phaseReached.label}',
                        style: NeonTextStyles.body.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: NeonColors.neonPanel(
                          color: NeonColors.cyan,
                          opacity: 0.4,
                        ),
                        child: Column(
                          children: [
                            _RewardRow(
                              leading: const PickupIcon(
                                kind: SlotKind.energy,
                                size: 22,
                              ),
                              label: 'Neon Energy',
                              value: '+${summary.neonEnergyEarned}',
                              color: NeonColors.cyan,
                            ),
                            const SizedBox(height: 14),
                            _RewardRow(
                              leading: const PickupIcon(
                                kind: SlotKind.shard,
                                size: 22,
                              ),
                              label: 'Crystal Shards',
                              value: '+${summary.crystalShardsEarned}',
                              color: NeonColors.magenta,
                            ),
                            const SizedBox(height: 14),
                            _RewardRow(
                              leading: const Icon(
                                Icons.meeting_room_rounded,
                                color: NeonColors.violet,
                                size: 24,
                              ),
                              label: 'Gates Flown',
                              value: '${summary.gatesActivated}',
                              color: NeonColors.violet,
                            ),
                          ],
                        ),
                      ),
                      if (dailyChallengeJustCompleted) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: NeonColors.gold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: NeonColors.gold.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.today_rounded,
                                color: NeonColors.gold,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Daily Challenge objective complete! Claim it from the menu.',
                                  style: NeonTextStyles.body.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (summary.newlyUnlockedMedals.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          decoration: BoxDecoration(
                            color: NeonColors.gold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: NeonColors.gold.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                summary.newlyUnlockedMedals.length == 1
                                    ? 'MEDAL UNLOCKED'
                                    : 'MEDALS UNLOCKED',
                                style: NeonTextStyles.label.copyWith(
                                  color: NeonColors.gold,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 16,
                                runSpacing: 10,
                                children: [
                                  for (final medal
                                      in summary.newlyUnlockedMedals)
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TimeMedalBadge(medal: medal, size: 56),
                                        const SizedBox(height: 6),
                                        Text(
                                          medal.name,
                                          style: NeonTextStyles.label.copyWith(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            NeonButton(
              label: 'Play Again',
              icon: Icons.replay_rounded,
              fullWidth: true,
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const GameScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            NeonButton(
              label: 'Main Menu',
              icon: Icons.home_rounded,
              fullWidth: true,
              style: NeonButtonStyle.ghost,
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.leading,
    required this.label,
    required this.value,
    required this.color,
  });

  final Widget leading;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 26, child: Center(child: leading)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: NeonTextStyles.body.copyWith(color: Colors.white),
          ),
        ),
        Text(value, style: NeonTextStyles.stat(size: 18, color: color)),
      ],
    );
  }
}
