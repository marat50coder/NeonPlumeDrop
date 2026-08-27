#!/usr/bin/env python3
"""Regenerates lib/core/sprite_frames.dart.

Each sprite sits on a shared canvas with uneven transparent padding, and many
sheets let glow / spikes overflow the nominal cell. This script:

  1. Labels 8-connected alpha blobs.
  2. Assigns every blob to the cell whose centre is nearest the blob centroid
     (so a drone that starts 20px into the cell above still belongs to itself).
  3. Drops stray particles that belong to a neighbour.
  4. Takes the tight union bbox per cell and pads it so the neon falloff is
     not clipped. Squares and uniform sizes are computed in *pixels*, not
     UV space — otherwise a "square" on a tall sheet becomes a huge
     rectangle that swallows the next sprite.

Usage:  python3 tool/trim_sprites.py [--preview DIR]
Requires: pillow, numpy
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

PLAY = 'assets/Neon_Plume_Drop_gameplay_assets'
OUT = 'lib/core/sprite_frames.dart'
ALPHA_THRESHOLD = 3
PAD_PX = 28
# Keep a transparent gutter so neighbouring glows never sit in the same crop.
GUTTER_PX = 8
MIN_BLOB_AREA = 80
# How far PAD/square may grow past the nominal cell. Actual artwork is never
# clipped to this — only extra padding is.
CELL_OVERFLOW = 0.14

# Drones sit in a tight vertical strip and legitimately overflow cells.
OVERFLOW_BY_SHEET = {
    'Energy_Drones_Set_asset.webp': 0.28,
    'Central_Energy_Cores_Set_asset.webp': 0.05,
    'Energy_Balls_Set_1_asset.webp': 0.08,
    'Energy_Balls_Set_2_asset.webp': 0.08,
    'Void_Zones_Set_asset.webp': 0.08,
}

# sheet file name -> (columns, rows)
SHEETS = {
    'Central_Energy_Cores_Set_asset.webp': (2, 2),
    'Energy_Balls_Set_1_asset.webp': (2, 2),
    'Energy_Balls_Set_2_asset.webp': (2, 2),
    'Energy_Obstacles_Set_1_asset.webp': (2, 2),
    'Energy_Obstacles_Set_2_asset.webp': (2, 2),
    'Energy_Drones_Set_asset.webp': (1, 4),
    'Void_Zones_Set_asset.webp': (2, 2),
    'Energy_Gates_Set_asset.webp': (2, 2),
    'Energy_Crystals_Set_1_asset.webp': (2, 2),
    'Energy_Crystals_Set_2_asset.webp': (2, 2),
    'Floating_Crystals_Set_asset.webp': (2, 2),
    'Prism_Gates_Set_asset.webp': (2, 2),
    'Colored_Energy_Routes_Set_asset.webp': (2, 2),
    'Holographic_Structures_Set_asset.webp': (2, 2),
    'Energy_Rings_Set_2_asset.webp': (2, 2),
    'Energy_Rings_Set_3_asset.webp': (2, 1),
    'Orbital_Segments_Set_1_asset.webp': (2, 2),
    'Crystal_Shard_asset.webp': (1, 1),
    'Shield_Core_asset.webp': (1, 1),
    'Rare_Prism_Core_asset.webp': (1, 1),
    'Neon_Energy_Orb_asset.webp': (1, 1),
    'Energy_Charge_Capsule_asset.webp': (1, 1),
    'Cosmic_Sector_Portal_asset.webp': (1, 1),
}

# Only sprites that must render at one shared size (skin picker). Never
# force this on mixed-shape sheets — a laser pylon and a hex mine sharing a
# box is exactly what made obstacles look cropped / floating in empty space.
UNIFORM_GROUPS = [
    ['Energy_Balls_Set_1_asset.webp', 'Energy_Balls_Set_2_asset.webp'],
    ['Energy_Gates_Set_asset.webp'],
    ['Energy_Crystals_Set_1_asset.webp', 'Energy_Crystals_Set_2_asset.webp'],
    ['Energy_Rings_Set_2_asset.webp'],
]

# Round-ish sprites are framed in a pixel-square about their centre so they
# don't sit off-centre inside a rectangular crop.
SQUARE_SHEETS = {
    'Energy_Balls_Set_1_asset.webp',
    'Energy_Balls_Set_2_asset.webp',
    'Central_Energy_Cores_Set_asset.webp',
    'Energy_Drones_Set_asset.webp',
    'Energy_Rings_Set_2_asset.webp',
    'Energy_Rings_Set_3_asset.webp',
    'Shield_Core_asset.webp',
    'Rare_Prism_Core_asset.webp',
    'Neon_Energy_Orb_asset.webp',
    'Cosmic_Sector_Portal_asset.webp',
}


def label_components(binary: np.ndarray) -> np.ndarray:
    """Two-pass 8-connected labels. 0 is background."""
    h, w = binary.shape
    labels = np.zeros((h, w), dtype=np.int32)
    parent = [0]

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    next_label = 1
    for y in range(h):
        row = binary[y]
        prev = labels[y - 1] if y else None
        for x in range(w):
            if not row[x]:
                continue
            neighbors = []
            if x and labels[y, x - 1]:
                neighbors.append(labels[y, x - 1])
            if prev is not None:
                if labels[y - 1, x]:
                    neighbors.append(labels[y - 1, x])
                if x and labels[y - 1, x - 1]:
                    neighbors.append(labels[y - 1, x - 1])
                if x + 1 < w and labels[y - 1, x + 1]:
                    neighbors.append(labels[y - 1, x + 1])
            if not neighbors:
                parent.append(next_label)
                labels[y, x] = next_label
                next_label += 1
            else:
                m = neighbors[0]
                labels[y, x] = m
                for n in neighbors[1:]:
                    union(m, n)

    remap = np.zeros(len(parent), dtype=np.int32)
    running = 0
    for i in range(1, len(parent)):
        root = find(i)
        if remap[root] == 0:
            running += 1
            remap[root] = running
        remap[i] = remap[root]
    return remap[labels]


def blob_stats(labels: np.ndarray):
    """Yield (label, area, x0, y0, x1, y1, cx, cy) for every non-zero label."""
    max_lab = int(labels.max())
    if max_lab == 0:
        return []
    out = []
    for lab in range(1, max_lab + 1):
        ys, xs = np.nonzero(labels == lab)
        if xs.size == 0:
            continue
        area = int(xs.size)
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        cx = float(xs.mean())
        cy = float(ys.mean())
        out.append((lab, area, x0, y0, x1, y1, cx, cy))
    return out


def _union_bbox(group):
    return (
        min(b[2] for b in group),
        min(b[3] for b in group),
        max(b[4] for b in group),
        max(b[5] for b in group),
    )


def _keep_satellites(group, cell_w, cell_h):
    """Drop particles that clearly belong to a neighbouring sprite."""
    if len(group) <= 1:
        return group
    dominant = max(group, key=lambda b: b[1])
    max_dist = math.hypot(cell_w, cell_h) * 0.40
    dx0, dy0, dx1, dy1 = dominant[2:6]
    pad = 56
    keep = []
    for blob in group:
        dist = math.hypot(blob[6] - dominant[6], blob[7] - dominant[7])
        overlaps = not (
            blob[4] < dx0 - pad
            or blob[2] > dx1 + pad
            or blob[5] < dy0 - pad
            or blob[3] > dy1 + pad
        )
        if blob is dominant or dist <= max_dist or overlaps:
            keep.append(blob)
    return keep


def _clip_keep_tight(padded, tight, lim):
    """Apply `lim` to padding only — never throw away the sprite's own pixels."""
    x0 = min(tight[0], max(padded[0], lim[0]))
    y0 = min(tight[1], max(padded[1], lim[1]))
    x1 = max(tight[2], min(padded[2], lim[2]))
    y1 = max(tight[3], min(padded[3], lim[3]))
    return x0, y0, x1, y1


