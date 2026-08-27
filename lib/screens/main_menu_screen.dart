import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/audio_service.dart';
import '../core/game_assets.dart';
import '../core/game_balance.dart';
import '../core/haptics.dart';
import '../core/profile_service.dart';
import '../core/theme.dart';
import '../game/game_models.dart';
import '../models/catalog.dart';
import '../widgets/currency_pill.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/neon_button.dart';
import '../widgets/sprite_image.dart';
import 'ball_select_screen.dart';
import 'collection_screen.dart';
import 'daily_challenge_screen.dart';
import 'game/game_screen.dart';
import 'records_screen.dart';
import 'sector_select_screen.dart';
import 'settings_screen.dart';
import 'tutorial_screen.dart';
import 'upgrades_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  )..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profile = ProfileService.instance;
      if (!profile.tutorialCompleted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TutorialScreen(startOfGame: true)),
        );
      }
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);
    final bestPhase = profile.bestPhaseIndex1 > 0
        ? CollapsePhase.values[profile.bestPhaseIndex1 - 1].label
        : '—';

    return MenuScaffold(
      background: sector.background,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    CurrencyPill(
                      kind: SlotKind.energy,
                      value: '${profile.neonEnergy}',
                      color: NeonColors.cyan,
                    ),
                    CurrencyPill(
                      kind: SlotKind.shard,
                      value: '${profile.crystalShards}',
                      color: NeonColors.magenta,
                    ),
                  ],
                ),
              ),
              NeonIconButton(
                icon: Icons.settings_rounded,
                semanticLabel: 'Settings',
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          // The logo block soaks up every bit of slack, which keeps PLAY and
          // the tile grid together as one bottom-anchored cluster instead of
          // scattering them down the screen with gaps between.
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: 'game-logo',
                    child: Image.asset(GameAssets.gameLogo, width: isTablet(context) ? 280 : 240),
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _spin.value * 2 * pi,
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: SpriteImage(ref: sector.core, cacheWidth: 360),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'BEST  $bestPhase  •  ${_formatTime(profile.bestSurvivalSeconds)}',
                    style: NeonTextStyles.label.copyWith(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          NeonButton(
            label: 'PLAY',
            icon: Icons.play_arrow_rounded,
            fullWidth: true,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GameScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _MenuGrid(profile: profile),
        ],
      ),
    );
  }

  String _formatTime(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.profile});

  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    final dc = profile.dailyChallenge;
    final dailyReady = dc != null && dc.isComplete && !dc.claimed;

    final items = <_MenuItem>[
      _MenuItem('Energy Ball', Icons.blur_circular_rounded, NeonColors.cyan,
          (ctx) => const BallSelectScreen()),
      _MenuItem('Upgrades', Icons.upgrade_rounded, NeonColors.violet,
          (ctx) => const UpgradesScreen()),
      _MenuItem('Sectors', Icons.public_rounded, NeonColors.magenta,
          (ctx) => const SectorSelectScreen()),
      _MenuItem('Collection', Icons.auto_awesome_rounded, NeonColors.emerald,
          (ctx) => const CollectionScreen()),
      _MenuItem('Daily Task', Icons.today_rounded, NeonColors.gold,
          (ctx) => const DailyChallengeScreen(),
          badge: dailyReady),
      _MenuItem('Records', Icons.emoji_events_rounded, NeonColors.deepBlue,
          (ctx) => const RecordsScreen()),
    ];

    final cols = adaptiveColumns(context, phone: 3, tablet: 3);

    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Square. At 0.92 the tiles came out taller than wide, and with a 20pt
        // corner radius on a narrow box they read as vertical pills.
        childAspectRatio: 1,
      ),
      itemBuilder: (context, i) => _MenuTile(item: items[i]),
    );
  }
}

class _MenuItem {
  _MenuItem(this.label, this.icon, this.color, this.builder, {this.badge = false});
  final String label;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  final bool badge;
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        AudioService.instance.menuOpen();
        Navigator.of(context).push(MaterialPageRoute(builder: item.builder));
      },
      // Expand, or the stack hands the tile loose constraints and the panel
      // shrinks to the width of its own label -- which is why the tiles came
      // out as vertical pills of six different widths.
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: NeonColors.neonPanel(
              color: item.color,
              opacity: 0.42,
              radius: 16,
              glow: 0.18,
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: item.color, size: 30),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: NeonTextStyles.label.copyWith(
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          if (item.badge)
            Positioned(
              top: 7,
              right: 7,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: NeonColors.danger,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: NeonColors.danger.withValues(alpha: 0.8),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
