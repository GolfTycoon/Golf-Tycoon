#!/usr/bin/env python3
"""
Pack individual sprite PNGs into atlas sheets for efficiency.

Produces:
  assets/sprite_sheets/buildings.png + .json
  assets/sprite_sheets/decorations.png + .json
  assets/sprite_sheets/trees.png + .json
  assets/sprite_sheets/golfer.png + .json (placeholder for golfer frames)
  assets/sprite_sheets/ui_icons.png + .json

Each JSON is { "meta": { "image": "buildings.png", "size": {w,h}, "scale": "1" }, "frames": { id: { "frame": [x,y,w,h] } } }

Simple row-packing: place images left-to-right, new row when row would exceed MAX_WIDTH.
"""
import os, json, sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow not installed, cannot pack")
    sys.exit(1)

ROOT = Path(__file__).parent.parent
ASSETS = ROOT / "assets"
OUT_DIR = ROOT / "assets" / "sprite_sheets"
OUT_DIR.mkdir(parents=True, exist_ok=True)

MAX_WIDTH = 2048
PADDING = 2

def pack_group(name, sources, atlas_size=None):
    """
    sources: list of (id, image_path)
    Returns { frames: {id: {frame:[x,y,w,h]}}, atlas_image }
    """
    # Load images
    images = []
    for sid, p in sources:
        if not os.path.exists(p):
            print(f"  skip missing {p}")
            continue
        im = Image.open(p).convert("RGBA")
        images.append((sid, im, p))

    if not images:
        print(f"[{name}] no images found, skipping")
        return

    # Simple shelf packing
    # Sort by height descending for better packing
    images_sorted = sorted(images, key=lambda x: x[1].height, reverse=True)

    atlas_w = MAX_WIDTH
    # Estimate height: sum area
    total_area = sum(im.width * im.height for _, im, _ in images_sorted)
    est_h = int((total_area / atlas_w) * 1.3) + 100
    # We'll dynamically grow height as needed, start with est
    # Use shelf algorithm: x,y cursor
    placements = []  # (sid, x, y, w, h)
    x = PADDING
    y = PADDING
    row_h = 0
    max_y = y

    for sid, im, _ in images_sorted:
        w, h = im.size
        if x + w + PADDING > atlas_w:
            # new row
            y += row_h + PADDING
            x = PADDING
            row_h = 0
        placements.append((sid, x, y, w, h))
        x += w + PADDING
        row_h = max(row_h, h)
        max_y = max(max_y, y + h + PADDING)

    atlas_h = max_y
    # Round up to next pow2 for efficiency (optional)
    # atlas_h = 1 << (atlas_h-1).bit_length()  # pow2
    # Use est if needed
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0,0,0,0))
    frames = {}
    for (sid, x, y, w, h), (orig_sid, im, _) in zip(placements, images_sorted):
        atlas.paste(im, (x, y))
        frames[orig_sid] = {"frame": [x, y, w, h], "sourceSize": [w, h], "spriteSourceSize": [0,0,w,h]}

    # Save
    out_png = OUT_DIR / f"{name}.png"
    out_json = OUT_DIR / f"{name}.json"
    atlas.save(out_png)
    data = {
        "meta": {
            "image": f"res://assets/sprite_sheets/{name}.png",
            "size": {"w": atlas_w, "h": atlas_h},
            "scale": "1",
            "app": "GolfTycoon pack_sprites.py",
            "version": "1.0"
        },
        "frames": frames
    }
    with open(out_json, "w") as f:
        json.dump(data, f, indent="\t")
    print(f"[{name}] packed {len(frames)} sprites into {atlas_w}x{atlas_h} -> {out_png.name}")
    return data

# Collect building sprites
def collect_buildings():
    bdir = ASSETS / "sprites" / "buildings"
    sources = []
    for png in sorted(bdir.glob("*.png")):
        sid = png.stem  # e.g. airstrip_1_e
        sources.append((sid, str(png)))
        # Also alias as building:facing form for code: "building:clubhouse:1:e"
        # We keep the raw stem as id; BuildingSprites will map to it
    return sources

def collect_decorations():
    ddir = ASSETS / "sprites" / "decorations"
    sources = []
    for png in sorted(ddir.glob("*.png")):
        sid = png.stem
        sources.append((sid, str(png)))
    return sources

def collect_trees():
    tdir = ASSETS / "sprites" / "trees"
    sources = []
    for png in sorted(tdir.glob("*.png")):
        if png.is_file():
            sources.append((png.stem, str(png)))
    for sub in ["spring","fall","winter"]:
        sdir = tdir / sub
        if sdir.exists():
            for png in sorted(sdir.glob("*.png")):
                # prefix with season to avoid duplicate stems
                sid = f"{sub}/{png.stem}"
                # Use path relative to trees dir as id, e.g. "spring/oak"
                alt_id = f"{sub}_{png.stem}"
                sources.append((alt_id, str(png)))
    return sources

def collect_golfer():
    # Golfer frames: assets/sprites/golfer/{beginner,casual}/animations/{idle,swing,walk}/{dir}/frame_*.png
    gdir = ASSETS / "sprites" / "golfer"
    sources = []
    if not gdir.exists():
        return sources
    for png in sorted(gdir.rglob("*.png")):
        # create id like "beginner_idle_south_frame_000"
        rel = png.relative_to(gdir)
        # e.g. beginner/animations/idle/south/frame_000.png -> "beginner_idle_south_frame_000"
        parts = rel.parts
        # parts: skin, animations, anim, dir, file
        if len(parts) >= 5:
            skin = parts[0]
            anim = parts[2]
            direction = parts[3]
            frame = png.stem
            sid = f"{skin}_{anim}_{direction}_{frame}"
            sources.append((sid, str(png)))
        else:
            sources.append((png.stem, str(png)))
    return sources

def collect_flag():
    fdir = ASSETS / "sprites" / "flag"
    sources = []
    if fdir.exists():
        for png in sorted(fdir.glob("*.png")):
            sources.append((png.stem, str(png)))
    return sources

# Run
print("Packing sprite sheets...")
pack_group("buildings", collect_buildings())
pack_group("decorations", collect_decorations())
pack_group("trees", collect_trees())

# Golfer is many small frames, pack them (could be large, limit to 2048 width, ~ 40x40 each -> 200 frames fit)
golfer_srcs = collect_golfer()
# Sample first 100 if too many to keep atlas manageable
if len(golfer_srcs) > 256:
    print(f"[golfer] {len(golfer_srcs)} frames, packing first 256 for atlas demo")
    golfer_srcs = golfer_srcs[:256]
if golfer_srcs:
    pack_group("golfer", golfer_srcs)

# UI icons: reuse flag + maybe generate pixel icons on fly? For now pack flag
flag_srcs = collect_flag()
if flag_srcs:
    pack_group("ui_icons", flag_srcs + collect_decorations()[:2])

# Generate a manifest for the packer
print("Done packing.")
print(f"Output in {OUT_DIR}")
# List results
for jf in sorted(OUT_DIR.glob("*.json")):
    d = json.loads(jf.read_text())
    print(f"  {jf.name}: {len(d['frames'])} frames, {d['meta']['size']}")
