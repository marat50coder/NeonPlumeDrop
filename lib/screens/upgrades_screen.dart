import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/profile_service.dart';
import '../core/theme.dart';
import '../game/game_models.dart';
import '../models/catalog.dart';
import '../widgets/currency_pill.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/neon_button.dart';

class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);

    return MenuScaffold(
      background: sector.background,
      title: 'Upgrades',
      onBack: () => Navigator.of(context).pop(),
      trailing: CurrencyPill(
        kind: SlotKind.energy,
        value: '${profile.neonEnergy}',
        color: NeonColors.cyan,
        compact: true,
      ),
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        itemCount: GameCatalog.upgrades.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _UpgradeTile(def: GameCatalog.upgrades[i]),
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({required this.def});

  final UpgradeDef def;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final level = profile.upgradeLevel(def.id);
    final maxed = level >= def.maxLevel;
    final cost = def.costForLevel(level);

    return Container(
      decoration: NeonColors.neonPanel(color: NeonColors.violet, opacity: 0.35),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(def.name, style: NeonTextStyles.heading(size: 15)),
              ),
              Text(
                maxed ? 'MAX' : 'Lv $level/${def.maxLevel}',
                style: NeonTextStyles.label.copyWith(color: NeonColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(def.description, style: NeonTextStyles.body),
          const SizedBox(height: 10),
          Row(
            children: List.generate(def.maxLevel, (i) {
              final filled = i < level;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  height: 6,
                  decoration: BoxDecoration(
                    color: filled
                        ? NeonColors.violet
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          NeonButton(
            label: maxed ? 'Fully Upgraded' : 'Upgrade • $cost Energy',
            icon: maxed ? Icons.check_rounded : Icons.arrow_upward_rounded,
            fullWidth: true,
            dense: true,
            style: NeonButtonStyle.secondary,
            onPressed: maxed
                ? null
                : () async {
                    final ok = await profile.spendNeonEnergy(cost);
                    if (ok) {
                      await profile.setUpgradeLevel(def.id, level + 1);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Not enough Neon Energy yet.')),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }
}