def _gutter_box(box, pad=GUTTER_PX):
    return (box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad)


def _overlap(a, b):
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def _separate_from(box, other, floor):
    """Inset `box` so it no longer overlaps `other`, without going inside `floor`."""
    if not _overlap(box, other):
        return box
    x0, y0, x1, y1 = box
    ox0, oy0, ox1, oy1 = other
    cuts = []
    if x1 > ox0 and x0 < ox0:
        cuts.append((x1 - ox0, 'r'))
    if x0 < ox1 and x1 > ox1:
        cuts.append((ox1 - x0, 'l'))
    if y1 > oy0 and y0 < oy0:
        cuts.append((y1 - oy0, 'b'))
    if y0 < oy1 and y1 > oy1:
        cuts.append((oy1 - y0, 't'))
    if not cuts:
        return box
    amount, edge = min(cuts, key=lambda c: c[0])
    if edge == 'r':
        x1 = max(floor[2], x1 - amount)
    elif edge == 'l':
        x0 = min(floor[0], x0 + amount)
    elif edge == 'b':
        y1 = max(floor[3], y1 - amount)
    else:
        y0 = min(floor[1], y0 + amount)
    return x0, y0, x1, y1


def cell_boxes(path: str, cols: int, rows: int, overflow: float):
    image = Image.open(path).convert('RGBA')
    width, height = image.size
    alpha = np.array(image.split()[3])
    binary = alpha > ALPHA_THRESHOLD
    labels = label_components(binary)
    blobs = blob_stats(labels)

    cell_w = width / cols
    cell_h = height / rows
    centres = [
        ((c + 0.5) * cell_w, (r + 0.5) * cell_h)
        for r in range(rows)
        for c in range(cols)
    ]

    large = [b for b in blobs if b[1] >= MIN_BLOB_AREA]
    small = [b for b in blobs if b[1] < MIN_BLOB_AREA]

    assigned = [[] for _ in centres]

    def nearest_cell(cx, cy):
        best_i, best_d = 0, 1e18
        for i, (tx, ty) in enumerate(centres):
            d = (cx - tx) ** 2 + (cy - ty) ** 2
            if d < best_d:
                best_i, best_d = i, d
        return best_i

    for blob in large:
        assigned[nearest_cell(blob[6], blob[7])].append(blob)
    for blob in small:
        assigned[nearest_cell(blob[6], blob[7])].append(blob)

    tight_boxes = []
    for i, group in enumerate(assigned):
        col, row = i % cols, i // cols
        group = _keep_satellites(group, cell_w, cell_h)
        if not group:
            side = min(cell_w, cell_h) * 0.4
            cx, cy = centres[i]
            tight_boxes.append((
                cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2,
            ))
            continue
        tight_boxes.append(_union_bbox(group))

    pixel_boxes = []
    for i, tight in enumerate(tight_boxes):
        col, row = i % cols, i // cols
        padded = (
            max(0, tight[0] - PAD_PX),
            max(0, tight[1] - PAD_PX),
            min(width, tight[2] + PAD_PX),
            min(height, tight[3] + PAD_PX),
        )
        lim = (
            max(0, (col - overflow) * cell_w),
            max(0, (row - overflow) * cell_h),
            min(width, (col + 1 + overflow) * cell_w),
            min(height, (row + 1 + overflow) * cell_h),
        )
        box = _clip_keep_tight(padded, tight, lim)
        for j, other in enumerate(tight_boxes):
            if i == j:
                continue
            box = _separate_from(box, _gutter_box(other), tight)
        pixel_boxes.append(tuple(int(round(v)) for v in box))

    frac_boxes = [
        (x0 / width, y0 / height, x1 / width, y1 / height)
        for (x0, y0, x1, y1) in pixel_boxes
    ]
    return frac_boxes, pixel_boxes, (width, height), len(large), image, tight_boxes


