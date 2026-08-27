import 'package:audioplayers/audioplayers.dart';

import 'game_assets.dart';
import 'profile_service.dart';

/// Thin wrapper around `audioplayers` exposing a small round-robin pool of
/// players so overlapping sound effects never cut each other off.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  /// Allocated on first use rather than with the singleton: constructing an
  /// [AudioPlayer] talks to the platform, so an eager pool both costs six
  /// native players on a muted device and throws anywhere the channel is
  /// absent.
  List<AudioPlayer>? _sfxPool;
  int _sfxCursor = 0;
  bool _unavailable = false;

  Future<void> init() async {
    _ensurePool();
  }

  List<AudioPlayer>? _ensurePool() {
    if (_unavailable) return null;
    final existing = _sfxPool;
    if (existing != null) return existing;
    try {
      final pool =
          List.generate(6, (i) => AudioPlayer(playerId: 'npd_sfx_$i'));
      for (final p in pool) {
        p.setReleaseMode(ReleaseMode.stop);
      }
      _sfxPool = pool;
      return pool;
    } catch (_) {
      // Audio is a non-critical enhancement; a hostile audio session must
      // never crash the game, and must not be retried on every tap either.
      _unavailable = true;
      return null;
    }
  }

  Future<void> playSfx(String asset, {double volumeScale = 1.0}) async {
    final volume = (ProfileService.instance.sfxVolume * volumeScale).clamp(0.0, 1.0);
    if (volume <= 0) return;
    final pool = _ensurePool();
    if (pool == null) return;
    try {
      final player = pool[_sfxCursor];
      _sfxCursor = (_sfxCursor + 1) % pool.length;
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(_stripAssetsPrefix(asset)));
    } catch (_) {
      // Ignore playback errors (e.g. rapid-fire triggers on old devices).
    }
  }

  String _stripAssetsPrefix(String path) =>
      path.startsWith('assets/') ? path.substring('assets/'.length) : path;

  // Convenience shortcuts for the most common UI sounds.
  Future<void> click() => playSfx(GameAssets.sfxButtonClick);
  Future<void> back() => playSfx(GameAssets.sfxButtonBack);
  Future<void> menuOpen() => playSfx(GameAssets.sfxMenuOpen);
  Future<void> menuClose() => playSfx(GameAssets.sfxMenuClose);
}
