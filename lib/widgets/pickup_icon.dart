import 'package:flutter/material.dart';

import '../game/game_models.dart';
import '../game/pickup_marks.dart';
import '../game/slot_visuals.dart';

/// The in-field silhouette of a collectible, at menu size.
///
/// Menus and the HUD use the same marks as the play field so a player who has
/// learned what a shard looks like in a run recognises it on a price tag.
class PickupIcon extends StatelessWidget {
  const PickupIcon({super.key, required this.kind, this.size = 20});

  final SlotKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(kind, styleForKind(kind).color),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.kind, this.color);

  final SlotKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintPickupMark(
      canvas,
      center: size.center(Offset.zero),
      size: size.shortestSide,
      kind: kind,
      color: color,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.kind != kind || old.color != color;
}