def _px(box, size):
    sw, sh = size
    l, t, r, b = box
    return [l * sw, t * sh, r * sw, b * sh]


def _frac(px, size):
    sw, sh = size
    x0, y0, x1, y1 = px
    return (x0 / sw, y0 / sh, x1 / sw, y1 / sh)


def recentre_px(box, size_px, sheet):
    """Grow `box` (fractions) to `size_px` about its centre, clamped to the sheet."""
    sw, sh = sheet
    pw, ph = size_px
    pw = min(pw, sw)
    ph = min(ph, sh)
    x0, y0, x1, y1 = _px(box, sheet)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    cx = min(max(cx, pw / 2), sw - pw / 2)
    cy = min(max(cy, ph / 2), sh - ph / 2)
    return _frac((cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2), sheet)


def make_square_px(box, sheet):
    x0, y0, x1, y1 = _px(box, sheet)
    side = max(x1 - x0, y1 - y0)
    return recentre_px(box, (side, side), sheet)


def sync_pixels(frac_boxes, sheet):
    sw, sh = sheet
    return [
        tuple(int(round(v)) for v in (l * sw, t * sh, r * sw, b * sh))
        for (l, t, r, b) in frac_boxes
    ]


def split_thin_overlaps(pixel_boxes, max_span=16):
    """If two crops share a thin strip, split it at the midpoint.

    Neighbour glows can otherwise sit in both frames; a 4–12px split is
    invisible, while leaving the strip makes a sprite look double-exposed.
    """
    boxes = [list(b) for b in pixel_boxes]
    n = len(boxes)
    for i in range(n):
        for j in range(i + 1, n):
            a, b = boxes[i], boxes[j]
            ox0, oy0 = max(a[0], b[0]), max(a[1], b[1])
            ox1, oy1 = min(a[2], b[2]), min(a[3], b[3])
            if ox0 >= ox1 or oy0 >= oy1:
                continue
            ow, oh = ox1 - ox0, oy1 - oy0
            if ow <= oh and ow <= max_span:
                mid = (ox0 + ox1) / 2
                if (a[0] + a[2]) / 2 <= (b[0] + b[2]) / 2:
                    a[2] = min(a[2], mid)
                    b[0] = max(b[0], mid)
                else:
                    b[2] = min(b[2], mid)
                    a[0] = max(a[0], mid)
            elif oh <= max_span:
                mid = (oy0 + oy1) / 2
                if (a[1] + a[3]) / 2 <= (b[1] + b[3]) / 2:
                    a[3] = min(a[3], mid)
                    b[1] = max(b[1], mid)
                else:
                    b[3] = min(b[3], mid)
                    a[1] = max(a[1], mid)
    return [tuple(int(round(v)) for v in box) for box in boxes]


