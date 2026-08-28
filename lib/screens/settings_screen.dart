import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/audio_service.dart';
import '../core/avatar_service.dart';
import '../core/notification_service.dart';
import '../core/profile_service.dart';
import '../core/theme.dart';
import '../flarepath/config/flare_config.dart';
import '../models/catalog.dart';
import '../widgets/menu_scaffold.dart';
import '../widgets/player_avatar.dart';
import 'tutorial_screen.dart';
import 'webview_screen.dart';

String get kPrivacyPolicyUrl => FlareConfig.privacyUrl;
String get kSupportUrl => FlareConfig.supportUrl;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileService>();
    final sector = GameCatalog.sectorById(profile.selectedSectorId);

    return MenuScaffold(
      background: sector.background,
      title: 'Settings',
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          _SectionLabel('PROFILE'),
          _Panel(
            children: [
              _AvatarRow(
                imagePath: profile.avatarPath,
                onChange: () => _pickAvatar(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('AUDIO & HAPTICS'),
          _Panel(
            children: [
              _SliderRow(
                icon: Icons.graphic_eq_rounded,
                label: 'Sound Effects',
                value: profile.sfxVolume,
                onChanged: profile.setSfxVolume,
                onChangeEnd: (_) => AudioService.instance.click(),
              ),
              const Divider(color: Colors.white12, height: 24),
              _SwitchRow(
                icon: Icons.vibration_rounded,
                label: 'Vibration',
                value: profile.vibrationEnabled,
                onChanged: (v) => profile.setVibrationEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('ALERTS'),
          _Panel(
            children: [
              _SwitchRow(
                icon: Icons.notifications_rounded,
                label: 'Daily reminder',
                value: profile.notificationsEnabled,
                onChanged: (v) => _setNotifications(context, v),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('GAME'),
          _Panel(
            children: [
              _ActionRow(
                icon: Icons.school_rounded,
                label: 'How to Play',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TutorialScreen(startOfGame: false),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('LEGAL & SUPPORT'),
          _Panel(
            children: [
              _ActionRow(
                icon: Icons.privacy_tip_rounded,
                label: 'Privacy Policy',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SimpleWebViewScreen(
                      title: 'Privacy Policy',
                      url: kPrivacyPolicyUrl,
                    ),
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 24),
              _ActionRow(
                icon: Icons.support_agent_rounded,
                label: 'Support',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SimpleWebViewScreen(
                      title: 'Support',
                      url: kSupportUrl,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Neon Plume Drop v1.0.3',
              style: NeonTextStyles.body.copyWith(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setNotifications(BuildContext context, bool enabled) async {
    if (enabled) {
      final ok = await NotificationService.instance.enableDailyReminder();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications are turned off for this app.'),
          ),
        );
      }
    } else {
      await NotificationService.instance.disable();
    }
  }

  Future<void> _pickAvatar(BuildContext context) async {
    final profile = ProfileService.instance;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NeonColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Player avatar', style: NeonTextStyles.heading(size: 18)),
                const SizedBox(height: 16),
                _ActionRow(
                  icon: Icons.photo_camera_rounded,
                  label: 'Take photo',
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _tryPick(context, ImageSource.camera);
                  },
                ),
                const Divider(color: Colors.white12, height: 24),
                _ActionRow(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose from gallery',
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _tryPick(context, ImageSource.gallery);
                  },
                ),
                if (profile.avatarPath != null) ...[
                  const Divider(color: Colors.white12, height: 24),
                  _ActionRow(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove avatar',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await AvatarService.clear();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _tryPick(BuildContext context, ImageSource source) async {
    try {
      await AvatarService.pickAndSave(source);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? 'Camera is not available on this device.'
                : 'Could not open the photo library.',
          ),
        ),
      );
    }
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.imagePath, required this.onChange});

  final String? imagePath;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChange,
      child: Row(
        children: [
          PlayerAvatar(size: 64, imagePath: imagePath),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your avatar',
                  style: NeonTextStyles.body.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Camera or photo library',
                  style: NeonTextStyles.body.copyWith(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.edit_rounded, color: Colors.white38, size: 20),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        text,
        style: NeonTextStyles.label.copyWith(color: NeonColors.cyan),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: NeonColors.neonPanel(color: NeonColors.cyan, opacity: 0.3),
      child: Column(children: children),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: NeonTextStyles.body.copyWith(color: Colors.white),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: NeonColors.cyan,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: NeonColors.cyan.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              // Previewing the new volume once the player lets go, rather
              // than on every drag tick, avoids a burst of dozens of
              // overlapping clicks across the effect-player pool.
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: NeonTextStyles.body.copyWith(color: Colors.white),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: NeonColors.cyan,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: NeonTextStyles.body.copyWith(color: Colors.white),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }
}
