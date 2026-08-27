import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
          AudioService.instance.playSfx(GameAssets.sfxCollectEnergy, volumeScale: 0.7);
          break;
        case GameSfxEvent.collectRare:
          AudioService.instance.playSfx(GameAssets.sfxCollectRareCrystal);
          Haptics.light();
          break;
        case GameSfxEvent.gateActivate:
          AudioService.instance.playSfx(GameAssets.sfxEnergyGateActivation, volumeScale: 0.8);
          break;
        case GameSfxEvent.shieldActivate:
          AudioService.instance.playSfx(GameAssets.sfxShieldActivation);
          Haptics.medium();
          break;
        case GameSfxEvent.collision:
          AudioService.instance.playSfx(GameAssets.sfxCollision);
          Haptics.heavy();
          break;
        case GameSfxEvent.dangerWarning:
          AudioService.instance.playSfx(GameAssets.sfxDangerWarning, volumeScale: 0.8);
          break;
        case GameSfxEvent.sectorPortal:
          AudioService.instance.playSfx(GameAssets.sfxSectorPortal);
          Haptics.medium();
          break;
        case GameSfxEvent.defeat:
          AudioService.instance.playSfx(GameAssets.sfxDefeat);
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

    if (result.newTime || result.newPhase) {
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

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  void _restart() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
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
                        final side = constraints.maxWidth < constraints.maxHeight
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
                            // The shift zones deliberately span the whole
                            // area under the HUD, not just the square play
                            // field: the tutorial promises "tap the left /
                            // right half of the screen", and the letterbox
                            // margins are wide on tall phones and iPads.
                            Positioned.fill(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapUp: (_) => _controller.attemptShift(-1),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapUp: (_) => _controller.attemptShift(1),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Positioned(
                              left: 10,
                              bottom: 10,
                              child: _HintChevron(
                                  icon: Icons.keyboard_double_arrow_left_rounded),
                            ),
                            const Positioned(
                              right: 10,
                              bottom: 10,
                              child: _HintChevron(
                                  icon: Icons.keyboard_double_arrow_right_rounded),
                            ),
                          ],
                        );
                      },
                    ),
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

class _HintChevron extends StatelessWidget {
  const _HintChevron({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, color: Colors.white.withValues(alpha: 0.18), size: 26);
  }
}
