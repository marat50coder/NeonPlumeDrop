import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/neon_button.dart';

class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.onResume,
    required this.onRestart,
    required this.onExit,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: NeonColors.voidBlack.withValues(alpha: 0.65),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                padding: const EdgeInsets.all(26),
                decoration: NeonColors.neonPanel(color: NeonColors.cyan, opacity: 0.6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pause_circle_filled_rounded, color: NeonColors.cyan, size: 44),
                    const SizedBox(height: 10),
                    Text('PAUSED', style: NeonTextStyles.title(size: 24)),
                    const SizedBox(height: 24),
                    NeonButton(
                      label: 'Resume',
                      icon: Icons.play_arrow_rounded,
                      fullWidth: true,
                      onPressed: onResume,
                    ),
                    const SizedBox(height: 12),
                    NeonButton(
                      label: 'Restart',
                      icon: Icons.replay_rounded,
                      fullWidth: true,
                      style: NeonButtonStyle.secondary,
                      onPressed: onRestart,
                    ),
                    const SizedBox(height: 12),
                    NeonButton(
                      label: 'Exit to Menu',
                      icon: Icons.home_rounded,
                      fullWidth: true,
                      style: NeonButtonStyle.ghost,
                      playBackSound: true,
                      onPressed: onExit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