def write_preview(preview_dir, name, image, pixel_boxes, cols, rows):
    os.makedirs(preview_dir, exist_ok=True)
    overlay = image.copy()
    draw = ImageDraw.Draw(overlay)
    stem = name.replace('.webp', '')
    gray = (36, 36, 42, 255)
    for i, (x0, y0, x1, y1) in enumerate(pixel_boxes):
        draw.rectangle(
            [x0, y0, max(x0, x1 - 1), max(y0, y1 - 1)],
            outline=(0, 255, 90, 255),
            width=3,
        )
        crop = image.crop((x0, y0, x1, y1))
        # Grey backing makes leftover transparent padding obvious.
        backing = Image.new('RGBA', crop.size, gray)
        backing.paste(crop, mask=crop.split()[3])
        backing.save(os.path.join(preview_dir, f'{stem}_{i}.png'))
    overlay.thumbnail((520, 940), Image.Resampling.LANCZOS)
    overlay.save(os.path.join(preview_dir, f'{stem}_OVERLAY.png'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--preview', default='')
    args = parser.parse_args()

    uniform_of = {}
    for group in UNIFORM_GROUPS:
        for name in group:
            uniform_of[name] = group

    measured = {}
    pixels = {}
    sizes = {}
    images = {}
    tight = {}
    n_larges = {}
    for name, (cols, rows) in SHEETS.items():
        path = os.path.join(PLAY, name)
        overflow = OVERFLOW_BY_SHEET.get(name, CELL_OVERFLOW)
        frac, pix, size, n_large, image, tight_px = cell_boxes(
            path, cols, rows, overflow,
        )
        measured[name] = frac
        pixels[name] = pix
        sizes[name] = size
        images[name] = image
        tight[name] = tight_px
        n_larges[name] = n_large

    for name in SQUARE_SHEETS:
        if name not in measured:
            continue
        sheet = sizes[name]
        measured[name] = [make_square_px(box, sheet) for box in measured[name]]
        # Squaring must not swallow a neighbour's artwork.
        tights = tight[name]
        squared = []
        for i, box in enumerate(measured[name]):
            px = _px(box, sheet)
            floor = tights[i]
            for j, other in enumerate(tights):
                if i == j:
                    continue
                px = _separate_from(px, _gutter_box(other), floor)
            squared.append(_frac(px, sheet))
        measured[name] = squared
        pixels[name] = sync_pixels(measured[name], sheet)

    for name, (cols, rows) in SHEETS.items():
        group = uniform_of.get(name)
        if not group:
            continue
        # Common size in pixels. Sheets in a group share dimensions.
        sheet = sizes[name]
        pooled_px = []
        for member in group:
            sw, sh = sizes[member]
            for box in measured[member]:
                x0, y0, x1, y1 = _px(box, (sw, sh))
                pooled_px.append((x1 - x0, y1 - y0))
        pw = max(w for w, h in pooled_px)
        ph = max(h for w, h in pooled_px)
        if name in SQUARE_SHEETS:
            side = max(pw, ph)
            pw = ph = side
        measured[name] = [
            recentre_px(box, (pw, ph), sheet) for box in measured[name]
        ]
        tights = tight[name]
        uniformed = []
        for i, box in enumerate(measured[name]):
            px = _px(box, sheet)
            floor = tights[i]
            for j, other in enumerate(tights):
                if i == j:
                    continue
                px = _separate_from(px, _gutter_box(other), floor)
            uniformed.append(_frac(px, sheet))
        measured[name] = uniformed
        pixels[name] = sync_pixels(measured[name], sheet)

    for name, sheet in sizes.items():
        pixels[name] = split_thin_overlaps(pixels[name])
        measured[name] = [
            (x0 / sheet[0], y0 / sheet[1], x1 / sheet[0], y1 / sheet[1])
            for (x0, y0, x1, y1) in pixels[name]
        ]

    for name, (cols, rows) in SHEETS.items():
        size = sizes[name]
        n_large = n_larges[name]
        expected = cols * rows
        flag = '' if n_large >= expected else f'  !! only {n_large} large blobs'
        print(f'{name:48} {size[0]}x{size[1]}  cells={expected}  blobs={n_large}{flag}')
        for i, (x0, y0, x1, y1) in enumerate(pixels[name]):
            print(f'    [{i}] {x1 - x0:4}x{y1 - y0:<4}  @({x0},{y0})')

    if args.preview:
        for name, (cols, rows) in SHEETS.items():
            write_preview(args.preview, name, images[name], pixels[name], cols, rows)
        print(f'previews -> {args.preview}')

    lines = [
        '// GENERATED FILE -- do not edit by hand.',
        '// Regenerate with: python3 tool/trim_sprites.py',
        '',
        "import 'dart:ui' show Rect, Size;",
        '',
        'const double kSheetWidth = 768;',
        'const double kSheetHeight = 1376;',
        '',
        'const Map<String, Size> kSheetSizes = {',
    ]
    for name, (w, h) in sizes.items():
        lines.append(f"  '{PLAY}/{name}': Size({w:.0f}, {h:.0f}),")
    lines.append('};')
    lines.append('')
    lines.append('/// Tight padded alpha box of every sprite, as a fraction of')
    lines.append('/// the sheet. Keyed by asset path; indexed by')
    lines.append('/// `row * columns + column`.')
    lines.append('const Map<String, List<Rect>> kSpriteFrames = {')

    for name, (cols, rows) in SHEETS.items():
        boxes = measured[name]
        lines.append(f"  '{PLAY}/{name}': [")
        for index, (l, t, r, b) in enumerate(boxes):
            col, row = index % cols, index // cols
            lines.append(
                '    Rect.fromLTRB('
                f'{l:.5f}, {t:.5f}, {r:.5f}, {b:.5f}), '
                f'// c{col} r{row}'
            )
        lines.append('  ],')
    lines.append('};')
    lines.append('')

    with open(OUT, 'w') as handle:
        handle.write('\n'.join(lines))
    print(f'wrote {OUT} ({len(SHEETS)} sheets)')


if __name__ == '__main__':
    sys.exit(main())
