import 'dart:math';

import 'package:flutter/material.dart';

import '../core/game_balance.dart';
import '../core/image_loader.dart';
import '../models/catalog.dart';
import 'game_models.dart';
import 'play_sprites.dart';
import 'run_controller.dart';
import 'slot_visuals.dart';

/// Renders one frame of a Neon Plume Drop run onto a square canvas using
/// only raw [Canvas] calls, reading state directly from [controller].
///
/// Every family in [SlotFamily] gets its own silhouette, and nothing else may
/// borrow it:
///
///  * danger -- red spiked ring. A mine is a full circle sitting on the lane,
///    a breach is a hole in the rail, a void well is a dark pit. All three
///    wear the same red mark.
///  * warning -- amber dashes over intact lane.
///  * pickup -- a coloured glow with a smooth ring, never the spiked red badge.
///  * gate -- a full circular portal with a smooth violet ring. Always a buff.
class GamePainter extends CustomPainter {
  GamePainter({
    required this.controller,
    required this.sector,
    required this.ball,
  }) : images = ImageLoader.instance;

  final RunController controller;
  final SectorTheme sector;
  final BallSkin ball;
  final ImageLoader images;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final fieldRadius = min(size.width, size.height) / 2;
    final t = controller.elapsedSeconds;

    canvas.save();
    if (controller.screenShake > 0) {
      final dx = sin(t * 53) * cos(t * 19) * controller.screenShake * 9;
      final dy = sin(t * 41 + 3) * controller.screenShake * 9;
      canvas.translate(dx, dy);
    }

    final metrics = _Metrics(
      center: center,
      fieldRadius: fieldRadius,
      lanes: controller.laneRadii,
      activeLanes: controller.band.activeOrbits,
    );

    _drawFieldDepth(canvas, metrics);
    _drawCore(canvas, metrics, t);
    for (int lane = 0; lane < metrics.activeLanes; lane++) {
      _drawLane(canvas, metrics, lane, t);
    }
    _drawDrones(canvas, metrics, t);
    _drawBallTrail(canvas, metrics);
    _drawBall(canvas, metrics, t);
    _drawFloatingTexts(canvas, metrics);
    _drawParticles(canvas, metrics);

    if (controller.prismShiftTimer > 0) {
      _drawPrismVignette(canvas, size, controller.prismShiftTimer);
    }

