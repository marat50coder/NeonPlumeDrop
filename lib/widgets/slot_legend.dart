import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../game/game_models.dart';
import '../game/pickup_marks.dart';
import '../game/slot_visuals.dart';

/// Explains the gameplay vocabulary by drawing the real thing.
///
/// Each row shows a straightened piece of lane carrying the exact silhouette
/// the play field uses, so what the player learns here is what they will
/// recognise mid-run. Wording that merely names the objects is no help when the
/// question is "will this one kill me".
class SlotLegend extends StatelessWidget {
  const SlotLegend({super.key, required this.kinds});

  final List<SlotKind> kinds;

  static const Map<SlotKind, String> _blurbs = {
    SlotKind.obstacle: 'A red spiked mine. Never survivable.',
    SlotKind.breach: 'The lane itself is missing. Never survivable.',
    SlotKind.cracked: 'Holds once. Crossing it leaves a breach behind you.',
    SlotKind.voidZone: 'Grabs you. Shift out before the ring closes.',
    SlotKind.energy: 'The run currency. Buys upgrades between runs.',
    SlotKind.shard: 'Rarer. Buys energy ball skins.',
    SlotKind.shield: 'An extra life. Soaks up one hit.',
    SlotKind.prism: 'A shard windfall, and a richer field for a while.',
    SlotKind.gateEnergy: 'A circular portal. Big energy payout.',
    SlotKind.gateSurge: 'Faster shifts, and clears the lane around it.',
    SlotKind.gateGhost: 'Pass straight through danger for a few seconds.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final kind in kinds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                _Swatch(kind: kind),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labelForKind(kind),
                        style: NeonTextStyles.stat(size: 13, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _blurbs[kind] ?? '',
                        style: NeonTextStyles.body.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.kind});

  final SlotKind kind;

  @override
  Widget build(BuildContext context) {
    final style = styleForKind(kind);
    return SizedBox(
      width: 66,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _SwatchPainter(kind))),
          if (style.glyph != null)
            Icon(style.glyph, size: 18, color: Colors.white),
        ],
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.kind);

  final SlotKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final rail = size.height * 0.17;
    final style = styleForKind(kind);
    const laneColor = Color(0xFF6D8BAB);

    void drawRail({double gap = 0}) {
      final paint = Paint()
        ..color = laneColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rail
        ..strokeCap = StrokeCap.round;
      if (gap == 0) {
        canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), paint);
        return;
      }
      final half = size.width / 2;
      canvas.drawLine(Offset(2, y), Offset(half - gap / 2, y), paint);
      canvas.drawLine(Offset(half + gap / 2, y), Offset(size.width - 2, y), paint);
    }

    switch (kind.family) {
      case SlotFamily.danger:
        if (kind == SlotKind.breach) {
          drawRail(gap: size.width * 0.42);
          final arm = rail * 1.5;
          final paint = Paint()
            ..color = GameColors.danger
            ..style = PaintingStyle.stroke
            ..strokeWidth = rail * 0.75
            ..strokeCap = StrokeCap.round;
          for (final sign in const [1.0, -1.0]) {
            canvas.drawLine(
              Offset(size.width / 2 - arm, y - arm * sign),
              Offset(size.width / 2 + arm, y + arm * sign),
              paint,
            );
          }
        } else if (kind == SlotKind.voidZone) {
          drawRail();
          final centre = Offset(size.width / 2, y);
          canvas.drawCircle(
            centre,
            rail * 2.2,
            Paint()..color = const Color(0xFF07010F),
          );
          canvas.drawCircle(
            centre,
            rail * 2.2,
            Paint()
              ..color = GameColors.danger.withValues(alpha: 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = rail * 0.5,
          );
        } else {
          drawRail();
          final centre = Offset(size.width / 2, y);
          canvas.drawCircle(
            centre,
            rail * 2.15,
            Paint()..color = const Color(0xFF1A0208),
          );
          canvas.drawCircle(
            centre,
            rail * 2.15,
            Paint()
              ..color = GameColors.danger
              ..style = PaintingStyle.stroke
              ..strokeWidth = rail * 0.55,
          );
          final tooth = Paint()..color = GameColors.danger;
          for (int i = 0; i < 6; i++) {
            final a = i * pi / 3;
            final inner = rail * 2.0;
            final outer = rail * 2.65;
            canvas.drawPath(
              Path()
                ..moveTo(centre.dx + cos(a) * inner, centre.dy + sin(a) * inner)
                ..lineTo(centre.dx + cos(a - 0.22) * outer,
                    centre.dy + sin(a - 0.22) * outer)
                ..lineTo(centre.dx + cos(a + 0.22) * outer,
                    centre.dy + sin(a + 0.22) * outer)
                ..close(),
              tooth,
            );
          }
        }
        break;

      case SlotFamily.warning:
        drawRail();
        final paint = Paint()
          ..color = GameColors.warning
          ..style = PaintingStyle.stroke
          ..strokeWidth = rail * 1.15;
        for (final f in const [0.34, 0.5, 0.66]) {
          final x = size.width * f;
          canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), paint);
        }
        break;

      case SlotFamily.pickup:
        drawRail();
        paintPickupMark(
          canvas,
          center: Offset(size.width / 2, y),
          size: size.height * 0.62,
          kind: kind,
          color: style.color,
        );
        break;

      case SlotFamily.gate:
        drawRail();
        final centre = Offset(size.width / 2, y);
        canvas.drawCircle(
          centre,
          rail * 2.2,
          Paint()..color = style.color.withValues(alpha: 0.22),
        );
        canvas.drawCircle(
          centre,
          rail * 2.2,
          Paint()
            ..color = style.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = rail * 0.55,
        );
        break;

      case SlotFamily.empty:
        drawRail();
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) => old.kind != kind;
}
