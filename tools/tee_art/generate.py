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
from buildings import Builder

OUT = ROOT / 'assets/sprites/tee_numbers'
DIGITS = [
    ('111','101','101','101','111'), ('010','110','010','010','111'),
    ('111','001','111','100','111'), ('111','001','111','001','111'),
    ('101','101','111','001','001'), ('111','100','111','001','111'),
    ('111','100','111','101','111'), ('111','001','010','010','010'),
    ('111','101','111','101','111'), ('111','101','111','001','111'),
]


def bake(number):
    model = Model(1, 1)
    b = Builder(model)
    brass = mat(C('cfad62'), 'metal')
    green = mat(C('173e32'))
    stone = mat(C('777b70'), 'gravel')
    cream = mat(C('fff0be'), unlit=True)
    # Circular footing and a slim round stem avoid the old boxy silhouette.
    b.cylinder(32, 16, 0, 2, 6, stone, segments=32)
    b.cylinder(32, 16, 2, 7, 1.6, brass, segments=16)

    def point(u, v, depth=0):
        # A camera-facing plane: horizontal model motion projects horizontally.
        # The round sign stays readable as its ground anchor rotates with the tee.
        return (32 + u + depth, 16 - u * 0.5 + depth * 0.5, 16 + v)

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
        model.quad(point(11 * math.cos(a), 11 * math.sin(a), -1),
                   point(11 * math.cos(c), 11 * math.sin(c), -1),
                   point(10.5 * math.cos(c), 10.5 * math.sin(c), 1),
                   point(10.5 * math.cos(a), 10.5 * math.sin(a), 1),
                   brass, group=edge_group)
    disk(10.5, 1, brass)
    disk(8.8, 1.15, green)
    text = str(number)
    unit = 1.8
    start = -(len(text) * 4 - 1) * unit / 2
    # Raised cream glyphs are part of the single baked sprite, not UI text.
    glyph_group = model.group()
    for i, digit in enumerate(text):
        for row, pixels in enumerate(DIGITS[int(digit)]):
            for col, bit in enumerate(pixels):
                if bit == '1':
                    u = start + (i * 4 + col) * unit
                    v = 4.5 - row * unit
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
