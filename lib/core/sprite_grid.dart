import 'dart:ui' as ui;

/// How a sprite-sheet asset is divided into cells.
class SpriteGrid {
  const SpriteGrid(this.columns, this.rows);

  final int columns;
  final int rows;

  /// The nominal cell at [column]/[row] (both zero-based) as a fraction of
  /// the sheet. This is only the cell the sprite was *authored* into; the
  /// artwork inside it is neither centred nor cell-sized, which is what
  /// `kSpriteFrames` corrects.
  ui.Rect cellFraction(int column, int row) => ui.Rect.fromLTWH(
        column / columns,
        row / rows,
        1 / columns,
        1 / rows,
      );
}

/// Grid shapes used across the Neon Plume Drop art pack.
class SpriteGrids {
  SpriteGrids._();

  static const SpriteGrid grid2x2 = SpriteGrid(2, 2);
  static const SpriteGrid stripVertical4 = SpriteGrid(1, 4);
  static const SpriteGrid single = SpriteGrid(1, 1);
}
