import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/game_assets.dart';
import '../../core/image_loader.dart';
import '../../core/notification_service.dart';
import '../../core/orientation_controller.dart';
import '../../core/theme.dart';
import '../../screens/main_menu_screen.dart';
import '../core/flare_models.dart';
import '../flare_router.dart';
import '../infra/flare_boot.dart';
import 'flare_invite.dart';
import 'orbit_portal.dart';
import 'void_signal_page.dart';

class IgniteScreen extends StatefulWidget {
  const IgniteScreen({super.key, this.router});

  final FlareRouter? router;

  @override
  State<IgniteScreen> createState() => _IgniteScreenState();
}

class _IgniteScreenState extends State<IgniteScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _target = 0.08;
  double _shown = 0.0;

  double _assetProgress = 0;
  FlareLanding? _landing;
  bool _started = false;
  bool _navigating = false;
  late final DateTime _startTime;
  Timer? _hardDeadline;
  static const Duration _minHold = Duration(milliseconds: 1850);
  static const Duration _offlineFloor = Duration(milliseconds: 720);

  static const SystemUiOverlayStyle _blackChrome = SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    SystemChrome.setSystemUIOverlayStyle(_blackChrome);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _ticker = createTicker(_onTick)..start();
    _hardDeadline = Timer(const Duration(seconds: 11), () {
      if (mounted && !_navigating && _landing != null) {
        if (_landing is GameLanding && _assetProgress < 1) return;
        unawaited(_finalizeThenOpen());
      }
    });
  }

  @override
  void dispose() {
    _hardDeadline?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_begin());
    }
  }

  /// Never rewinds. Hard-capped below 1.0 so the meter cannot show 100%
  /// until [_finalizeThenOpen] runs immediately before the next screen.
  void _advance(double stage) {
    if (!mounted) return;
    setState(() => _target = max(_target, stage.clamp(0.0, 0.94)));
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    final diff = _target - _shown;
    if (diff <= 0) return;
    final speed = min(2.2, max(0.14, diff * 3.2));
    setState(() => _shown = min(_target, _shown + speed * dt));
  }

  Future<void> _begin() async {
    final router = widget.router;
    try {
      await router?.vault.initialize();
    } catch (_) {}
    if (router != null && !await router.probe.quickReach()) {
      await _openOfflineNow();
      return;
    }
    try {
      await router?.agent.prepare();
    } catch (_) {}
    await FlareBoot.warmGame();
    await FlareBoot.ensureProduction();
    if (router != null && !await router.probe.hasInterface()) {
      await _openOfflineNow();
      return;
    }
    await _resolveLanding();
    if (_landing is VoidLanding) {
      await _openOfflineNow();
      return;
    }
    if (_landing is GameLanding) {
      await _preloadGameArt();
    } else {
      _advance(0.92);
    }
    await _finalizeThenOpen();
  }

  Future<void> _resolveLanding() async {
    _advance(0.14);
    final router = widget.router;
    if (router == null) {
      _landing = const GameLanding();
      _advance(0.72);
      return;
    }
    try {
      _landing = await router.decide(
        onProgress: (value) => _advance(value * 0.72),
      );
    } catch (_) {
      _landing = const VoidLanding(returnToGame: false);
    }
    if (_landing is VoidLanding) return;
    _advance(0.78);
  }

  Future<void> _preloadGameArt() async {
    try {
      await ImageLoader.instance.preloadAll(
        GameAssets.allGameplayImages,
        onProgress: (p) {
          _assetProgress = p;
          _advance(0.78 + p * 0.14);
        },
      );
    } catch (_) {}
    _assetProgress = 1;
    _advance(0.92);
  }

  Future<void> _openOfflineNow() async {
    if (_navigating) return;
    _navigating = true;
    _hardDeadline?.cancel();
    _ticker.stop();
    final router = widget.router;
    if (router == null) return;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VoidSignalPage(
          probe: router.probe,
          retryBuilder: (_) => IgniteScreen(router: router),
        ),
      ),
    );
  }

  Future<void> _finalizeThenOpen() async {
    if (_navigating || _landing == null) return;
    if (_landing is GameLanding && _assetProgress < 1) return;
    _navigating = true;
    _hardDeadline?.cancel();

    final elapsed = DateTime.now().difference(_startTime);
    final floor = _landing is VoidLanding ? _offlineFloor : _minHold;
    if (elapsed < floor) {
      await Future<void>.delayed(floor - elapsed);
    }
    if (!mounted) return;

    const finish = Duration(milliseconds: 520);
    final started = DateTime.now();
    final from = _shown;
    final delta = 1.0 - from;
    while (mounted) {
      final t = (DateTime.now().difference(started).inMicroseconds /
              finish.inMicroseconds)
          .clamp(0.0, 1.0);
      final eased = 1 - pow(1 - t, 3).toDouble();
      setState(() {
        _shown = max(_shown, from + delta * eased);
        _target = max(_target, _shown);
      });
      if (t >= 1.0) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;

    _ticker.stop();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    if (!mounted) return;
    await _open(_landing!);
  }

  Future<void> _open(FlareLanding landing) async {
    final router = widget.router;

    if (landing is GameLanding || router == null) {
      try {
        await NotificationService.instance.syncWithProfile();
      } catch (_) {}
      await OrientationController.lockPortrait();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 480),
          pageBuilder: (_, _, _) => const MainMenuScreen(),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
      return;
    }

    if (landing is VoidLanding) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VoidSignalPage(
            probe: router.probe,
            retryBuilder: (_) => IgniteScreen(router: router),
          ),
        ),
      );
      return;
    }

    if (landing is PortalLanding) {
      Widget portalBuilder(BuildContext _) => OrbitPortal(
        url: landing.url,
        coldLaunch: landing.coldLaunch,
        vault: router.vault,
        probe: router.probe,
        pulse: router.pulse,
        agent: router.agent,
      );

      if (!landing.coldLaunch &&
          router.vault.shouldShowPushInvite &&
          await router.pulse.canOfferPermission()) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => FlareInvite(
              vault: router.vault,
              pulse: router.pulse,
              nextBuilder: portalBuilder,
              onTokenReady: router.refreshForToken,
            ),
          ),
        );
      } else if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute<void>(builder: portalBuilder));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final isPortrait = orientation == Orientation.portrait;
    final background = isPortrait
        ? GameAssets.loadingVertical
        : GameAssets.loadingHorizontal;
    final pct = _shown >= 0.995
        ? '100'
        : (_shown * 100).floor().clamp(0, 99).toString();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _blackChrome,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ColoredBox(
          color: Colors.black,
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  background,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: isPortrait ? 48 : 20,
                  child: Center(
                    child: SizedBox(
                      width: isPortrait ? 280 : 360,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _StrokeLabel(text: 'LOADING'),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 22,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _MeterPainter(_shown),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _StrokeLabel(text: '$pct%', size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StrokeLabel extends StatelessWidget {
  const _StrokeLabel({required this.text, this.size = 18});

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

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final inner = outer.deflate(3);

    canvas.drawRRect(outer, Paint()..color = Colors.black);
    canvas.drawRRect(inner, Paint()..color = const Color(0xFF120C28));

    const inset = 5.0;
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
    }

    canvas.drawRRect(
      inner,
      Paint()
        ..color = NeonColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _MeterPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
