import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/profile_service.dart';
import '../core/theme.dart';
import '../game/game_models.dart';
import '../models/catalog.dart';
import '../models/daily_challenge.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/neon_button.dart';
import '../widgets/pickup_icon.dart';

class DailyChallengeScreen extends StatelessWidget {
  const DailyChallengeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);
    final dc = profile.dailyChallenge ?? DailyChallenge.forDate(DateTime.now());
    final progressFrac = (dc.bestProgress / dc.target).clamp(0.0, 1.0);

    return MenuScaffold(
      background: sector.background,
      title: 'Daily Challenge',
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
            padding: const EdgeInsets.all(20),
            decoration: NeonColors.neonPanel(color: NeonColors.gold, opacity: 0.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.today_rounded, color: NeonColors.gold, size: 40),
                const SizedBox(height: 12),
                Text(
                  dc.type.describe(dc.target),
                  textAlign: TextAlign.center,
                  style: NeonTextStyles.heading(size: 17),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                    height: 10,
                    child: Stack(
                      children: [
                        Container(color: Colors.white.withValues(alpha: 0.12)),
                        FractionallySizedBox(
                          widthFactor: progressFrac,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(color: NeonColors.gold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${dc.bestProgress} / ${dc.target}',
                  style: NeonTextStyles.body,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const PickupIcon(kind: SlotKind.energy, size: 19),
                    const SizedBox(width: 6),
                    Text('+${DailyChallenge.rewardNeonEnergy}', style: NeonTextStyles.stat()),
                    const SizedBox(width: 18),
                    const PickupIcon(kind: SlotKind.shard, size: 19),
                    const SizedBox(width: 6),
                    Text('+${DailyChallenge.rewardCrystalShards}', style: NeonTextStyles.stat()),
                  ],
                ),
                const SizedBox(height: 18),
                if (dc.claimed)
                  const _StatusBanner(text: 'Reward claimed. Come back tomorrow!', color: NeonColors.emerald)
                else if (dc.isComplete)
                  NeonButton(
                    label: 'Claim Reward',
                    icon: Icons.card_giftcard_rounded,
                    fullWidth: true,
                    onPressed: () => profile.claimDailyChallenge(),
                  )
                else
                  const _StatusBanner(
                    text: 'Complete this objective during any run to unlock the reward.',
                    color: NeonColors.cyan,
                  ),
              ],
            ),
              ),
            ),
          ),
          Text(
            'A new challenge appears every day at midnight.',
            textAlign: TextAlign.center,
            style: NeonTextStyles.body.copyWith(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: NeonTextStyles.body.copyWith(color: Colors.white),
      ),
    );
  }
}
