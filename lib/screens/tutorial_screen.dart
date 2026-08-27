import 'package:flutter/material.dart';

import '../core/game_assets.dart';
import '../core/profile_service.dart';
import '../core/theme.dart';
import '../game/game_models.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/neon_button.dart';
import '../widgets/slot_legend.dart';

class _TutorialPage {
  const _TutorialPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.legend = const [],
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  /// Slot kinds to show as real, drawn examples underneath [body].
  final List<SlotKind> legend;
}

const List<_TutorialPage> _pages = [
  _TutorialPage(
    icon: Icons.blur_circular_rounded,
    color: NeonColors.cyan,
    title: 'One Move Only',
    body: 'Your energy ball circles the collapsing core on its own. You never '
        'steer it. Tap the LEFT half of the screen, or the left arrow, to '
        'shift one lane inward. The RIGHT half or the right arrow shifts '
        'one lane outward. That is the whole game: picking the moment to '
        'change lanes.',
  ),
  _TutorialPage(
    icon: Icons.warning_amber_rounded,
    color: NeonColors.danger,
    title: 'Hazards End The Run',
    body: 'Anything inside a spiked red ring is lethal: circular mines, '
        'missing track, purple void wells and hunting drones all cost a hit. '
        'Smooth coloured rings are pickups — always safe. Cracked amber rail '
        'still lets you through — once. Shift before a well pulls you in.',
    legend: [
      SlotKind.obstacle,
      SlotKind.breach,
      SlotKind.voidZone,
      SlotKind.cracked,
    ],
  ),
  _TutorialPage(
    icon: Icons.diamond_rounded,
    color: NeonColors.violet,
    title: 'Take The Glow',
    body: 'Neon Energy, Crystal Shards, Shield Cores and Rare Prism Cores are '
        'always safe to collect. Inner lanes hold the richest prizes — and '
        'the most danger. Outer lanes are calmer and pay less.',
    legend: [
      SlotKind.energy,
      SlotKind.shard,
      SlotKind.shield,
      SlotKind.prism,
    ],
  ),
  _TutorialPage(
    icon: Icons.meeting_room_rounded,
    color: NeonColors.emerald,
    title: 'Fly The Gates',
    body: 'Circular energy portals on a lane are always worth taking. '
        'Energy Gates pay a burst of Neon Energy, Surge Gates clear the '
        'track ahead, and Ghost Gates let you phase through the next hits.',
    legend: [
      SlotKind.gateEnergy,
      SlotKind.gateSurge,
      SlotKind.gateGhost,
    ],
  ),
  _TutorialPage(
    icon: Icons.dangerous_rounded,
    color: NeonColors.gold,
    title: 'Watch The Core',
    body: 'The core strikes on a timer. Red bars blink across the lanes it is '
        'about to cut -- that blink is your warning to be somewhere else. Each '
        'phase speeds the ball up and opens another lane, so the arena keeps '
        'growing as the collapse deepens.',
  ),
];

/// Centres a page, but lets it scroll on short screens rather than overflow.
class _PageBody extends StatelessWidget {
  const _PageBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, this.startOfGame = false});

  final bool startOfGame;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    // Also covers the iOS swipe-back gesture: however the first-run
    // tutorial is left, it must not reappear on the next launch.
    if (widget.startOfGame) {
      ProfileService.instance.setTutorialCompleted(true);
    }
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    ProfileService.instance.setTutorialCompleted(true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    return MenuScaffold(
      background: GameAssets.bgDeepNeonSpace,
      title: 'How to Play',
      onBack: widget.startOfGame ? null : () => Navigator.of(context).pop(),
      trailing: widget.startOfGame
          ? TextButton(
              onPressed: _finish,
              child: const Text('Skip', style: TextStyle(color: Colors.white54)),
            )
          : null,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final page = _pages[i];
                return _PageBody(
                  children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: page.color.withValues(alpha: 0.15),
                          border: Border.all(
                            color: page.color.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(page.icon, color: page.color, size: 38),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        page.title,
                        style: NeonTextStyles.heading(size: 22),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        page.body,
                        textAlign: TextAlign.center,
                        style: NeonTextStyles.body.copyWith(fontSize: 14, height: 1.5),
                      ),
                      if (page.legend.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: NeonColors.neonPanel(
                            color: page.color,
                            opacity: 0.25,
                            radius: 18,
                            glow: 0.12,
                          ),
                          child: SlotLegend(kinds: page.legend),
                        ),
                      ],
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? NeonColors.cyan : Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          NeonButton(
            label: isLast ? "Let's Go" : 'Next',
            icon: isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
            fullWidth: true,
            onPressed: () {
              if (isLast) {
                _finish();
              } else {
                _controller.nextPage(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
