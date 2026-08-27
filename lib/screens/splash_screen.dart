import 'package:flutter/material.dart';

import '../core/game_assets.dart';
import '../core/image_loader.dart';
import '../core/orientation_controller.dart';
import '../core/theme.dart';
import 'main_menu_screen.dart';

/// First screen shown on launch. It may appear in portrait or landscape on
/// both iPhone and iPad, swapping between the matching loading artworks.
/// Once gameplay assets are cached, the app locks to portrait.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEverything());
  }

  Future<void> _loadEverything() async {
    final minimumDelay = Future.delayed(const Duration(milliseconds: 900));
    try {
      await ImageLoader.instance.preloadAll(
        GameAssets.allGameplayImages,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (_) {
      // Preloading is an optimisation, never a gate: an unreadable asset
      // must not leave the player stranded on the loading screen.
    }
    await minimumDelay;
    if (!mounted || _leaving) return;
    _leaving = true;
    await OrientationController.lockPortrait();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const MainMenuScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final isPortrait = orientation == Orientation.portrait;
    final background =
        isPortrait ? GameAssets.loadingVertical : GameAssets.loadingHorizontal;

    return Scaffold(
      backgroundColor: NeonColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(background, fit: BoxFit.cover),
          Positioned(
            left: 0,
            right: 0,
            bottom: isPortrait ? 64 : 28,
            child: SafeArea(
              child: Center(
                child: SizedBox(
                  width: isPortrait ? 280 : 360,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _progress.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      final pct = (value * 100).clamp(0, 100).toStringAsFixed(0);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _OutlinedLabel(text: 'LOADING'),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 22,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _LoadingScalePainter(value),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _OutlinedLabel(text: '$pct%', size: 14),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White fill with a hard black stroke so the label stays readable on the
/// bright nebula artwork.
class _OutlinedLabel extends StatelessWidget {
  const _OutlinedLabel({required this.text, this.size = 18});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: 3.4,
      color: Colors.white,
      height: 1,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          style: fill.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.28
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black,
          ),
        ),
        Text(text, style: fill),
      ],
    );
  }
}

/// A chunky meter with tick marks, a black rim and a filling neon bar.
class _LoadingScalePainter extends CustomPainter {
  _LoadingScalePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final inner = outer.deflate(3);

    canvas.drawRRect(outer, Paint()..color = Colors.black);
    canvas.drawRRect(inner, Paint()..color = const Color(0xFF120C28));

    final inset = 5.0;
    final fillWidth = (size.width - inset * 2) * progress.clamp(0.0, 1.0);
    if (fillWidth > 1) {
      final fillRect = Rect.fromLTWH(
        inset,
        inset,
        fillWidth,
        size.height - inset * 2,
      );
      final fill = RRect.fromRectAndRadius(
        fillRect,
        Radius.circular((size.height - inset * 2) / 2),
      );
      canvas.drawRRect(
        fill,
        Paint()
          ..shader = const LinearGradient(
            colors: [NeonColors.cyan, NeonColors.magenta],
          ).createShader(fillRect),
      );
      canvas.drawRRect(
        fill,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    const ticks = 10;
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (int i = 1; i < ticks; i++) {
      final x = size.width * i / ticks;
      canvas.drawLine(
        Offset(x, size.height * 0.28),
        Offset(x, size.height * 0.72),
        tickPaint,
      );
    }

    canvas.drawRRect(
      inner,
      Paint()
        ..color = NeonColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingScalePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
