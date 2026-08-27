import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/profile_service.dart';
import '../core/theme.dart';
import '../game/game_models.dart';
import '../models/catalog.dart';
import '../widgets/currency_pill.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/neon_button.dart';
import '../widgets/sprite_image.dart';

class BallSelectScreen extends StatelessWidget {
  const BallSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);

    return MenuScaffold(
      background: sector.background,
      title: 'Energy Ball',
      onBack: () => Navigator.of(context).pop(),
      trailing: CurrencyPill(
        kind: SlotKind.shard,
        value: '${profile.crystalShards}',
        color: NeonColors.magenta,
        compact: true,
      ),
      child: GridView.builder(
        padding: const EdgeInsets.only(top: 6),
        itemCount: GameCatalog.balls.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: adaptiveColumns(context, phone: 2, tablet: 3),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (context, i) {
          final ball = GameCatalog.balls[i];
          final unlocked = profile.unlockedBallIds.contains(ball.id);
          final selected = profile.selectedBallId == ball.id;
          return _BallCard(ball: ball, unlocked: unlocked, selected: selected);
        },
      ),
    );
  }
}

class _BallCard extends StatelessWidget {
  const _BallCard({required this.ball, required this.unlocked, required this.selected});

  final BallSkin ball;
  final bool unlocked;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final profile = context.read<ProfileService>();
    return Container(
      decoration: NeonColors.neonPanel(
        color: selected ? NeonColors.emerald : NeonColors.cyan,
        opacity: selected ? 0.9 : 0.35,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: Opacity(
              opacity: unlocked ? 1 : 0.4,
              child: SpriteImage(ref: ball.sprite),
            ),
          ),
          const SizedBox(height: 4),
          Text(ball.name, style: NeonTextStyles.heading(size: 14)),
          const SizedBox(height: 8),
          if (selected)
            const _StatusChip(label: 'EQUIPPED', color: NeonColors.emerald)
          else if (unlocked)
            NeonButton(
              label: 'Equip',
              dense: true,
              fullWidth: true,
              onPressed: () => profile.selectBall(ball.id),
            )
          else
            NeonButton(
              label: ball.unlockCrystalCost > 0
                  ? '${ball.unlockCrystalCost} Shards'
                  : 'Locked',
              icon: ball.unlockCrystalCost > 0 ? Icons.diamond_rounded : Icons.lock_rounded,
              dense: true,
              fullWidth: true,
              style: NeonButtonStyle.secondary,
              onPressed: ball.unlockCrystalCost > 0
                  ? () async {
                      final ok = await profile.spendCrystalShards(ball.unlockCrystalCost);
                      if (ok) {
                        await profile.unlockBall(ball.id);
                        await profile.selectBall(ball.id);
                      } else if (context.mounted) {
                        _notEnough(context);
                      }
                    }
                  : () => _showRequirement(context, ball),
            ),
        ],
      ),
    );
  }

  void _notEnough(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Not enough Crystal Shards yet.')),
    );
  }

  void _showRequirement(BuildContext context, BallSkin ball) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ball.unlockDescription)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color),
      ),
      alignment: Alignment.center,
      child: Text(label, style: NeonTextStyles.label.copyWith(color: color)),
    );
  }
}
