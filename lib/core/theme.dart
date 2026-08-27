import 'package:flutter/material.dart';

/// Neon / cosmic color palette shared by every screen in the app.
class NeonColors {
  NeonColors._();

  static const Color voidBlack = Color(0xFF03040F);
  static const Color deepSpace = Color(0xFF0A0B24);
  static const Color panel = Color(0xFF10123A);
  static const Color panelLight = Color(0xFF181B4C);

  static const Color cyan = Color(0xFF3DEFFF);
  static const Color magenta = Color(0xFFFF4FD8);
  static const Color violet = Color(0xFF9B5CFF);
  static const Color deepBlue = Color(0xFF3A5CFF);
  static const Color emerald = Color(0xFF33FFB0);
  static const Color whiteEnergy = Color(0xFFF3F7FF);
  static const Color gold = Color(0xFFFFC85C);
  static const Color danger = Color(0xFFFF3B5C);

  static const List<Color> rainbow = [
    Color(0xFFFF4FD8),
    Color(0xFFFFC85C),
    Color(0xFF33FFB0),
    Color(0xFF3DEFFF),
    Color(0xFF9B5CFF),
  ];

  static LinearGradient titleGradient = const LinearGradient(
    colors: [cyan, magenta],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration neonPanel({
    Color color = cyan,
    double opacity = 0.5,
    double radius = 20,
    double glow = 0.28,
  }) {
    return BoxDecoration(
      color: panel.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: color.withValues(alpha: opacity), width: 1.4),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: glow),
          blurRadius: 18,
          spreadRadius: 1,
        ),
      ],
    );
  }

  /// Rounded border only, for panels that clip artwork of their own and so
  /// must draw the outline over the clipped content rather than inside it.
  static BoxDecoration neonOutline({Color color = cyan, double opacity = 0.5, double radius = 20}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: color.withValues(alpha: opacity), width: 1.4),
    );
  }
}

class NeonTextStyles {
  NeonTextStyles._();

  static TextStyle title({double size = 32, Color color = Colors.white}) {
    return TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
      color: color,
      height: 1.05,
      shadows: [
        Shadow(color: NeonColors.cyan.withValues(alpha: 0.9), blurRadius: 18),
        Shadow(
          color: NeonColors.magenta.withValues(alpha: 0.6),
          blurRadius: 30,
        ),
      ],
    );
  }

  static TextStyle heading({double size = 20, Color color = Colors.white}) {
    return TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: color,
      shadows: [
        Shadow(color: NeonColors.cyan.withValues(alpha: 0.55), blurRadius: 10),
      ],
    );
  }

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Color(0xFFC9CDEF),
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: Color(0xFF9AA0D6),
  );

  static TextStyle stat({double size = 16, Color color = Colors.white}) {
    return TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: color,
    );
  }
}

bool isTablet(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

int adaptiveColumns(BuildContext context, {int phone = 3, int tablet = 4}) =>
    isTablet(context) ? tablet : phone;

/// Clamps text scaling so large-font accessibility settings never break the
/// tight HUD layouts used across the game.
class ClampedTextScale extends StatelessWidget {
  const ClampedTextScale({super.key, required this.child, this.max = 1.15});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scaler = mq.textScaler.clamp(minScaleFactor: 0.8, maxScaleFactor: max);
    return MediaQuery(
      data: mq.copyWith(textScaler: scaler),
      child: child,
    );
  }
}
