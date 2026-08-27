import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../game/game_models.dart';
import 'pickup_icon.dart';

class CurrencyPill extends StatelessWidget {
  const CurrencyPill({
    super.key,
    required this.kind,
    required this.value,
    this.color = NeonColors.cyan,
    this.compact = false,
  });

  final SlotKind kind;
  final String value;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 5 : 7),
      decoration: BoxDecoration(
        color: NeonColors.panel.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PickupIcon(kind: kind, size: compact ? 14 : 17),
          const SizedBox(width: 7),
          Text(
            value,
            style: NeonTextStyles.stat(size: compact ? 12 : 14),
          ),
        ],
      ),
    );
  }
}
