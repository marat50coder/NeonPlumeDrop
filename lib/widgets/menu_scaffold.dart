import 'package:flutter/material.dart';

import '../core/game_assets.dart';
import '../core/theme.dart';
import 'neon_button.dart';

/// Shared chrome for every non-gameplay screen: a full-bleed cosmic
/// background (covers the whole device regardless of aspect ratio, so it
/// looks correct on both iPhone and iPad), a scrim for legibility, and a
/// centered content column clamped to a comfortable reading width so
/// layouts don't stretch awkwardly on large iPad screens.
class MenuScaffold extends StatelessWidget {
  const MenuScaffold({
    super.key,
    required this.child,
    this.background = GameAssets.bgDeepNeonSpace,
    this.title,
    this.onBack,
    this.trailing,
    this.maxContentWidth = 560,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
  });

  final Widget child;
  final String background;
  final String? title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final double maxContentWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final maxW = isTablet(context) ? 720.0 : maxContentWidth;
    return Scaffold(
      backgroundColor: NeonColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(background, fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  NeonColors.voidBlack.withValues(alpha: 0.35),
                  NeonColors.voidBlack.withValues(alpha: 0.55),
                  NeonColors.voidBlack.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (title != null || onBack != null || trailing != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              if (onBack != null)
                                NeonIconButton(
                                  icon: Icons.arrow_back_rounded,
                                  semanticLabel: 'Back',
                                  onPressed: onBack,
                                ),
                              if (onBack != null) const SizedBox(width: 12),
                              if (title != null)
                                Expanded(
                                  child: Text(
                                    title!,
                                    style: NeonTextStyles.heading(size: 22),
                                  ),
                                ),
                              ?trailing,
                            ],
                          ),
                        ),
                      Expanded(child: child),
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
