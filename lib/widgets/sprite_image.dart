import 'package:flutter/material.dart';

import '../models/catalog.dart';

/// Renders one sprite out of a sheet asset as an ordinary widget, cropped to
/// the artwork's real bounds ([SpriteRef.frame]) so it fills the space it is
/// given and sits dead centre.
///
/// Menus use this; the gameplay screen crops the same frames straight onto a
/// [Canvas] instead. Both read [SpriteRef], so a sprite looks identical in a
/// picker and in play.
class SpriteImage extends StatelessWidget {
  const SpriteImage({super.key, required this.ref, this.cacheWidth});

  final SpriteRef ref;

  /// Decode width for the *whole sheet*, so a cropped sprite ends up with
  /// roughly `cacheWidth * frame.width` pixels across. Left null the full
  /// sheet is decoded, which is wasteful for small icons.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final frame = ref.frame;
    return Center(
      child: AspectRatio(
        aspectRatio: ref.aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Scale the sheet up so that the frame alone covers the box, then
            // slide the frame's top-left corner to the box's origin.
            final sheetWidth = constraints.maxWidth / frame.width;
            final sheetHeight = constraints.maxHeight / frame.height;
            return ClipRect(
              child: OverflowBox(
                maxWidth: sheetWidth,
                maxHeight: sheetHeight,
                alignment: Alignment.topLeft,
                child: Transform.translate(
                  offset: Offset(
                    -frame.left * sheetWidth,
                    -frame.top * sheetHeight,
                  ),
                  child: SizedBox(
                    width: sheetWidth,
                    height: sheetHeight,
                    child: Image.asset(
                      ref.asset,
                      fit: BoxFit.fill,
                      cacheWidth: cacheWidth,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
