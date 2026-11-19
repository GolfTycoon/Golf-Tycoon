#!/usr/bin/env python3
"""Bake numbered tee signs with the building/terrain 3D renderer.

python3 tools/tee_art/generate.py [--check]
Requires tools/building_art/requirements.txt. Outputs are committed; no Python
or runtime font rendering is needed in game. One complete sprite per number.
"""
import argparse
import io
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/building_art'))
from render import Model, C, mat, render, project, grid_origin_offset

OUT = ROOT / 'assets/sprites/tee_numbers'
# Model-space reduction, not a runtime texture shrink: re-bake clean edges
# at the same two source pixels per world pixel as the rest of the tee art.
MARKER_SCALE = 0.8
DIGITS = [
    ('111','101','101','101','111'), ('010','110','010','010','111'),
    ('111','001','111','100','111'), ('111','001','111','001','111'),
    ('101','101','111','001','001'), ('111','100','111','001','111'),
    ('111','100','111','101','111'), ('111','001','010','010','010'),
    ('111','101','111','101','111'), ('111','101','111','001','111'),
]


def bake(number):
    model = Model(1, 1)
    brass = mat(C('cfad62'), 'metal', emissive=0.18)
    green = mat(C('123e34'), unlit=True)
    rim_shadow = mat(C('594b30'))
    gold_light = mat(C('e2c884'), unlit=True)
    cream = mat(C('fff0be'), unlit=True)
    # A standalone medallion: no stone base, plinth or supporting stem.
    # Its lower rim touches the ground anchor used by sorting and occlusion.
    def point(u, v, depth=0):
        # A camera-facing plane: horizontal model motion projects horizontally.
        # The round sign stays readable as its ground anchor rotates with the tee.
        return (32 + (u + depth) * MARKER_SCALE,
                16 + (-u * 0.5 + depth * 0.5) * MARKER_SCALE,
                (8.5 + v) * MARKER_SCALE)

    def disk(radius, depth, material):
        group = model.group()
        for i in range(48):
            a, c = math.tau * i / 48, math.tau * (i + 1) / 48
            model.tri(point(0, 0, depth),
                      point(radius * math.cos(a), radius * math.sin(a), depth),
                      point(radius * math.cos(c), radius * math.sin(c), depth),
                      material, group=group)

    # Solid medallion with a softly bevelled brass rim and recessed enamel.
    edge_group = model.group()
    for i in range(48):
        a, c = math.tau * i / 48, math.tau * (i + 1) / 48
        model.quad(point(8.5 * math.cos(a), 8.5 * math.sin(a), -1),
                   point(8.5 * math.cos(c), 8.5 * math.sin(c), -1),
                   point(8.1 * math.cos(c), 8.1 * math.sin(c), 1),
                   point(8.1 * math.cos(a), 8.1 * math.sin(a), 1),
                   brass, group=edge_group)
    disk(8.1, 1, rim_shadow)
    disk(7.7, 1.08, brass)
    disk(6.9, 1.15, green)

    def ornament(points, material=gold_light):
        model.quad(*(point(u, v, 1.3) for u, v in points), material,
                   group=model.group())

    # A tiny compass-diamond crest and two restrained laurel leaves. These
    # embellishments occupy the spare poles, keeping the number's field clear.
    ornament([(0, 6.3), (0.8, 5.5), (0, 4.7), (-0.8, 5.5)])
    ornament([(-3.8, -4.3), (-1.8, -5.4), (-0.5, -5.4), (-2.5, -4.3)])
    ornament([(3.8, -4.3), (1.8, -5.4), (0.5, -5.4), (2.5, -4.3)])
    text = str(number)
    unit = 1.4
    start = -(len(text) * 4 - 1) * unit / 2
    # Raised cream glyphs are part of the single baked sprite, not UI text.
    glyph_group = model.group()
    for i, digit in enumerate(text):
        for row, pixels in enumerate(DIGITS[int(digit)]):
            for col, bit in enumerate(pixels):
                if bit == '1':
                    u = start + (i * 4 + col) * unit
                    v = 3.5 - row * unit
                    model.quad(point(u, v, 1.3), point(u+unit, v, 1.3),
                               point(u+unit, v-unit, 1.3), point(u, v-unit, 1.3), cream, group=glyph_group)
    image, rect = render(model, 0, scale=2.0, pad=(4,4,4,4))
    origin = grid_origin_offset(1, 1, 0)
    foot = project(32, 16, 0, 0)
    anchor = [(origin[i] + foot[i] - rect[i]) / rect[i+2] for i in range(2)]
    return image, anchor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    layout = {'scale': 0.5, 'sprites': {}}
    stale = []
    # Includes extended courses; never clamp a displayed number to another hole.
    for number in range(1, 100):
        image, anchor = bake(number)
        name = f'{number}.png'
        data = io.BytesIO()
        image.save(data, format='PNG')
        path = OUT / name
        layout['sprites'][name] = anchor
        if args.check:
            if not path.exists() or path.read_bytes() != data.getvalue():
                stale.append(name)
        else:
            path.write_bytes(data.getvalue())
    path = OUT / 'layout.json'
    data = json.dumps(layout, indent=2, sort_keys=True) + '\n'
    if args.check:
        if not path.exists() or path.read_text() != data:
            stale.append(path.name)
    else:
        path.write_text(data)
    if stale:
        sys.exit('Stale tee art: ' + ', '.join(stale))
    print('All 99 tee number sprites ' + ('verified.' if args.check else 'generated.'))


if __name__ == '__main__':
    main()
