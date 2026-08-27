import 'package:flutter/material.dart';

import '../../core/game_balance.dart';
import '../../core/theme.dart';
import '../../game/game_models.dart';
import '../../game/run_controller.dart';
import '../../widgets/neon_button.dart';
import '../../widgets/pickup_icon.dart';

class GameHud extends StatelessWidget {
  const GameHud({super.key, required this.controller, required this.onPause});

  final RunController controller;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _StatChip(
                  kind: SlotKind.energy,
                  value: '${controller.neonEnergyRun}',
                  color: NeonColors.cyan,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  kind: SlotKind.shard,
                  value: '${controller.crystalShardsRun}',
                  color: NeonColors.magenta,
                ),
              ],
            ),
          ),
          Text(
            _formatTime(controller.elapsedSeconds),
            style: NeonTextStyles.stat(size: 13),
          ),
          const SizedBox(width: 10),
          _ShieldIndicator(shields: controller.shields),
          const SizedBox(width: 10),
          NeonIconButton(
            icon: Icons.pause_rounded,
            semanticLabel: 'Pause',
            onPressed: onPause,
            size: 40,
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.kind, required this.value, required this.color});
  final SlotKind kind;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: NeonColors.panel.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PickupIcon(kind: kind, size: 14),
          const SizedBox(width: 6),
          Text(value, style: NeonTextStyles.stat(size: 13)),
        ],
      ),
    );
  }
}

class _ShieldIndicator extends StatelessWidget {
  const _ShieldIndicator({required this.shields});
  final int shields;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(GameBalance.maxShields, (i) {
        final filled = i < shields;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          // The same silhouette the pickup wears, so collecting one visibly
          // fills a slot the player has already been shown.
          child: Opacity(
            opacity: filled ? 1 : 0.18,
            child: const PickupIcon(kind: SlotKind.shield, size: 17),
          ),
        );
      }),
    );
  }
}
