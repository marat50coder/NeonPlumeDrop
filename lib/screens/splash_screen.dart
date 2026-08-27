import 'package:flutter/material.dart';

import '../core/audio_service.dart';
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
    AudioService.instance.playSfx(GameAssets.sfxScreenTransition);
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
                  width: isPortrait ? 240 : 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: SizedBox(
                          height: 8,
                          child: Stack(
                            children: [
                              Container(color: Colors.white.withValues(alpha: 0.12)),
                              FractionallySizedBox(
                                widthFactor: _progress.clamp(0, 1),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: NeonColors.titleGradient,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'LOADING ${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: NeonTextStyles.label.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          letterSpacing: 2,
                        ),
                      ),
                    ],
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
