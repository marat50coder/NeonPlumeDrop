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
    final band = controller.band;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        children: [
          Row(
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
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                band.phase.label.toUpperCase(),
                style: NeonTextStyles.label.copyWith(
                  color: _phaseColor(band.phase.index1),
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(color: Colors.white.withValues(alpha: 0.12)),
                        FractionallySizedBox(
                          widthFactor: _phaseProgress(controller),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: _phaseColor(band.phase.index1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(controller.elapsedSeconds),
                style: NeonTextStyles.stat(size: 13),
              ),
            ],
          ),
          if (controller.coreWarning) ...[
            const SizedBox(height: 8),
            _WarningBanner(kind: controller.coreVisualState),
          ],
        ],
      ),
    );
  }

  double _phaseProgress(RunController controller) {
    final band = controller.band;
    final next = GameBalance.nextBandAfter(band);
    if (next == null) return 1.0;
    final span = next.startSeconds - band.startSeconds;
    if (span <= 0) return 1.0;
    return ((controller.elapsedSeconds - band.startSeconds) / span).clamp(0.0, 1.0);
  }

  Color _phaseColor(int index1) {
    const colors = [
      NeonColors.cyan,
      NeonColors.emerald,
      NeonColors.violet,
      NeonColors.gold,
      NeonColors.danger,
    ];
    return colors[(index1 - 1).clamp(0, colors.length - 1)];
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

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.kind});
  final CoreState kind;

  String get _label => switch (kind) {
        CoreState.pulse => 'CORE PULSE INCOMING',
        CoreState.expand => 'CORE EXPANDING — MOVE OUTWARD',
        CoreState.collapse => 'COLLAPSE EVENT INCOMING',
        CoreState.stable => '',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: NeonColors.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NeonColors.danger.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        _label,
        style: NeonTextStyles.label.copyWith(color: NeonColors.danger, letterSpacing: 1.2),
      ),
    );
  }
}
