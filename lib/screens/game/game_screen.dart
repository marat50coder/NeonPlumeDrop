import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/analytics_service.dart';
import '../../core/audio_service.dart';
import '../../core/game_assets.dart';
import '../../core/haptics.dart';
import '../../core/profile_service.dart';
import '../../core/theme.dart';
import '../../game/game_painter.dart';
import '../../game/run_controller.dart';
import '../../game/run_modifiers.dart';
import '../../models/catalog.dart';
import '../../models/daily_challenge.dart';
import '../../models/run_summary.dart';
import '../run_result_screen.dart';
import 'hud.dart';
import 'pause_overlay.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  late final RunController _controller;
  late final BallSkin _ball;
  late final SectorTheme _sector;
  bool _paused = false;
  bool _finishing = false;
  double _countdown = 3.0;
  double _goTimer = 0;
  bool _showGo = false;
  int? _lastCountDigit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final profile = ProfileService.instance;
    _ball = GameCatalog.ballById(profile.selectedBallId);
    _sector = GameCatalog.sectorById(profile.selectedSectorId);
    _controller = RunController(modifiers: RunModifiers.fromProfile(profile));
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_paused && mounted) {
      setState(() => _paused = true);
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (_paused || _finishing) return;
    if (dt <= 0 || dt > 0.25) return;

    if (_countdown > 0) {
      _countdown = (_countdown - dt).clamp(0.0, 3.0);
      final digit = _countdown == 0 ? 0 : _countdown.ceil();
      if (digit != _lastCountDigit && digit > 0) {
        _lastCountDigit = digit;
        AudioService.instance.click();
      }
      if (_countdown == 0) {
        _showGo = true;
        _goTimer = 0.55;
      }
      if (mounted) setState(() {});
      return;
    }

    if (_goTimer > 0) {
      _goTimer = max(0, _goTimer - dt);
      if (_goTimer == 0) _showGo = false;
    }

    _controller.update(dt);
    _drainEvents();

    if (_controller.gameOver && !_finishing) {
      _finishing = true;
      _finishRun();
    }

    if (mounted) setState(() {});
  }

  void _drainEvents() {
    for (final event in _controller.drainSfxEvents()) {
      switch (event) {
        case GameSfxEvent.orbitalShift:
          AudioService.instance.playSfx(GameAssets.sfxOrbitalShift);
          Haptics.light();
          break;
        case GameSfxEvent.shiftDenied:
          Haptics.selection();
          break;
        case GameSfxEvent.collectEnergy:
          AudioService.instance.playSfx(
            GameAssets.sfxCollectEnergy,
            volumeScale: 0.95,
          );
          break;
        case GameSfxEvent.collectRare:
          AudioService.instance.playSfx(
            GameAssets.sfxCollectEnergy,
            volumeScale: 0.95,
          );
          Haptics.light();
          break;
        case GameSfxEvent.gateActivate:
          AudioService.instance.playSfx(
            GameAssets.sfxCollectEnergy,
            volumeScale: 0.95,
          );
          break;
        case GameSfxEvent.shieldActivate:
          AudioService.instance.playSfx(GameAssets.sfxShieldActivation);
          Haptics.medium();
          break;
        case GameSfxEvent.collision:
          AudioService.instance.playSfx(
            GameAssets.sfxCollision,
            volumeScale: 0.45,
          );
          Haptics.heavy();
          break;
        case GameSfxEvent.dangerWarning:
          AudioService.instance.playSfx(
            GameAssets.sfxDangerWarning,
            volumeScale: 0.65,
          );
          break;
        case GameSfxEvent.sectorPortal:
          AudioService.instance.playSfx(
            GameAssets.sfxCollectEnergy,
            volumeScale: 0.95,
          );
          Haptics.medium();
          break;
        case GameSfxEvent.defeat:
          AudioService.instance.playSfx(
            GameAssets.sfxDefeat,
            volumeScale: 0.32,
          );
          break;
      }
    }
  }

  Future<void> _finishRun() async {
    final stats = _controller.collectStats();
    final profile = ProfileService.instance;
    final result = await profile.applyRunResult(
      survivalSeconds: stats.survivalSeconds,
      phaseIndex1: stats.phaseIndex1,
      neonEnergyEarned: stats.neonEnergyEarned,
      crystalShardsEarned: stats.crystalShardsEarned,
    );
    await AnalyticsService.instance.logRunComplete(
      survivalSeconds: stats.survivalSeconds,
      phaseIndex1: stats.phaseIndex1,
      neonEnergyEarned: stats.neonEnergyEarned,
    );

    bool dailyDone = false;
    final dc = profile.dailyChallenge;
    if (dc != null && !dc.claimed) {
      final progress = switch (dc.type) {
        DailyChallengeType.survivePhases => stats.phaseIndex1,
        DailyChallengeType.collectShards => stats.crystalShardsEarned,
        DailyChallengeType.activateGates => stats.gatesActivated,
        DailyChallengeType.surviveNoHitSeconds => stats.maxNoHitStreak.round(),
      };
      final wasComplete = dc.isComplete;
      await profile.updateDailyProgress(progress);
      dailyDone = !wasComplete && (profile.dailyChallenge?.isComplete ?? false);
    }

    if (result.newTime || result.newPhase || result.newMedals.isNotEmpty) {
      AudioService.instance.playSfx(GameAssets.sfxVictory);
    } else {
      AudioService.instance.playSfx(GameAssets.sfxScreenTransition);
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final summary = RunSummary(
      survivalSeconds: stats.survivalSeconds,
      phaseReached: _controller.band.phase,
      neonEnergyEarned: stats.neonEnergyEarned,
      crystalShardsEarned: stats.crystalShardsEarned,
      gatesActivated: stats.gatesActivated,
      isNewBestTime: result.newTime,
      isNewBestPhase: result.newPhase,
      newlyUnlockedMedals: result.newMedals,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RunResultScreen(
          summary: summary,
          dailyChallengeJustCompleted: dailyDone,
        ),
      ),
    );
  }

  bool get _runLive => _countdown <= 0 && !_paused && !_finishing;

  void _shiftIn() {
    if (_runLive) _controller.attemptShift(-1);
  }

  void _shiftOut() {
    if (_runLive) _controller.attemptShift(1);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  void _restart() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  void _exitToMenu() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_paused) setState(() => _paused = true);
      },
      child: Scaffold(
        backgroundColor: NeonColors.voidBlack,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(_sector.background, fit: BoxFit.cover),
            Container(color: NeonColors.voidBlack.withValues(alpha: 0.25)),
            SafeArea(
              child: Column(
                children: [
                  GameHud(controller: _controller, onPause: _togglePause),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side =
                            constraints.maxWidth < constraints.maxHeight
                            ? constraints.maxWidth
                            : constraints.maxHeight;
                        return Stack(
                          children: [
                            Center(
                              child: SizedBox(
                                width: side,
                                height: side,
                                child: CustomPaint(
                                  painter: GamePainter(
                                    controller: _controller,
                                    sector: _sector,
                                    ball: _ball,
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapUp: (_) => _shiftIn(),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapUp: (_) => _shiftOut(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_countdown > 0 || _showGo)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: _CountdownBurst(
                                    label: _showGo || _countdown <= 0
                                        ? 'GO'
                                        : '${_countdown.ceil()}',
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  _ShiftControls(
                    enabled: _runLive,
                    onIn: _shiftIn,
                    onOut: _shiftOut,
                  ),
                ],
              ),
            ),
            if (_paused)
              PauseOverlay(
                onResume: _togglePause,
                onRestart: _restart,
                onExit: _exitToMenu,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftControls extends StatelessWidget {
  const _ShiftControls({
    required this.enabled,
    required this.onIn,
    required this.onOut,
  });

  final bool enabled;
  final VoidCallback onIn;
  final VoidCallback onOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 10),
      child: Row(
        children: [
          Expanded(
            child: _ShiftArrowButton(
              enabled: enabled,
              icon: Icons.keyboard_arrow_left_rounded,
              label: 'IN',
              color: NeonColors.cyan,
              onPressed: onIn,
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: _ShiftArrowButton(
              enabled: enabled,
              icon: Icons.keyboard_arrow_right_rounded,
              label: 'OUT',
              color: NeonColors.magenta,
              onPressed: onOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftArrowButton extends StatelessWidget {
  const _ShiftArrowButton({
    required this.enabled,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final bool enabled;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: NeonColors.panel.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 16),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 34),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownBurst extends StatelessWidget {
  const _CountdownBurst({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final go = label == 'GO';
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) {
          return ScaleTransition(
            scale: Tween<double>(begin: 1.55, end: 1).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        child: _OutlinedCountdown(
          key: ValueKey(label),
          text: label,
          size: go ? 72 : 108,
          color: go ? NeonColors.emerald : NeonColors.cyan,
        ),
      ),
    );
  }
}

class _OutlinedCountdown extends StatelessWidget {
  const _OutlinedCountdown({
    super.key,
    required this.text,
    required this.size,
    required this.color,
  });

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: text.length == 1 ? 0 : 6,
      color: color,
      height: 1,
      shadows: [
        Shadow(color: color.withValues(alpha: 0.95), blurRadius: 22),
        Shadow(color: Colors.black, blurRadius: 8),
      ],
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          style: fill.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.08
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black,
          ),
        ),
        Text(text, style: fill),
      ],
    );
  }
}
