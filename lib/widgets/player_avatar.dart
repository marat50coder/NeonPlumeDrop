import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Circular player portrait. Falls back to a person glyph when no photo is set.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.size,
    this.imagePath,
    this.onTap,
  });

  final double size;
  final String? imagePath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final file = imagePath == null ? null : File(imagePath!);
    final hasFile = file != null && file.existsSync();

    final portrait = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasFile
            ? Image.file(file, fit: BoxFit.cover, gaplessPlayback: true)
            : ColoredBox(
                color: NeonColors.panel,
                child: Icon(
                  Icons.person_rounded,
                  color: NeonColors.cyan,
                  size: size * 0.52,
                ),
              ),
      ),
    );

    final ring = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: NeonColors.cyan.withValues(alpha: 0.7),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: NeonColors.cyan.withValues(alpha: 0.35),
            blurRadius: 10,
          ),
        ],
      ),
      child: portrait,
    );

    if (onTap == null) return ring;
    return GestureDetector(onTap: onTap, child: ring);
  }
}
