import 'dart:math';
import 'dart:ui';

import 'game_models.dart';

/// The four collectibles, drawn as flat silhouettes.
///
/// The art pack has a lovely illustration for each of these, and all four are
/// glowing spheres. At slot size that made them interchangeable with one
/// another *and* with the player's own ball, which is also a glowing sphere --
/// so the field read as orb soup and the one question that matters, "is that
/// thing good for me", had no visual answer.
///
/// A silhouette per collectible answers it at a glance and at any size, so the
/// same marks are used in the HUD and menus. The illustrations still carry the
/// things that get drawn large: the core, the ball, and the skin gallery.
void paintPickupMark(
  Canvas canvas, {
  required Offset center,
  required double size,
  required SlotKind kind,
  required Color color,
  double opacity = 1.0,
}) {
  final path = pickupMarkPath(kind, center, size);

  canvas.drawPath(
    path,
    Paint()
      ..color = color.withValues(alpha: 0.55 * opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.28),
  );
  canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  // A white heart, so every mark keeps a hot centre and stays visible against
  // the sector backgrounds, which are themselves full of coloured nebulae.
  canvas.drawCircle(
    center,
    size * 0.11,
    Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * opacity),
  );
}

/// Silhouette for [kind], bounded by a [size]-wide box centred on [center].
Path pickupMarkPath(SlotKind kind, Offset center, double size) {
  final r = size / 2;
  switch (kind) {
    // A four-point spark: the common currency, and the lightest mark on the
    // field since there are more of these than anything else.
    case SlotKind.energy:
      final path = Path();
      const waist = 0.16;
      path.moveTo(center.dx, center.dy - r);
      path.quadraticBezierTo(
          center.dx + r * waist, center.dy - r * waist, center.dx + r, center.dy);
      path.quadraticBezierTo(
          center.dx + r * waist, center.dy + r * waist, center.dx, center.dy + r);
      path.quadraticBezierTo(
          center.dx - r * waist, center.dy + r * waist, center.dx - r, center.dy);
      path.quadraticBezierTo(
          center.dx - r * waist, center.dy - r * waist, center.dx, center.dy - r);
      path.close();
      return path;

    // A cut gem: wide shoulders, tapered point.
    case SlotKind.shard:
      return Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r * 0.62, center.dy - r * 0.24)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r * 0.62, center.dy - r * 0.24)
        ..close();

    // A heater shield: square shoulders, rounded base. The only mark with a
    // flat top, which is what makes the extra life findable in a hurry.
    case SlotKind.shield:
      final path = Path()
        ..moveTo(center.dx - r * 0.72, center.dy - r * 0.82)
        ..lineTo(center.dx + r * 0.72, center.dy - r * 0.82)
        ..lineTo(center.dx + r * 0.72, center.dy + r * 0.1);
      path.quadraticBezierTo(
          center.dx + r * 0.6, center.dy + r * 0.86, center.dx, center.dy + r);
      path.quadraticBezierTo(center.dx - r * 0.6, center.dy + r * 0.86,
          center.dx - r * 0.72, center.dy + r * 0.1);
      path.close();
      return path;

    // A six-point burst for the rarest pickup: the busiest silhouette, for the
    // one the player should chase.
    case SlotKind.prism:
      final path = Path();
      for (int i = 0; i < 12; i++) {
        final a = -pi / 2 + i * pi / 6;
        final rad = i.isEven ? r : r * 0.42;
        final p = center + Offset(cos(a), sin(a)) * rad;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      return path;

    default:
      return Path()..addOval(Rect.fromCircle(center: center, radius: r * 0.8));
  }
}
