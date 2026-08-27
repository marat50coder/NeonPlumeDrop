import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/profile_service.dart';
import '../core/theme.dart';
import '../game/play_sprites.dart';
import '../models/catalog.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/sprite_image.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);

    return MenuScaffold(
      background: sector.background,
      title: 'Collection',
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          TabBar(
            controller: _tab,
            indicatorColor: NeonColors.cyan,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: NeonTextStyles.label,
            tabs: const [
              Tab(text: 'BALLS'),
              Tab(text: 'SECTORS'),
              Tab(text: 'ARTIFACTS'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _BallsGrid(profile: profile),
                _SectorsGrid(profile: profile),
                _ArtifactsGrid(profile: profile),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BallsGrid extends StatelessWidget {
  const _BallsGrid({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: GameCatalog.balls.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: adaptiveColumns(context),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, i) {
        final ball = GameCatalog.balls[i];
        final unlocked = profile.unlockedBallIds.contains(ball.id);
        return _CollectionCard(
          label: ball.name,
          unlocked: unlocked,
          lockHint: ball.unlockDescription,
          child: SpriteImage(ref: ball.sprite),
        );
      },
    );
  }
}

class _SectorsGrid extends StatelessWidget {
  const _SectorsGrid({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: GameCatalog.sectors.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: adaptiveColumns(context),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, i) {
        final s = GameCatalog.sectors[i];
        final unlocked = profile.unlockedSectorIds.contains(s.id);
        return _CollectionCard(
          label: s.name,
          unlocked: unlocked,
          lockHint: s.unlockDescription,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(s.background, fit: BoxFit.cover, cacheWidth: 320),
          ),
        );
      },
    );
  }
}

class _ArtifactsGrid extends StatelessWidget {
  const _ArtifactsGrid({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: ArtifactCatalog.items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: adaptiveColumns(context),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, i) {
        final item = ArtifactCatalog.items[i];
        final unlocked = item.unlockBestPhase == 0 ||
            profile.bestPhaseIndex1 >= item.unlockBestPhase;
        return _CollectionCard(
          label: item.name,
          unlocked: unlocked,
          lockHint: item.unlockDescription,
          child: SpriteImage(ref: item.sprite),
        );
      },
    );
  }
}

/// Desaturates per pixel and leaves alpha alone.
///
/// `ColorFilter.mode(black, BlendMode.saturation)` reads better in source but
/// blends against the whole saved layer, so every locked ball sat on a black
/// rectangle the size of its sprite box.
const ColorFilter _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.label,
    required this.unlocked,
    required this.lockHint,
    required this.child,
  });

  final String label;
  final bool unlocked;
  final String lockHint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: unlocked
          ? null
          : () => ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(lockHint))),
      child: Container(
        decoration: NeonColors.neonPanel(
          color: unlocked ? NeonColors.cyan : Colors.white24,
          opacity: unlocked ? 0.4 : 0.15,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: Opacity(
                opacity: unlocked ? 1 : 0.35,
                child: unlocked
                    ? child
                    : ColorFiltered(colorFilter: _greyscale, child: child),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: NeonTextStyles.label.copyWith(
                color: unlocked ? Colors.white : Colors.white38,
              ),
            ),
            if (!unlocked)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.lock_rounded, size: 14, color: Colors.white38),
              ),
          ],
        ),
      ),
    );
  }
}
