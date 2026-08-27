import 'package:flutter/material.dart';

import '../models/catalog.dart';

/// Circular time badge used in Collection and on the run-result screen.
class TimeMedalBadge extends StatelessWidget {
  const TimeMedalBadge({super.key, required this.medal, this.size = 72});

  final TimeMedal medal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inner = size * 0.72;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  medal.accent.withValues(alpha: 0.35),
                  medal.accent.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: medal.accent, width: size * 0.06),
              boxShadow: [
                BoxShadow(
                  color: medal.accent.withValues(alpha: 0.45),
                  blurRadius: size * 0.22,
                ),
              ],
            ),
          ),
          Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF10123A).withValues(alpha: 0.92),
              border: Border.all(
                color: medal.accent.withValues(alpha: 0.55),
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              medal.formattedTime,
              style: TextStyle(
                color: medal.accent,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.18,
                letterSpacing: 0.6,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
