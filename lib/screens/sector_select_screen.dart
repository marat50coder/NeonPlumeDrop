import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/profile_service.dart';
import '../core/theme.dart';
import '../models/catalog.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/neon_button.dart';
import '../widgets/sprite_image.dart';

class SectorSelectScreen extends StatelessWidget {
  const SectorSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);

    return MenuScaffold(
      background: sector.background,
      title: 'Cosmic Sectors',
      onBack: () => Navigator.of(context).pop(),
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        itemCount: GameCatalog.sectors.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = GameCatalog.sectors[i];
          final unlocked = profile.unlockedSectorIds.contains(s.id);
          final selected = profile.selectedSectorId == s.id;
          return _SectorTile(sector: s, unlocked: unlocked, selected: selected);
        },
      ),
    );
  }
}

class _SectorTile extends StatelessWidget {
  const _SectorTile({
    required this.sector,
    required this.unlocked,
    required this.selected,
  });

  final SectorTheme sector;
  final bool unlocked;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final profile = context.read<ProfileService>();
    final outline = selected
        ? NeonColors.emerald
        : Colors.white.withValues(alpha: 0.15);
    // The outline goes in `foregroundDecoration`, matching the clip radius.
    // Drawn *inside* a ClipRRect it was a square border with its corners
    // sliced off by the clip, which is what made the frame look crooked.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: NeonColors.emerald.withValues(alpha: 0.3),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: outline, width: selected ? 2 : 1),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: unlocked ? 1 : 0.35,
              child: Image.asset(
                sector.background,
                fit: BoxFit.cover,
                // Row thumbnails never need the full-screen resolution
                // that the same six backgrounds ship at.
                cacheWidth: 512,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    NeonColors.voidBlack.withValues(alpha: 0.88),
                    NeonColors.voidBlack.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                // The sector's own core, which is the thing that actually
                // changes in play. Cropping the background to a letterbox strip
                // gave six near-identical dark smudges instead.
                Opacity(
                  opacity: unlocked ? 1 : 0.4,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: SpriteImage(ref: sector.core, cacheWidth: 256),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sector.name,
                        style: NeonTextStyles.heading(size: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        unlocked ? 'Unlocked' : sector.unlockDescription,
                        style: NeonTextStyles.body.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: NeonColors.emerald,
                    size: 28,
                  )
                else if (unlocked)
                  NeonButton(
                    label: 'Select',
                    dense: true,
                    onPressed: () => profile.selectSector(sector.id),
                  )
                else
                  const Icon(
                    Icons.lock_rounded,
                    color: Colors.white38,
                    size: 24,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
