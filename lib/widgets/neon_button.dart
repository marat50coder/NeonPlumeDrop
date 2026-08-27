import 'package:flutter/material.dart';

import '../core/audio_service.dart';
import '../core/haptics.dart';
import '../core/theme.dart';

enum NeonButtonStyle { primary, secondary, danger, ghost }

/// A tactile, glowing pill button used across every menu screen. Handles
/// its own click sound + haptic feedback so call sites stay terse.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.style = NeonButtonStyle.primary,
    this.fullWidth = false,
    this.dense = false,
    this.playBackSound = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NeonButtonStyle style;
  final bool fullWidth;
  final bool dense;
  final bool playBackSound;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _pressed = false;

  (Color, Color) get _colors => switch (widget.style) {
        NeonButtonStyle.primary => (NeonColors.cyan, NeonColors.deepBlue),
        NeonButtonStyle.secondary => (NeonColors.violet, NeonColors.magenta),
        NeonButtonStyle.danger => (NeonColors.danger, const Color(0xFF7A0F24)),
        NeonButtonStyle.ghost => (const Color(0xFF6B7280), const Color(0xFF1B1E3D)),
      };

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final (accent, accent2) = _colors;
    final scale = _pressed ? 0.96 : 1.0;
    final button = Opacity(
      opacity: _enabled ? 1 : 0.45,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled
            ? (_) {
                setState(() => _pressed = false);
                Haptics.selection();
                if (widget.playBackSound) {
                  AudioService.instance.back();
                } else {
                  AudioService.instance.click();
                }
                widget.onPressed?.call();
              }
            : null,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: widget.fullWidth ? double.infinity : null,
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 18 : 26,
              vertical: widget.dense ? 12 : 16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: 0.85), accent2.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: Colors.white, size: widget.dense ? 16 : 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: widget.dense ? 13 : 16,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: button,
    );
  }
}

/// A round icon-only neon button, used for pause/back/settings glyphs.
class NeonIconButton extends StatelessWidget {
  const NeonIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.size = 44,
    this.color = NeonColors.cyan,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onPressed != null,
      child: GestureDetector(
        onTap: onPressed == null
            ? null
            : () {
                Haptics.selection();
                AudioService.instance.click();
                onPressed!.call();
              },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: NeonColors.panel.withValues(alpha: 0.85),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12),
            ],
          ),
          child: Icon(icon, color: color, size: size * 0.5),
        ),
      ),
    );
  }
}