    canvas.restore();
  }

  // -- lanes ---------------------------------------------------------------

  /// Seats the rings in a shallow well rather than floating them on the sector
  /// background, and marks the slot boundaries faintly so the player can see
  /// where one slice ends and the next begins.
  void _drawFieldDepth(Canvas canvas, _Metrics m) {
    final outer = GameBalance.outermostLane * m.fieldRadius;
    canvas.drawCircle(
      m.center,
      outer * 1.04,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF120A2E).withValues(alpha: 0.55),
            const Color(0xFF0A0520).withValues(alpha: 0.0),
          ],
          stops: const [0.55, 1.0],
        ).createShader(Rect.fromCircle(center: m.center, radius: outer * 1.04)),
    );

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = m.fieldRadius * 0.003;
    final inner = GameBalance.innermostLane * m.fieldRadius;
    for (int s = 0; s < GameBalance.slotsPerOrbit; s++) {
      final a = (s - 0.5) * 2 * pi / GameBalance.slotsPerOrbit;
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(
        m.center + dir * (inner - m.laneThickness),
        m.center + dir * (outer + m.laneThickness),
        tickPaint,
      );
    }
  }

  void _drawLane(Canvas canvas, _Metrics m, int lane, double t) {
    final orbit = controller.orbits[lane];
    final radius = m.lanes[lane] * m.fieldRadius;
    final thickness = m.laneThickness;
    final bounds = Rect.fromCircle(center: m.center, radius: radius);
    final slotWidth = orbit.slotAngleWidth();
    final laneColor = GameColors.lane(lane);

    // A single path for the intact rail, so the whole lane costs two strokes
    // no matter how many slots it has. Slots the lane is missing from are left
    // out, which is what makes a breach read as a hole rather than a decal.
    final rail = Path();
    for (int s = 0; s < orbit.slotCount; s++) {
      if (_railMissingAt(orbit, lane, s)) continue;
      // Overlap neighbours slightly so consecutive slots fuse seamlessly.
      rail.addArc(
        bounds,
        (s - 0.52) * slotWidth,
        slotWidth * 1.04,
      );
    }

    // The lane the ball is riding glows cyan; the rest stay steel. On a
    // five-ring field this is the fastest answer to "which of these am I on",
    // and it costs no extra screen furniture. Other lanes are dimmed only
    // slightly -- they still have to be readable, because looking ahead on
    // them is how the next shift gets planned.
    final occupied = lane == controller.ballOrbit;

    if (occupied) {
      // A full ring, not the gapped rail: the highlight has to survive the
      // holes in the lane, since those holes are exactly where the player is
      // looking when they need to know where they stand.
      canvas.drawCircle(
        m.center,
        radius,
        Paint()
          ..color = GameColors.energy.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness * 2.6
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 1.6),
      );
    }

    canvas.drawPath(
      rail,
      Paint()
        ..color = laneColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 2.4
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 0.9),
    );
    canvas.drawPath(
      rail,
      Paint()
        ..color = laneColor.withValues(alpha: occupied ? 0.95 : 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );
    // Bright core down the middle of the rail, so it reads as a lit tube
    // rather than a flat grey band.
    canvas.drawPath(
      rail,
      Paint()
        ..color = Colors.white.withValues(alpha: occupied ? 0.40 : 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 0.3,
    );

    final nearestLethal = occupied ? controller.nearestLethalAhead : null;
    for (int s = 0; s < orbit.slotCount; s++) {
      final angle = s * slotWidth;
      final overlay = controller.overlayStateFor(lane, s);
      if (overlay != CoreStrike.none) {
        _drawOverlayStrike(canvas, m, bounds, angle, slotWidth, overlay, t);
      }
      if (nearestLethal == s) {
        final pos = m.center + Offset(cos(angle), sin(angle)) * radius;
        _drawIncomingDangerPulse(canvas, pos, m.iconSize * 1.35, t);
      }
      final slot = orbit.slots[s];
      if (slot.consumed) continue;
      switch (slot.kind) {
        case SlotKind.safe:
          break;
        case SlotKind.cracked:
          _drawCracked(canvas, m, bounds, angle, slotWidth);
          break;
        case SlotKind.breach:
          _drawBreach(canvas, m, radius, angle);
          break;
        case SlotKind.obstacle:
          _drawBarrier(canvas, m, radius, angle, slot.variant, t);
          break;
        case SlotKind.voidZone:
          _drawVoidWell(canvas, m, radius, angle, t, slot.variant);
          break;
        case SlotKind.energy:
        case SlotKind.shard:
        case SlotKind.shield:
        case SlotKind.prism:
          _drawPickup(
              canvas, m, radius, angle, slot.kind, styleForKind(slot.kind), t,
              variant: slot.variant);
          break;
        case SlotKind.gateEnergy:
        case SlotKind.gateGhost:
        case SlotKind.gateSurge:
          _drawGate(canvas, m, radius, angle, slot.kind, t);
          break;
      }
    }
  }

  /// True where the lane has no rail to stand on: a breach, or a cell the core
  /// has already collapsed.
  bool _railMissingAt(Orbit orbit, int lane, int slotIndex) {
    final slot = orbit.slots[slotIndex];
    if (slot.kind == SlotKind.breach && !slot.consumed) return true;
    return controller.overlayStateFor(lane, slotIndex) == CoreStrike.lethal;
  }

  /// Expanding red ping on the next lethal on the player's own ring. Other
  /// mines keep the usual badge; this one has to shout.
  void _drawIncomingDangerPulse(Canvas canvas, Offset pos, double size, double t) {
    final breath = 0.5 + 0.5 * sin(t * 6.4);
    canvas.drawCircle(
      pos,
      size * (0.92 + 0.20 * breath),
      Paint()
        ..color = GameColors.danger.withValues(alpha: 0.18 + 0.22 * breath)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.38),
    );
    final ping = (t * 0.9) % 1.0;
    for (final phase in const [0.0, 0.5]) {
      final p = (ping + phase) % 1.0;
      canvas.drawCircle(
        pos,
        size * (0.42 + 0.78 * p),
        Paint()
          ..color = GameColors.danger.withValues(alpha: (1 - p) * 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * (0.07 - 0.03 * p),
      );
    }
  }

  void _drawCracked(
      Canvas canvas, _Metrics m, Rect bounds, double angle, double slotWidth) {
    final paint = Paint()
      ..color = GameColors.warning.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = m.laneThickness * 1.15
      ..strokeCap = StrokeCap.butt;
    // Three dashes across the slot: intact rail, visibly fracturing.
    for (int i = 0; i < 3; i++) {
      final start = angle + (i - 1.5) * slotWidth * 0.28;
      canvas.drawArc(bounds, start, slotWidth * 0.18, false, paint);
    }
  }

  void _drawBreach(Canvas canvas, _Metrics m, double radius, double angle) {
    final thickness = m.laneThickness;
    final pos = m.center + Offset(cos(angle), sin(angle)) * radius;
    final arm = thickness * 0.8;

    canvas.drawCircle(
      pos,
      thickness * 1.55,
      Paint()
        ..color = GameColors.danger.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 1.2),
    );
    canvas.drawCircle(
      pos,
      thickness * 1.15,
      Paint()
        ..color = GameColors.danger
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 0.28,
    );
    // A single cross in the hole. Marking both cut ends instead put two red
    // objects on the field per breach, which made the track look twice as
    // hostile as it is.
    final paint = Paint()
      ..color = GameColors.danger
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness * 0.42
      ..strokeCap = StrokeCap.round;
    for (final sign in const [1.0, -1.0]) {
      canvas.drawLine(
        pos + Offset(-arm, -arm * sign),
        pos + Offset(arm, arm * sign),
        paint,
      );
    }
  }

  void _drawBarrier(
      Canvas canvas, _Metrics m, double radius, double angle, int variant, double t) {
    final pos = m.center + Offset(cos(angle), sin(angle)) * radius;
    final size = m.iconSize * 1.22;
    _drawHazardBadge(canvas, pos, size, t);
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: pos, radius: size * 0.46)),
    );
    _drawSprite(
      canvas,
      PlaySprites.obstacle(variant),
      pos,
      size * 0.92,
      cover: true,
      rotation: t * 0.35,
    );
    canvas.restore();
  }

  /// Full red circle with ticking teeth. Every lethal object on the field uses
  /// this mark so a glance is enough: red ring = it will hit you, anything else
  /// will not.
  void _drawHazardBadge(Canvas canvas, Offset pos, double size, double t) {
    final pulse = 0.7 + 0.3 * (0.5 + 0.5 * sin(t * 9));
    final r = size * 0.56;

    canvas.drawCircle(
      pos,
      r * 1.22,
      Paint()
        ..color = GameColors.danger.withValues(alpha: 0.42 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.48),
    );
    canvas.drawCircle(
      pos,
      r,
      Paint()..color = const Color(0xFF1A0208).withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..color = GameColors.danger.withValues(alpha: 0.35 + 0.55 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.1,
    );
    canvas.drawCircle(
      pos,
      r * 0.8,
      Paint()
        ..color = GameColors.danger.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.028,
    );

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(t * 1.1);
    final tooth = Paint()..color = GameColors.danger;
    for (int i = 0; i < 6; i++) {
      final a = i * pi / 3;
      final inner = r * 0.94;
      final outer = r * 1.2;
      final path = Path()
        ..moveTo(cos(a) * inner, sin(a) * inner)
        ..lineTo(cos(a - 0.18) * outer, sin(a - 0.18) * outer)
        ..lineTo(cos(a + 0.18) * outer, sin(a + 0.18) * outer)
        ..close();
      canvas.drawPath(path, tooth);
    }
    canvas.restore();
  }

  void _drawVoidWell(Canvas canvas, _Metrics m, double radius, double angle,
      double t, int variant) {
    final pos = m.center + Offset(cos(angle), sin(angle)) * radius;
    final size = m.iconSize * 1.16;
    _drawHazardBadge(canvas, pos, size, t);
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: pos, radius: size * 0.44)),
    );
    _drawSprite(
      canvas,
      PlaySprites.voidZone(variant),
      pos,
      size * 0.9,
      cover: true,
      rotation: t * 1.4,
    );
    canvas.restore();
  }

  void _drawGate(
      Canvas canvas, _Metrics m, double radius, double angle, SlotKind kind, double t) {
    final pos = m.center + Offset(cos(angle), sin(angle)) * radius;
    final size = m.iconSize * 1.22;
    final color = GameColors.gate;
    canvas.drawCircle(
      pos,
      size * 0.58,
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.45),
    );
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: pos, radius: size * 0.5)),
    );
    _drawSprite(
      canvas,
      PlaySprites.gate(kind),
      pos,
      size,
      cover: true,
      rotation: t * 0.45,
    );
    canvas.restore();
    canvas.drawCircle(
      pos,
      size * 0.52,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.07,
    );
  }

  void _drawPickup(Canvas canvas, _Metrics m, double radius, double angle,
      SlotKind kind, SlotStyle style, double t, {int variant = 0}) {
    final pos = m.center + Offset(cos(angle), sin(angle)) * radius;
    final breathe = 0.92 + 0.08 * sin(t * 3 + angle * 4);
    final size = m.iconSize * breathe * (kind == SlotKind.prism ? 1.12 : 0.98);

    canvas.drawCircle(
      pos,
      size * 0.55,
      Paint()
        ..color = style.color.withValues(alpha: 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.5),
    );
    _drawSprite(
      canvas,
      PlaySprites.forPickup(kind, variant),
      pos,
      size,
      rotation: kind == SlotKind.energy ? t * 0.6 : 0,
    );
    // Smooth coloured ring: pickups never wear the spiked red hazard badge.
    canvas.drawCircle(
      pos,
      size * 0.58,
      Paint()
        ..color = style.color.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.07,
    );
  }

  void _drawOverlayStrike(Canvas canvas, _Metrics m, Rect bounds, double angle,
      double slotWidth, CoreStrike state, double t) {
    final thickness = m.laneThickness;
    final start = angle - slotWidth * 0.5;

    if (state == CoreStrike.lethal) {
      // The rail here is already gone; this is the beam standing in its place.
      canvas.drawArc(
        bounds,
        start,
        slotWidth,
        false,
        Paint()
          ..color = GameColors.danger.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness * 3.4
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 0.8),
      );
      canvas.drawArc(
        bounds,
        start,
        slotWidth,
        false,
        Paint()
          ..color = GameColors.danger
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness * 2.0
          ..strokeCap = StrokeCap.butt,
      );
      return;
    }

    // Winding up. A blurred wash blinking under the rail read as a smudge and
    // was easy to miss entirely, so the warning is drawn as hard brackets
    // clamped over the doomed slice instead: crisp, blinking, and obviously
    // sitting on top of a lane that is still there.
    final blink = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 14));
    canvas.drawArc(
      bounds,
      start,
      slotWidth,
      false,
      Paint()
        ..color = GameColors.danger.withValues(alpha: 0.22 * blink)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 2.6
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 0.7),
    );

    final edge = Paint()
      ..color = GameColors.danger.withValues(alpha: blink)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness * 0.22
      ..strokeCap = StrokeCap.round;
    final radius = bounds.width / 2;
    for (final side in const [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCircle(
            center: m.center, radius: radius + side * thickness * 1.15),
        start,
        slotWidth,
        false,
        edge,
      );
      final a = angle + side * slotWidth * 0.5;
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(
        m.center + dir * (radius - thickness * 1.15),
        m.center + dir * (radius + thickness * 1.15),
        edge,
      );
    }
  }

  // -- actors --------------------------------------------------------------

  void _drawCore(Canvas canvas, _Metrics m, double t) {
    final glowColor = switch (controller.coreVisualState) {
      CoreState.stable => const Color(0xFF3DEFFF),
      CoreState.pulse => const Color(0xFFFF4FD8),
      CoreState.expand => const Color(0xFFFFA23D),
      CoreState.collapse => GameColors.danger,
    };
    final warning = controller.coreWarning;
    final pulse = 0.5 + 0.5 * sin(t * (warning ? 10 : 2.2));
    final coreRadius = m.fieldRadius * (0.15 + pulse * (warning ? 0.02 : 0.01));

    canvas.drawCircle(
      m.center,
      coreRadius * 1.35,
      Paint()
        ..color = glowColor.withValues(alpha: 0.30 + pulse * 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, m.fieldRadius * 0.1),
    );

    canvas.save();
    canvas.translate(m.center.dx, m.center.dy);
    canvas.rotate(-t * 0.18);
    canvas.translate(-m.center.dx, -m.center.dy);
    _drawSprite(
      canvas,
      PlaySprites.coreRing(sector.core.column + sector.core.row * 2),
      m.center,
      coreRadius * 1.85,
      opacity: 0.9,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(m.center.dx, m.center.dy);
    canvas.rotate(t * 0.25);
    canvas.translate(-m.center.dx, -m.center.dy);
    _drawSprite(canvas, sector.core, m.center, coreRadius * 1.7);
    canvas.restore();
  }

  /// Spinning red rotors. Everything else red on the field is bolted to a lane
  /// and can be planned around; a drone moves, so it gets the one silhouette
  /// that is visibly in motion.
  void _drawDrones(Canvas canvas, _Metrics m, double t) {
    for (final drone in controller.drones) {
      if (drone.orbitIndex >= m.activeLanes) continue;
      final radius = m.lanes[drone.orbitIndex] * m.fieldRadius;
      final pos = m.center + Offset(cos(drone.angle), sin(drone.angle)) * radius;
      final size = m.iconSize * 1.08;
      final spin = t * 1.8 * (drone.variant.isEven ? 1 : -1);

      _drawHazardBadge(canvas, pos, size, t);
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: pos, radius: size * 0.44)),
      );
      _drawSprite(
        canvas,
        PlaySprites.drone(drone.variant),
        pos,
        size * 0.9,
        cover: true,
        rotation: spin,
      );
      canvas.restore();
    }
  }

  void _drawBallTrail(Canvas canvas, _Metrics m) {
    final radius = controller.ballRadiusFraction * m.fieldRadius;
    for (int i = 1; i <= 6; i++) {
      final a = controller.ballAngle - i * 0.045;
      final pos = m.center + Offset(cos(a), sin(a)) * radius;
      canvas.drawCircle(
        pos,
        m.fieldRadius * 0.026,
        Paint()
          ..color = GameColors.energy.withValues(alpha: (1 - i / 7) * 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _drawBall(Canvas canvas, _Metrics m, double t) {
    final radius = controller.ballRadiusFraction * m.fieldRadius;
    final pos = m.center + Offset(cos(controller.ballAngle), sin(controller.ballAngle)) * radius;
    // Comfortably larger than a pickup. At matching sizes the cyan starter
    // skin was indistinguishable from a Neon Energy orb, so the player could
    // not find themselves on the field.
    final size = m.fieldRadius * 0.155;

    double opacity = 1.0;
    if (controller.invulnTimer > 0) {
      opacity = 0.45 + 0.45 * (0.5 + 0.5 * sin(t * 28));
    }

    final grace = controller.voidGraceTimer;
    if (grace != null) {
      // Countdown ring closing in: how long is left to shift out of the well.
      final left = (grace / (GameBalance.voidGraceMs / 1000)).clamp(0.0, 1.0);
      canvas.drawCircle(
        pos,
        size * (0.8 + (1 - left) * 0.5),
        Paint()
          ..color = GameColors.danger.withValues(alpha: 0.5 * (1 - left))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.6),
      );
      canvas.drawArc(
        Rect.fromCircle(center: pos, radius: size * 0.95),
        -pi / 2,
        2 * pi * left,
        false,
        Paint()
          ..color = GameColors.danger
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.1
          ..strokeCap = StrokeCap.round,
      );
    }

    if (controller.phaseGhostTimer > 0) {
      canvas.drawCircle(
        pos,
        size * 0.85,
        Paint()
          ..color = GameColors.gate.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.08,
      );
    }

    canvas.drawCircle(
      pos,
      size * 0.72,
      Paint()
        ..color = GameColors.energy.withValues(alpha: 0.40 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.5),
    );

    _drawSprite(canvas, ball.sprite, pos, size, opacity: opacity);

    // A crisp white containment ring: the one white outline on the field, and
    // the fastest way to pick yourself out of a crowded lane.
    canvas.drawCircle(
      pos,
      size * 0.52,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.045,
    );

    for (int i = 0; i < controller.shields; i++) {
      canvas.drawCircle(
        pos,
        size * (0.66 + i * 0.11),
        Paint()
          ..color = GameColors.shield.withValues(alpha: 0.75 - i * 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.055,
      );
    }
  }

  // -- effects -------------------------------------------------------------

  void _drawFloatingTexts(Canvas canvas, _Metrics m) {
    for (final ft in controller.floatingTexts) {
      final lift = (1 - ft.life) * m.fieldRadius * 0.18;
      final base = m.center +
          Offset(cos(ft.angle), sin(ft.angle)) * (ft.radiusFraction * m.fieldRadius);
      final tp = TextPainter(
        text: TextSpan(
          text: ft.text,
          style: TextStyle(
            color: Color(ft.color).withValues(alpha: ft.life.clamp(0, 1)),
            fontSize: m.fieldRadius * 0.058,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, base - Offset(tp.width / 2, tp.height / 2 + lift));
    }
  }

  void _drawParticles(Canvas canvas, _Metrics m) {
    for (final p in controller.particles) {
      final progress = 1 - (p.life / p.maxLife);
      final base = m.center +
          Offset(cos(p.angle), sin(p.angle)) * (p.radiusFraction * m.fieldRadius);
      final paint = Paint()
        ..color = Color(p.color).withValues(alpha: (p.life / p.maxLife).clamp(0, 1) * 0.8);
      for (int i = 0; i < 8; i++) {
        final a = i * pi / 4;
        final dot = base + Offset(cos(a), sin(a)) * progress * m.fieldRadius * 0.12;
        canvas.drawCircle(dot, m.fieldRadius * 0.012, paint);
      }
    }
  }

  void _drawPrismVignette(Canvas canvas, Size size, double timer) {
    final alpha = min(timer, 1.0).clamp(0.0, 1.0) * 0.5;
    final rect = Offset.zero & size;
    final gradient = SweepGradient(
      colors: [
        GameColors.shard.withValues(alpha: alpha),
        GameColors.prism.withValues(alpha: alpha),
        GameColors.shield.withValues(alpha: alpha),
        GameColors.energy.withValues(alpha: alpha),
        GameColors.gate.withValues(alpha: alpha),
        GameColors.shard.withValues(alpha: alpha),
      ],
    );
    canvas.drawRect(
      rect.deflate(size.shortestSide * 0.01),
      Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.05
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.04),
    );
  }

  void _drawSprite(
    Canvas canvas,
    SpriteRef ref,
    Offset center,
    double size, {
    double opacity = 1.0,
    double rotation = 0,
    bool cover = false,
  }) {
    final image = images.get(ref.asset);
    if (image == null) return;
    final aspect = ref.aspectRatio;
    final double width;
    final double height;
    if (cover) {
      width = aspect >= 1 ? size * aspect : size;
      height = aspect >= 1 ? size : size / aspect;
    } else {
      width = aspect > 1 ? size : size * aspect;
      height = aspect > 1 ? size / aspect : size;
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (rotation != 0) canvas.rotate(rotation);
    canvas.drawImageRect(
      image,
      ref.sourceRectIn(image),
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}

/// Screen-space geometry for one frame, derived once so every draw call agrees
/// on lane thickness and icon size.
class _Metrics {
  _Metrics({
    required this.center,
    required this.fieldRadius,
    required this.lanes,
    required this.activeLanes,
  });

  final Offset center;
  final double fieldRadius;
  final List<double> lanes;
  final int activeLanes;

  /// Rail width, capped to a share of the lane pitch so five live lanes never
  /// bleed into one another.
  double get laneThickness {
    final pitch = activeLanes <= 1
        ? GameBalance.outermostLane - GameBalance.innermostLane
        : (GameBalance.outermostLane - GameBalance.innermostLane) /
            (activeLanes - 1);
    return fieldRadius * min(0.05, pitch * 0.20);
  }

  /// Size of a slot icon. Bounded by the arc length of an innermost-lane slot,
  /// which is the tightest on the field, and held well under the ball's own
  /// size so the two never read as the same kind of thing.
  double get iconSize {
    final innerArc = 2 *
        pi *
        GameBalance.innermostLane *
        fieldRadius /
        GameBalance.slotsPerOrbit;
    return min(innerArc * 0.92, fieldRadius * 0.155);
  }
}
