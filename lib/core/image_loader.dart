import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Loads and caches decoded [ui.Image]s for every art asset used by the
/// custom-painted game canvas. Widgets like [Image.asset] already do their
/// own caching, but the gameplay canvas is drawn with raw [Canvas] calls
/// via a [CustomPainter], so we need direct access to decoded [ui.Image]
/// objects instead.
class ImageLoader {
  ImageLoader._();

  static final ImageLoader instance = ImageLoader._();

  final Map<String, ui.Image> _cache = {};

  /// Sprite sheets ship at 768x1376. The largest cell any draw call needs is
  /// the central core on a 13" iPad, which lands just under 460 device
  /// pixels tall -- so decoding sheets at 512 wide never upscales anything
  /// while cutting the resident cost per sheet from ~4MB to ~1.9MB.
  /// [SpriteGrid] slices cells by fraction, so the drawing code never has to
  /// know the decode size.
  static const int _decodeWidth = 512;

  ui.Image? get(String assetPath) => _cache[assetPath];

  bool isLoaded(String assetPath) => _cache.containsKey(assetPath);

  Future<ui.Image> load(String assetPath, {int? targetWidth}) async {
    final cached = _cache[assetPath];
    if (cached != null) return cached;
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    _cache[assetPath] = frame.image;
    return frame.image;
  }

  /// Preloads a batch of assets, invoking [onProgress] with a 0..1 value
  /// after each finishes. Used by the splash screen's progress bar.
  ///
  /// A single failing asset never aborts the batch: the game simply skips
  /// drawing whatever could not be decoded.
  Future<void> preloadAll(
    List<String> assetPaths, {
    void Function(double progress)? onProgress,
  }) async {
    if (assetPaths.isEmpty) {
      onProgress?.call(1);
      return;
    }
    int done = 0;
    for (final path in assetPaths) {
      try {
        await load(path, targetWidth: _decodeWidth);
      } catch (_) {
        // Keep going -- a missing sprite must not block the whole launch.
      }
      done++;
      onProgress?.call(done / assetPaths.length);
    }
  }
}
