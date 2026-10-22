# Golf Tycoon — Tree Sprite Sheet Prompt Bible

> **Text-to-Image Prompts for Every Tree Species — Isometric 2:1 Dimetric**
> *Create an amazing 4-view (N / E / S / W) pixel-art sprite sheet where each tree reads as a **volumetric 3D object sitting on its terrain tile**, exactly as seen from the game's camera.*
> Covers the 11 base species in `assets/sprites/trees/` + all seasonal variants in `mods/golf_tycoon.seasons/tree_art/` + **one mega-sheet with every species together**.

---

## How to Read This Guide

- Every tree is **authored once** as the north-facing view (`<species>.png`). The tool `tools/tree_art/generate.py` derives the other three angles automatically — but with AI you can now generate **all four views at once** as a sprite sheet.
- Copy the **Copy-Paste Prompt** for your generator (Stable Diffusion XL, Midjourney v6, Flux, Ideogram, DALL·E 3) — then slice the sheet into `tree_n.png`, `tree_e.png`, `tree_s.png`, `tree_w.png`.
- Keep the **Global Style Fragment** + **Negative Prompt** in every generation. Only the per-tree description changes.

### What went wrong before — and what this fixes

> **Too front-on:** A prompt like *“front view of an oak tree”* makes the AI draw a **side elevation** — eye-level, horizon at mid-trunk, canopy as a flat circle, trunk as a rectangle. In Golf Tycoon you never see trees like that.
>
> **Game's camera is high and oblique:** Golf Tycoon is a **2:1 isometric dimetric** world. Tiles are `64 × 32` diamonds (`TILE_W=64, TILE_H=32`), elevation lifts `10px` per level, projection is `sx = (u−v)×32, sy = (u+v)×16 − z`. The camera sits high above the course (≈ 26.6° elevation — `arctan 0.5`), looking down from the southeast. You see **the top of the canopy plus two sides**, the trunk as a short vertical cylinder standing on the diamond's centre, and the ground as a flattened ellipse (`TreeOverlay` draws it at `scale (1.0, 0.5)`).
>
> **Every prompt here now forces that angle:** *isometric 2:1 dimetric, high-oblique 3/4 top-down, diorama on diamond tile, volumetric 3D tree — not a flat billboard.*

**Preview — single species (4 frames, shared camera elevation, rotated azimuth):**

```
┌──────────┬──────────┬──────────┬──────────┐
│  N view  │  E view  │  S view  │  W view  │  ← one row, equal gaps
│  FRONT   │  RIGHT   │  BACK    │  LEFT    │
│ (lit)    │  +lean R │ (dark)   │ +lean L  │
└──────────┴──────────┴──────────┴──────────┘
          bottom-center trunk anchor + tiny ground shadow in each cell
```

**Preview — mega sheet (all 11 species together, 11 rows × 4 cols):**

```
        N        E        S        W
  ┌────────┬────────┬────────┬────────┐
  │  oak_N │  oak_E │  oak_S │  oak_W │  64×80  ← row 1
  ├────────┼────────┼────────┼────────┤
  │ birch_N│ birch_E│ birch_S│ birch_W│  48×80  ← row 2
  ├────────┼────────┼────────┼────────┤
  │ pine_N │ pine_E │ pine_S │ pine_W │  48×80
  ├────────┼────────┼────────┼────────┤
  │ maple_N│ maple_E│ maple_S│ maple_W│  56×72
  ├────────┼────────┼────────┼────────┤
  │ palm_N │ palm_E │ palm_S │ palm_W │  56×80
  ├────────┼────────┼────────┼────────┤
  │ dead_N │ dead_E │ dead_S │ dead_W │  56×80
  ├────────┼────────┼────────┼────────┤
  │ cactus │ cactus │ cactus │ cactus │  40×64
  ├────────┼────────┼────────┼────────┤
  │  bush  │  bush  │  bush  │  bush  │  40×40
  ├────────┼────────┼────────┼────────┤
  │cattails│cattails│cattails│cattails│  32×48
  ├────────┼────────┼────────┼────────┤
  │ fescue │ fescue │ fescue │ fescue │  32×32
  ├────────┼────────┼────────┼────────┤
  │ heather│ heather│ heather│ heather│  32×32  ← row 11
  └────────┴────────┴────────┴────────┘
          solid chroma-key background → remove to transparent in 10 sec
```

---

## 1. Global Art Direction — INCLUDE IN EVERY PROMPT

Golf Tycoon is a **cozy, clean, 16-bit-era pixel art** tycoon — think *Stardew Valley* × *Theme Park (1994)* × *A Short Hike*, but rendered through a **fixed isometric 2:1 dimetric camera** — the same projection as the buildings in `tools/building_art/render.py`.

### Positive Style Fragment (paste verbatim)

```
pixel art game asset, 16-bit retro cozy golf tycoon style, hand-pixelled,
crisp 1px outline, limited vibrant palette, warm soft lighting from top-right
(sun over +u, 135° southeast), dithered shading, no anti-aliasing blur,
Stardew Valley meets SimGolf, highly detailed at small resolution, game-ready sprite,
ultra-sharp pixels, nearest-neighbor, texture_filter nearest
```

### Camera Fragment — THIS IS THE FIX (paste verbatim — do not omit)

```
ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE VIEW, high camera 26.6 degrees above ground
(arctan 0.5, tile 64x32 diamond), looking down from southeast at golf course terrain tile,
diorama on diamond tile, volumetric 3D tree sitting on terrain tile — NOT a flat side elevation
or eye-level portrait — seeing the TOP of the canopy plus two side faces, trunk is a short
vertical cylinder standing at the centre of the isometric diamond with a small flattened
elliptical ground shadow (50% vertical scale, 20% opacity), canopy is a volume with clear
top texture and dithered side shading, consistent with building art projection sx=(u-v)*32
sy=(u+v)*16 - z, one art pixel equals one world pixel, correctly sitting on the ground plane
```

**What this clause does for the AI:**

| Old (front-on) result | New (isometric) result |
|---|---|
| Eye-level horizon, trunk tall, canopy as flat disc | Camera high, trunk short/vertical, canopy as sphere/oval with visible top |
| No ground, tree floats | Ground diamond implied, ellipse shadow at 1.0×0.5 scale, tree anchored |
| Sides only, no top highlight | Top highlight + two visible faces, volumetric depth, dithered falloff |
| Looks like an icon pasted on screen | Looks like a building — sits *in* the world, occludes correctly |

**Synonyms to add if your generator ignores “isometric”:** also include `3/4 top-down view, diorama, dimetric projection, tilted top view, 45-degree isometric, chibi isometric tree, voxel-style but pixel art`.

### Background Handling — PICK ONE (see §1a below)

Add **either** of these to the end of every prompt, depending on your generator:

**A) Transparent BG (only if your tool supports it):**
```
isolated on transparent background, no background, alpha channel, transparent PNG
```

**B) Solid Chroma-Key BG (recommended for Midjourney / DALL·E / SDXL / Flux):**
```
isolated on solid flat pure chroma-key green background #00FF6A, even flat color,
no gradient, no shadow except tiny flattened ground oval under trunk at 1.0x0.5 scale,
no scenery, no sky, no grass field, no horizon line, studio sprite on solid color
for easy background removal, ground plane is the isometric diamond tile centre only
```

> **Why B is the default:** Midjourney, DALL·E 3, Flux, SDXL, and most Midjourney-style tools **cannot output transparency** — they always fill the background. Don't fight it: ask for a solid, removable color (see §1a) and strip it in one click afterwards. Transparent-native tools (Leonardo `Transparent PNG`, Ideogram `Canvas`, Recraft `Remove BG`) can use variant A.

### Technical Layout Fragment (single species, 4 frames)

```
sprite sheet, single horizontal row of 4 identical trees at SAME high-oblique isometric
elevation (26.6 degrees), only the azimuth rotates quarter-turns around vertical axis:
North view (camera southeast, sees north+east faces) | East view (sees east+south, crown
foreshortened 18% toward trunk, leaned 3px in screen space, lit from right) | South view
(sees south+west, mirrored, slightly darker 0.88x sun away) | West view (sees west+north,
mirrored foreshortened leaned 3px left lit from left) — same volumetric tree, same height,
same top texture, same trunk base at exact bottom-center pixel, perfectly aligned ground
ellipse in every frame, equal spacing, no border, no text, no watermark
```

### Technical Layout Fragment (all 11 species mega-sheet)

```
master sprite sheet contact sheet, grid layout 11 rows × 4 columns, 44 isometric tree sprites
on solid green, SAME 26.6-degree high-oblique dimetric camera for every cell, columns are
N | E | S | W azimuth rotations (same elevation), rows top-to-bottom are: oak, birch, pine,
maple, palm, dead_tree, cactus, bush, cattails, fescue, heather — same volumetric species
in each row with 4 azimuth views, each cell shows TOP of canopy plus two faces, trunk vertical
cylinder on diamond centre with flattened ellipse shadow 1.0x0.5, even spacing, no border,
no text, no labels, no horizon, no scenery
```

> **Tip:** If your generator merges frames, add: `four separate sprites in a row, grid layout 4x1, contact sheet, separated cells with small gap`.

### Universal Negative Prompt (always add)

```
photorealistic, 3d render, CGI, blurry, anti-aliased, gradient mesh, watercolor, oil painting,
sketch, noisy, low-res upscale, eye-level front-on elevation, side silhouette only, flat billboard,
horizon line, sky, clouds, forest landscape, multiple different trees blended, background scenery,
grass field beyond tile, text, letters, numbers, watermark, frame, border, vignette, drop shadow
beyond flattened ground oval, asymmetric trunks between frames, different species in same row,
top-down map symbol, icon, voxel block
```

---

### 1a. Transparency Workaround — Because Most Generators Can't Do Alpha

| Generator | Can it do transparent? | What to type in prompt | How to strip background (10 sec) |
|---|---|---|---|
| **Midjourney** | ❌ always fills BG | Use **Solid Chroma-Key BG** `#00FF6A` | Download → [remove.bg](https://www.remove.bg) or Photoshop `Select > Color Range > #00FF6A` → Delete. Or Pillow snippet below. |
| **DALL·E 3 / GPT-Image** | ❌ white/grey BG | `isolated on pure flat white background #FFFFFF, studio white` | Same — white is trivial to key. |
| **SDXL / Flux / ComfyUI** | ❌ unless add-on | `solid flat pastel green #A8D88A, even color` + use `rembg` / `birefnet` node | Comfy: `RMBG` node → `Alpha`. Auto. |
| **Leonardo.ai / Recraft / Ideogram** | ✅ has `Transparent BG` toggle | Use **Transparent BG** variant + turn ON `Transparent PNG` / `Remove Background` in UI | Already transparent — done. |
| **Firefly** | ✅ `Remove Background` button | Either — then click `Remove Background` | Built-in. |

**Recommended universal trick — bright green key ` #00FF6A`:**

- It's **not in any tree palette** (Golf Tycoon's greens are desaturated `#6BAE4A`–`#7EC850`, cactus `#4E9A3A`). `#00FF6A` is neon enough to select perfectly with zero erosion of leaf edges.
- Avoid pure magenta `#FF00FF` — heather's purple flowers (`#B070C0`) can get clipped. Green is safer.
- Alternative: pure **light golf beige `#E8E2C8`** if you prefer a warm paper tone — also absent from sprites.

**One-click removal — Python (no install beyond Pillow):**

```python
from PIL import Image

# For solid #00FF6A background — makes it transparent
sheet = Image.open("sheet_oak_chromakey.png").convert("RGBA")
key = (0, 255, 106)  # #00FF6A
px = sheet.load()
for y in range(sheet.height):
    for x in range(sheet.width):
        if px[x, y][:3] == key:
            px[x, y] = (0, 0, 0, 0)
sheet.save("sheet_oak_transparent.png", "PNG")

# For white background (#FFFFFF) — allow near-white 250+ to catch anti-alias fringe
sheet = Image.open("sheet_white.png").convert("RGBA")
px = sheet.load()
for y in range(sheet.height):
    for x in range(sheet.width):
        r, g, b, a = px[x, y]
        if r > 248 and g > 248 and b > 248:  # near-white → transparent
            px[x, y] = (0, 0, 0, 0)
sheet.save("sheet_transparent.png")
```

**Even easier — `rembg` (works even if AI added a soft vignette):**

```bash
pip install rembg[cli] --break-system-packages
rembg i sheet_oak_chromakey.png sheet_oak_transparent.png
```

**ComfyUI:** `Load Image → Rembg (BiRefNet) → Save Image (RGBA)`.

> **Pro move:** Generate at **4× size** on solid green (e.g., oak `256×320` instead of `64×80`) — the larger canvas gives the keyer more edge pixels, so the final `NEAREST` downscale lands perfectly crisp and no green fringe remains.

---

## 2. Canvas & Tech Specs

These are the **exact canvas sizes** the engine expects. Generate at **4×** then downscale with `Nearest Neighbor` for extra crispness.

| # | Species (`<name>.png`) | Canvas | `SPRITE_BASE_OFFSETS` | Biome / Theme | Isometric Silhouette Hint |
|---|---|---|---|---|---|
| 1 | **oak** | **64×80** | 22.0 | Parkland, Woodland (flagship) | Huge dome viewed from above — top highlight is an oval, sides fall away with dither |
| 2 | **birch** | **48×80** | 25.0 | Parkland, Heathland | Tall slender — white vertical cylinder trunk (perspective), small crown with visible top |
| 3 | **pine** | **48×80** | 32.0 | Mountain, Heathland | Cone of tiers — isometric sees concentric ovals shrinking upward |
| 4 | **maple** | **56×72** | 20.0 | Parkland, City | Broad shallow dome — top-down shows radial leaf texture |
| 5 | **palm** | **56×80** | 22.0 | Desert, Tropical | Vertical trunk, fronds radiate from top point — top view is starburst |
| 6 | **dead_tree** | **56×80** | 28.0 | Marshland, spooky | Bare armature — branches reach in 3D, seen obliquely |
| 7 | **cactus** | **40×64** | 24.0 | Desert | Column on diamond — 2 arms are 3D volumes, not flat cutouts |
| 8 | **bush** | **40×40** | 12.0 | All / fairway filler | Low mound — isometric top is fullest, sides rounded |
| 9 | **cattails** | **32×48** | 16.0 | Marshland, water edge | Reed cluster — thin verticals with 3D heads |
| 10 | **fescue** | **32×32** | 10.0 | Links, rough | Tiny tuft — wispy blades splay in 3D, top cluster visible |
| 11 | **heather** | **32×32** | 10.0 | Heathland, moor | Ground-hugger — top-down flower scatter on diamond |

**Anatomy of a frame in isometric (for the AI):**

- **Camera:** Fixed high-oblique `26.6°` elevation, `135°` sun (southeast). Same for N/E/S/W — only azimuth turns `90°` per step.
- **Trunk anchor:** `bottom-center + SPRITE_BASE_OFFSETS` — trunk meets tile at diamond centre, trunk is **vertical cylinder** (not a flat rectangle), lit on sun side. Jitter `±6px X / ±3px Y` and scale `0.85–1.15×` are applied per tile in-game — generate the neutral centred version.
- **Ground shadow:** Flattened ellipse at `scale (1.0, 0.5)` directly under trunk at `tile_width*0.06, tile_height*0.06` from centre, `spread = tile_width*0.3*scale`, `Color(0,0,0,0.2)`. That's the only ground mark — no full tile texture.
- **Crown:** Volume, not disc. Isometric sees the **top plane** (highlighted, dithered) + **two side faces**. Crown leans with terrain elevation (`ELEVATION_STEP_Y=10px`) but base generation is flat.
- **East view:** Crown **foreshortened 0.82× in screen-X** toward trunk (isometric + perspective), **sheared ≤3px at crown top** in screen-X toward azimuth, lit from **right** (gradient highlight on right edge). See `tools/tree_art/generate.py` `PROFILES["e"]`.
- **West view:** Mirrored East, sheared opposite, lit from left.
- **South view:** Mirrored North, **0.88× brightness** (sun-away), east/west limbs swapped.
- **North view:** Hero — brightest, front-oblique with top clearly visible. This is the authored source (`<species>.png`); `generate.py` can derive E/S/W from it if you prefer.

---

## 3. Master Prompt Template

```
[GLOBAL STYLE FRAGMENT] + [CAMERA FRAGMENT — isometric top-down oblique] + [TREE-SPECIFIC DESCRIPTION with top texture] + [BACKGROUND VARIANT A or B] + [TECHNICAL LAYOUT FRAGMENT — same elevation, azimuth rotates] + --ar 4:1
```

For SDXL / Flux / Ideogram, keep it as one paragraph. For Midjourney, you can weight with `::`.

**MJ weighting example:**
```
pixel art isometric dimetric sprite sheet::2 high-oblique 26.6 degrees top-down::1.5 [tree description with top highlight]::2 four azimuth views same elevation::1.5 solid green background::1 --ar 4:1 --v 6 --style raw --s 250 --no photorealistic, eye-level, horizon, forest background
```

**Generation Settings (recommended):**

- **Steps:** 28–36
- **Sampler:** Euler a / DPM++ 2M Karras
- **CFG:** 6.5–8 (lower = truer pixels)
- **Resolution:** Generate 4× canvas (e.g., oak 256×320 on solid green) then strip BG → downscale 25% with `NEAREST` to target.
- **Upscaler:** None — or `ESRGAN 4× (Anime6B)` then pixelate back down.
- **Seed:** Lock seed after first good N view, then `img2img` 0.35 for E/S/W consistency if not sheet-based.

---

## 4. Per-Species Prompts — Copy & Paste

Each block is **ready to paste**. Replace `BACKGROUND` with `BACKGROUND A` (transparent) or `BACKGROUND B` (solid chroma green) from §1 — all blocks use the placeholder `[BG]`.

### 1) OAK — `oak.png` — 64×80 — The Parkland King

**Vibe:** Grand, friendly, storybook parkland oak. The tree players remember.

```text
pixel art game asset sprite sheet, majestic parkland oak tree massive dense rounded dome canopy,
top-down oval highlight pale lime on canopy TOP with three dithered vibrant green side tones
falling away under isometric light, volumetric 3D dome with clear top texture and overlapping
leaf clusters, thick vertical cylindrical gnarled warm brown trunk with vertical bark grooves
standing at centre of isometric diamond tile, tiny flattened elliptical ground shadow (50% vertical
scale, 20% opacity) under trunk, ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE VIEW high camera
26.6 degrees above ground looking down from southeast at terrain tile, seeing TOP of canopy plus
two side faces, not a flat side elevation, 16-bit retro cozy golf tycoon hand-pixelled crisp 1px
outline, warm sun from top-right 135 degrees, dithered side shading, Stardew Valley meets SimGolf
building art projection sx=(u-v)*32 sy=(u+v)*16 - z, ultra-sharp nearest-neighbor,
isolated on solid flat chroma-key green background #00FF6A, even flat color,
sprite sheet single horizontal row of 4 identical volumetric trees at SAME isometric elevation
26.6 degrees only azimuth rotates: North (sees north+east faces) | East (sees east+south,
crown foreshortened 18% toward trunk leaned 3px right lit from right) | South (sees south+west
mirrored slightly darker 0.88x) | West (sees west+north mirrored foreshortened leaned left),
same dome, same height, same top highlight, trunk base at exact bottom-center, equal spacing,
no border, no horizon, no sky --ar 4:1
```
*For transparent-capable tools, swap `isolated on solid flat chroma-key green background #00FF6A, even flat color` → `isolated on transparent background, alpha channel`.*

**Alt Midjourney tags:** `giant rounded oak, storybook, lush dithered canopy, gnarled oak trunk --no acorn, forest background`

---

### 2) BIRCH — `birch.png` — 48×80 — Elegant White Sentinel

**Vibe:** Tall, slender, Scandinavian elegance. The white trunk is the hero.

```text
pixel art game asset sprite sheet, elegant birch tree, tall slender VERTICAL CYLINDRICAL pure
white trunk with crisp horizontal black bark dashes and subtle grey-blue sun shading on sun-away
side, small light airy lime-green-yellow crown with visible TOP oval texture and delicate side
clusters plus dark twig speckles, graceful volumetric 3D crown viewed from above, tiny flattened
elliptical ground shadow under trunk base, ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE VIEW 26.6 degrees
high camera looking down on diamond tile, seeing TOP of crown plus two faces, not flat side-on,
16-bit retro cozy golf tycoon hand-pixelled crisp 1px outline, warm top-right sun,
isolated on solid flat chroma-key green background #00FF6A, even flat color,
centered bottom-center anchor, sprite sheet horizontal row of 4 identical volumetric birches at
SAME elevation azimuth rotates N|E squashed leaned right|S darker|W squashed leaned left,
same white cylinder every frame --ar 4:1
```

**Key detail:** White trunk must stay bright — AI loves to muddy it brown; add to positive: `pure white trunk, black markings` and to negative: `brown trunk`.

---

### 3) PINE — `pine.png` — 48×80 — Alpine Triangle

**Vibe:** Perfect Christmas-tree cone, layered, Mountain theme icon.

```text
pixel art game asset sprite sheet, perfect conical alpine pine fir tree, triangular volume of
5-6 distinct stacked tiers each as an oval viewed from above with dark forest green undersides
and mint emerald TOP-PLANE highlights, narrow vertical cylindrical brown trunk at centre of
isometric diamond, crisp 3D layered tiers with visible TOP texture on every level, tiny flattened
elliptical ground shadow, ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE 26.6 degrees high camera looking
down on terrain tile, seeing TOP of tiers plus two side faces, not flat triangle silhouette,
16-bit retro cozy hand-pixelled crisp 1px outline, isolated on solid flat chroma-key green
background #00FF6A, even flat color, sprite sheet horizontal row of 4 identical volumetric pines
at SAME elevation (North | East foreshortened 18% leaned right | South mirrored darker |
West foreshortened leaned left) --ar 4:1
```

**Winter prompt add-on:** `snow-dusted pine, white snow caps on branch tiers, snowy ground shadow, winter`

---

### 4) MAPLE — `maple.png` — 56×72 — Broad Canopy

**Vibe:** Slightly smaller than oak, warmer, friendly shade tree.

```text
pixel art game asset sprite sheet, broad rounded maple tree shallow dome canopy, isometric TOP
texture warm yellow-green amber radial leaf pattern with soft dithered falloff down sides, lighter
TOP highlight and side shading, medium vertical cylindrical brown trunk at diamond centre,
tiny flattened elliptical ground shadow, ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE VIEW 26.6 degrees
high camera on diamond tile, volumetric 3D dome seeing TOP plus two sides, not flat side mound,
16-bit retro cozy hand-pixelled crisp 1px outline, isolated on solid flat chroma-key green
background #00FF6A, sprite sheet horizontal row 4 identical volumetric maples at SAME elevation
N|E squashed leaned right|S darker|W squashed leaned left --ar 4:1
```

---

### 5) PALM — `palm.png` — 56×80 — Tropical Vacation

**Vibe:** Instant holiday. Curved, breezy, Desert/Tropical.

```text
pixel art game asset sprite sheet, tropical palm tree, thick vertical curved cylindrical
segmented sandy-brown trunk with dark ring bands and perspective taper (foreshortened, not flat),
crown of 7 long arching volumetric fronds radiating from TOP centre point — isometric sees starburst
TOP texture with yellow-green TOP highlights and darker undersides, two small coconuts tucked under
fronds viewed obliquely, tiny flattened elliptical ground shadow 1.0x0.5 under trunk,
ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE 26.6 degrees high camera on diamond tile, seeing TOP
starburst plus two side frond faces, 16-bit retro cozy hand-pixelled crisp 1px outline,
isolated on solid flat chroma-key green background #00FF6A, sprite sheet horizontal row 4 identical
volumetric palms at SAME elevation N front-oblique|E 90° azimuth|S mirrored darker|W 270° --ar 4:1
```

---

### 6) DEAD TREE — `dead_tree.png` — 56×80 — Haunted Heathland

**Vibe:** Spooky, beautiful, gothic — Halloween heathland star.

```text
pixel art game asset sprite sheet, dead gnarled tree volumetric bare armature, twisted vertical
cylindrical grey-brown trunk with deep bark grooves and two main forked skeletal branches rising
in 3D (foreshortened with isometric perspective), delicate twig fingers reaching outward in space
and seen obliquely from above, hollow knot on trunk side, no leaves — shows branch structure in
3D viewed from high oblique, tiny flattened elliptical ground shadow, ISOMETRIC 2:1 DIMETRIC
TOP-DOWN OBLIQUE 26.6 degrees high camera looking down on diamond tile, seeing branch volume
plus trunk side faces, not flat icon, 16-bit retro cozy pixel art hand-pixelled crisp outline,
isolated on solid flat chroma-key green background #00FF6A, sprite sheet horizontal row 4 identical
volumetric bare trees at SAME elevation N|E foreshortened leaned right lit right|S slightly darker|W --ar 4:1
```

---

### 7) CACTUS — `cactus.png` — 40×64 — Desert Guardian

**Vibe:** Friendly saguaro, two arms, instant Desert theme.

```text
pixel art game asset sprite sheet, classic saguaro cactus 3D column, central vertical cylindrical
column with flat TOP dome viewed from above plus two upward-curved cylindrical arms (3D volumes,
not flat cutouts), vibrant cactus green with darker green vertical rib side shading and TOP highlight,
small creamy 3D dot spines on ribs, tiny flattened elliptical sandy ground shadow 1.0x0.5 at diamond
centre, ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE 26.6 degrees high camera on terrain tile,
seeing TOP domes plus two side faces, 16-bit retro cozy hand-pixelled crisp 1px outline,
isolated on solid flat chroma-key green background #00FF6A, sprite sheet horizontal row 4
identical volumetric cacti at SAME elevation N|E foreshortened leaned right|S mirrored darker|W --ar 4:1
```

---

### 8) BUSH — `bush.png` — 40×40 — The Fairway Filler

**Vibe:** Cute, dense, low hemisphere — fills gaps, defines rough.

```text
pixel art game asset sprite sheet, low dense hemispherical bush shrub 3D mound, volumetric dome
with visible TOP highlight two-tone vibrant greens and darker underside shading around sides,
compact rounded puff with 3-4 overlapping leaf clusters — isometric sees TOP oval fullest plus
side curvature, tiny flattened elliptical ground shadow under centre, ISOMETRIC 2:1 DIMETRIC
TOP-DOWN OBLIQUE 26.6 degrees high camera on diamond tile, 16-bit retro cozy pixel art
hand-pixelled crisp 1px outline, isolated on solid flat chroma-key green background #00FF6A,
sprite sheet horizontal row 4 identical volumetric bushes at SAME elevation N|E foreshortened
leaned right|S mirrored darker|W mirrored leaned left --ar 4:1
```

---

### 9) CATTAILS — `cattails.png` — 32×48 — Marsh Reeds

**Vibe:** Waterside detail, tall thin, whispers of wind.

```text
pixel art game asset sprite sheet, marsh cattails reeds cluster volumetric, 5-6 thin vertical
cylindrical reed-green stalks of varying height with 3D TOP viewed as small circles plus 2-3
golden-brown cylindrical sausage cattail heads (volumes, not flat bars), delicate side leaf blades
and drooping seed fluff seen obliquely from above, tiny flattened elliptical ground shadow,
ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE 26.6 degrees high camera on diamond tile,
16-bit retro cozy pixel art hand-pixelled crisp outline, isolated on solid flat chroma-key green
background #00FF6A, sprite sheet horizontal row 4 identical volumetric reed clusters at SAME
elevation N|E foreshortened leaned right|S mirrored darker|W --ar 4:1
```

---

### 10) FESCUE — `fescue.png` — 32×32 — Links Tussock

**Vibe:** Wispy, wild, linksland rough — straw wind-blown grass.

```text
pixel art game asset sprite sheet, fescue tussock grass tuft micro volumetric, spiky wild
straw-green-beige clump with thin 3D blades splaying outward in all directions — isometric sees
denser TOP cluster highlight plus side wisps, lighter tips on sun-lit TOP, tiny flattened elliptical
ground shadow, ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE 26.6 degrees high camera on diamond tile
but very low height so foreshortening subtle, 16-bit retro cozy micro sprite hand-pixelled crisp
outline, isolated on solid flat chroma-key green background #00FF6A, sprite sheet horizontal row
4 identical volumetric tufts at SAME elevation N|E squashed|S darker|W --ar 4:1
```

---

### 11) HEATHER — `heather.png` — 32×32 — Moorland Carpet

**Vibe:** Tiny, precious, purple jewel — heathland ground cover.

```text
pixel art game asset sprite sheet, low heather ground cover plant volumetric micro mound, compact
mound of tiny green leaves viewed ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE 26.6 degrees high camera
— TOP plane scattered with 12-15 vibrant purple-pink 3D flower dots plus side shading, very low
height flattened dome sitting flush on diamond tile with tiny flattened elliptical ground shadow,
16-bit retro cozy hand-pixelled micro sprite crisp outline, isolated on solid flat chroma-key green
background #00FF6A, sprite sheet horizontal row 4 identical volumetric heather mounds at SAME
elevation N|E squashed|S darker|W --ar 4:1
```

---

## 5. Seasonal Variant Prompts (Seasons Mod `mods/golf_tycoon.seasons/tree_art/`)

These **replace only the canopy description** in the base prompt. Keep everything else (canvas, layout, style, negative, and your chosen BG).

| Season Folder | Species | Canvas | Canopy Swap Text |
|---|---|---|---|
| `spring/` | **birch** | 48×80 | `fresh spring birch, lime pastel green buds opening, 6-8 tiny pink cherry blossom dots, airy` |
| `spring/` | **maple** | 56×72 | `spring maple, fresh lime yellow-green buds, 6 tiny soft pink blossoms scattered in canopy` |
| `spring/` | **oak** | 64×80 | `spring oak, fresh bright lime green young leaves, 8 tiny pale pink-white blossoms on outer canopy` |
| `fall/` | **birch** | 48×80 | `autumn birch, golden yellow-orange canopy, warm fall glow, sparse` |
| `fall/` | **maple** | 56×72 | `autumn maple, fiery orange-red-gold canopy, dense warm fall colors, glowing dappled highlights` |
| `fall/` | **oak** | 64×80 | `autumn oak, warm amber golden-orange canopy, rich fall colors, cozy harvest light` |
| `winter/` | **birch** | 48×80 | `winter birch, completely bare branches with light snow dusting on twigs, white trunk with snow highlights, stark winter` |
| `winter/` | **maple** | 56×72 | `winter maple, bare twisted branches with light snow on limbs, no leaves, cold winter` |
| `winter/` | **oak** | 64×80 | `winter oak, bare gnarled branches with light snow on outer twigs, no leaves, stark winter silhouette` |
| `winter/` | **pine** | 48×80 | `winter alpine pine, snow-capped fir tiers with thick white snow on every branch ledge, snowy evergreen` |

**Example: Spring Oak Sprite Sheet (64×80 ×4) — solid green BG**

```text
pixel art game asset sprite sheet, spring oak tree volumetric dome, TOP fresh bright lime green
young leaves TOP highlight with 8 tiny pale pink-white blossoms scattered on outer TOP canopy
viewed isometrically from above plus two side faces, thick vertical cylindrical warm brown gnarled
trunk at diamond centre, tiny flattened elliptical ground shadow 1.0x0.5, ISOMETRIC 2:1 DIMETRIC
TOP-DOWN OBLIQUE 26.6 degrees high camera on diamond tile, 16-bit retro cozy hand-pixelled crisp
1px outline, warm sun from top-right, isolated on solid flat chroma-key green #00FF6A, sprite sheet
horizontal row 4 identical volumetric trees at SAME elevation N|E foreshortened leaned right|
S mirrored darker|W foreshortened leaned left --ar 4:1
```

**Example: Fall Maple Sprite Sheet**

```text
pixel art game asset sprite sheet, autumn maple TOP fiery orange-red-gold dense warm fall TOP
volumetric dome viewed isometrically from above plus two side faces, medium vertical cylindrical
brown trunk, tiny flattened elliptical ground shadow, ISOMETRIC 2:1 DIMETRIC 26.6 degrees high camera
on diamond tile, 16-bit retro cozy, isolated on solid flat chroma-key green #00FF6A, sprite sheet
horizontal row 4 identical volumetric maples at SAME elevation --ar 4:1
```

**Example: Winter Pine Sprite Sheet**

```text
pixel art game asset sprite sheet, winter snow-capped alpine pine fir volumetric stacked tiers,
each tier is oval TOP horizontal plane with thick white snow TOP caps viewed from above, dark green
side walls peeking, narrow vertical cylindrical brown trunk, tiny snowy flattened elliptical ground
shadow 1.0x0.5, ISOMETRIC 2:1 DIMETRIC TOP-DOWN OBLIQUE 26.6 degrees high camera on diamond tile,
16-bit retro cozy, isolated on solid flat chroma-key green #00FF6A, sprite sheet horizontal row
4 identical volumetric snowy pines at SAME elevation N|E|S|W --ar 4:1
```

---

## 6. Tool-Specific Tweaks

### Stable Diffusion XL / Flux / ComfyUI / Ideogram / Leonardo
- Paste the full block as **Prompt**, Negative Prompt in negative field.
- Use `Euler a`, 32 steps, CFG 7, generate at ~1024×256 on **solid green #00FF6A** → strip → downscale.
- Add trigger words at start: `pixel art, sprite sheet` — these dominate SDXL's attention.
- If trunk drifts, add `ControlNet: canny edge of N view, weight 0.75` for E/S/W consistency.
- **ComfyUI:** `Load Image → Rembg (BiRefNet) → Save Image (RGBA)` — one node removes the green.

### Midjourney v6
- Add `--ar 4:1 --v 6 --style raw --s 250 --chaos 4` (low chaos keeps frames identical).
- Use `--no photorealistic, forest, sky, text` rather than a separate negative box.
- Prompt must say `solid chroma-key green background #00FF6A` explicitly — MJ respects color hexes well.
- For tiny foliage (heather/fescue/cattails) add `micro sprite, 32x32 canvas` — MJ tends to over-detail these.

### DALL·E 3 / Firefly / GPT-Image
- Use the **full sentence** variant (no `--ar` tags). Add at end: `Make a horizontal sprite sheet with four equal panels side by side, each panel showing the same tree from a different cardinal direction, isolated on solid flat white background #FFFFFF for easy background removal, no text.`
- Request `pixel art, crisp pixels, no blur` twice — DALL·E loves to smooth.
- After download, white is one click to strip (see Python snippet in §1a — `r>248`).

### Ideogram / Recraft / Playground
- Enable `Magic Prompt: OFF` (it adds scenery). Turn ON `Transparent PNG` if available — then use BG variant A.
- Otherwise generate on white and strip: built-in `Remove Background` button works.

---

## 7. Workflow: From Prompt to Engine

```
1. Generate 4× sheet on SOLID GREEN (e.g., oak 1024×320 → native 64×80×4, #00FF6A BG)
       │
2. Strip solid to transparent (see §1a — rembg / Python / Photopea / GIMP)
       │
3. Downscale with NEAREST NEIGHBOR to exact canvas ×4 width
       e.g., PIL:  Image.resize((target_w, target_h), Image.NEAREST)
       │  (doing strip BEFORE downscale = no green fringe)
       │
4. Slice into 4 PNGs:
       oak_n.png = sheet[0:64, 0:80]        (North = shipped source)
       oak_e.png = sheet[64:128, 0:80]      (East  = squashed leaned right, lit right)
       oak_s.png = sheet[128:192, 0:80]     (South = mirrored darker)
       oak_w.png = sheet[192:256, 0:80]     (West  = mirrored squashed leaned left)
       │
5. Drop into:
       assets/sprites/trees/<species>.png        (copy of _n, per docs)
       assets/sprites/trees/<species>_{n,e,s,w}.png
       mods/golf_tycoon.seasons/tree_art/<season>/<species>.png (+ _n/_e/_s/_w via generate.py)
       │
6. Run:  python3 tools/tree_art/generate.py --check   # verifies no stale view
       or python3 tools/tree_art/generate.py           # regenerates _e/_s/_w if you keep N only
```

> **Prefer AI for N only:** The canonical pipeline is AI → N view (strip → transparent) → `generate.py` derives E/S/W via precise `PROFILES` (squash 0.82, shear ±3px, light gradients). This guarantees `TreeOverlay.SPRITE_BASE_OFFSETS` alignment. The 4-view sheet prompts above bake those transforms in so you can **compare** — pick whichever looks better, but keep N as source of truth.

**Python slicer (after stripping):**

```python
from PIL import Image
sheet = Image.open("sheet_oak_transparent.png")  # 256x80 RGBA
w = sheet.width // 4
for i, facing in enumerate("n e s w".split()):
    sheet.crop((i*w, 0, (i+1)*w, sheet.height)).save(f"oak_{facing}.png", "PNG")
```

**Mega-sheet slicer (11 rows × 4 cols):**

```python
from PIL import Image
sheet = Image.open("mega_sheet_transparent.png")  # e.g., 512x1760 RGBA (64*4*2 × ~80*11*2)
ROWS = ["oak","birch","pine","maple","palm","dead_tree","cactus","bush","cattails","fescue","heather"]
CANVASES = [(64,80),(48,80),(48,80),(56,72),(56,80),(56,80),(40,64),(40,40),(32,48),(32,32),(32,32)]
# If you generated at 4× and stripped: row height ≈ canvas_h * scale, col width ≈ canvas_w * scale
# For variable row heights, slice by known canvas ratios or export with faint grid guides.
# Easiest: generate grouped mega-sheets by height (see §10) — then uniform rows.
```

---

## 8. Quick Copy Block — All 11 Species (SDXL Ready, Solid BG)

<details>
<summary>Click to expand: 11-prompt cheat sheet for bulk generation</summary>

```text
# OAK 64x80 — isometric diorama on diamond
pixel art game asset, majestic oak dense rounded dome TOP oval highlight three greens volumetric, vertical cylindrical gnarled brown trunk, flattened ellipse shadow 1.0x0.5, ISOMETRIC 2:1 DIMETRIC 26.6° top-down oblique on diamond tile seeing TOP+2 sides, isolated on solid chroma-key green #00FF6A, sprite sheet row 4 same elevation N|E foreshortened leaned right lit right|S mirrored darker 0.88x|W mirrored foreshortened leaned left --ar 4:1

# BIRCH 48x80
pixel art game asset sprite sheet, elegant birch pure white trunk black horizontal dashes lime airy canopy, ground shadow, 16-bit retro cozy hand-pixelled, isolated on solid chroma-key green #00FF6A centered, sprite sheet row 4 identical N|E squashed|S mirrored darker|W --ar 4:1

# PINE 48x80
pixel art game asset sprite sheet, conical alpine pine fir triangular 5-6 tiered dark to mint greens narrow brown trunk, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# MAPLE 56x72
pixel art game asset sprite sheet, broad rounded maple warm yellow-green amber canopy medium brown trunk, ground shadow, 16-bit retro cozy hand-pixelled, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# PALM 56x80
pixel art game asset sprite sheet, tropical palm thick curved segmented sandy brown trunk 7 arching green fronds, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# DEAD_TREE 56x80
pixel art game asset sprite sheet, dead bare gnarled grey-brown tree no leaves skeletal claw branches hollow knot, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# CACTUS 40x64
pixel art game asset sprite sheet, classic saguaro cactus green two arms rib shading, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# BUSH 40x40
pixel art game asset sprite sheet, low dense hemispherical bush two-tone greens berry dots, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# CATTAILS 32x48
pixel art game asset sprite sheet, marsh cattails 6 reed stalks 3 golden brown heads, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# FESCUE 32x32
pixel art game asset sprite sheet, fescue tussock straw-green spiky tuft wispy tips, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# HEATHER 32x32
pixel art game asset sprite sheet, heather ground cover green mound 15 purple flower dots, ground shadow, 16-bit retro cozy pixel art, isolated on solid green #00FF6A centered, sprite sheet row 4 identical N|E|S|W --ar 4:1
```

</details>

---

## 9. Pro Tips for Amazing Results

1. **Lock the trunk.** Add `bottom-center trunk anchor at exact same pixel in every frame` — stops AI drifting the base between views.
2. **Name the light.** `top-right light` + `East lit from right, West lit from left, South darker` gives the engine's shading model.
3. **Say "same tree".** Repeat `same tree silhouette every frame, identical tree` — otherwise AI invents 4 different oaks.
4. **Tiny canvas discipline.** For 32×32 (heather/fescue) add `micro sprite, 32x32, minimal detail` — prevents over-rendering.
5. **No scenery.** `no background scenery, no grass field, no sky` must be explicit; AI wants to place trees in forests. Saying `solid flat color background` is stronger than `transparent`.
6. **Generate big, strip, then downscale.** 4× on solid green → `rembg` → `NEAREST` downscale preserves pixel crispness and eliminates green fringe. Doing it in this order is key.
7. **Seasonal recolor, not reshape.** For seasonal variants, keep `same silhouette and trunk, only canopy color changes` — ensures fall birch is recognizably the same birch.
8. **Test your key first.** Generate one sheet, run the Python snippet on it, and open the RGBA in Godot — the trunk's tiny shadow should stay, the green should be gone.

---

## 10. MEGA SHEET — All 11 Trees Together (11 rows × 4 columns)

This is for a **single master image** that contains every species at once — perfect for a style-reference sheet, a portfolio poster, an art-brief for an artist/AI, or to ensure every tree shares the exact same palette and light direction before slicing.

### 10a. Why a Mega Sheet?

- One generation = **consistent palette & lighting** across all species (no "same prompt, different seed" drift).
- One background strip operation for all 44 sprites.
- Feeds directly to `tmp_preview/tree_facings.png` style contact sheets — but with your new art.

### 10b. The One-Prompt Mega Sheet (SDXL / Midjourney / Flux)

> **Warning:** 44 sprites in one image is ambitious — budget models will wobble on the tiny rows (heather/fescue). If you get blending artifacts, use the **Grouped Mega Sheets** in §10c instead (3 smaller, more reliable prompts).

**Paste this entire block — it lists all 11 species top-to-bottom in row order:**

```text
pixel art master sprite sheet contact sheet, grid layout 11 rows × 4 columns = 44 pixel art trees,
isolated on solid flat chroma-key green background #00FF6A, even flat color, 16-bit retro cozy
golf tycoon style, hand-pixelled crisp 1px outline, warm soft lighting from top-right,
dithered shading, Stardew Valley meets SimGolf, ultra-sharp pixels,

ROW 1: majestic parkland oak massive dense rounded vibrant green canopy three green tones
       thick gnarled warm brown trunk with forked branches peeking through leaves
ROW 2: elegant birch slender tall pure white trunk with black horizontal bark dashes
       light airy lime green-yellow delicate canopy
ROW 3: conical alpine pine fir triangular 5-6 tiered dark forest to mint emerald
       narrow straight brown trunk
ROW 4: broad rounded maple warm yellow-green amber canopy medium brown trunk subtle fork
ROW 5: tropical palm thick curved segmented sandy-brown trunk 7 long arching green fronds
       with two small coconuts
ROW 6: dead gnarled tree completely bare leafless grey-brown skeletal claw branches
       hollow knot, spooky
ROW 7: classic saguaro cactus central column two arms cactus green with rib shading
ROW 8: low dense hemispherical bush shrub two-tone greens red berry dots compact puff
ROW 9: marsh cattails reeds 6 thin reed stalks with 2-3 golden-brown cattail heads
ROW 10: fescue tussock grass spiky straw-green-beige wispy blades splaying outward
ROW 11: low heather ground cover compact green mound with 12-15 purple-pink flower dots

each row has single species repeated 4 times as directional views left-to-right:
N front view | E right-side squashed 18% leaned 3px right lit from right | S back mirrored darker
| W left-side mirrored leaned left, same silhouette every column in that row, perfectly aligned
bottom-center trunk anchor with tiny soft elliptical ground shadow in every cell,
even equal spacing between rows and columns, no border, no text, no labels, no scenery,
no sky, no forest, game-ready sprites --ar 4:3
```

**Settings:** `--ar 4:3` (11 rows is tall — use `1536×1152` generation, then strip → downscale). For SDXL: `1536w × 1152h`, `CFG 6`, `32 steps`. For MJ: `--ar 4:3 --v 6 --style raw --s 220 --chaos 5 --no text, labels, forest, sky`.

**How to slice the mega sheet (after stripping green → RGBA):**

Each row's height is proportional to that species' canvas height. If you generated at a uniform 2× scale (e.g., each cell `128×160` max), easiest is to slice by fractions:

```python
from PIL import Image
sheet = Image.open("mega_sheet_transparent.png").convert("RGBA")
W, H = sheet.size
cols, rows = 4, 11
cell_w, cell_h = W // cols, H // rows
# Rows are in the order listed in the prompt
names = ["oak","birch","pine","maple","palm","dead_tree","cactus","bush","cattails","fescue","heather"]
for r, name in enumerate(names):
    for c, facing in enumerate(["n","e","s","w"]):
        x0, y0 = c*cell_w, r*cell_h
        cell = sheet.crop((x0, y0, x0+cell_w, y0+cell_h))
        # Trim chroma leftovers and center on true canvas (e.g., oak 64×80 → heather 32×32)
        # Find alpha bbox, then pad to canonical size if you need exact canvas:
        bbox = cell.getchannel("A").getbbox()
        if bbox:
            trimmed = cell.crop(bbox)
            # Optional: pad trimmed to target canvas centered (keeps bottom-center anchor)
            # Use canvases from §2 to pad:
            print(f"{name}_{facing}: trimmed {trimmed.size} from cell {cell_w}x{cell_h}")
            trimmed.save(f"{name}_{facing}.png", "PNG")
```

> **Tip:** After trimming, `ImageOps.pad(trimmed, target_canvas, color=(0,0,0,0), centering=(0.5, 1.0))` with `centering y=1.0` pins the trunk to the bottom-center — exactly what `TreeOverlay` expects.

### 10c. Grouped Mega Sheets — More Reliable (Recommended)

If the 44-in-one wobbles, split into **3 grouped sheets by height** — near-uniform rows = perfect slicing and the AI has fewer species to juggle.

**Group A — Tall Trees (80px + 72px) — 6 rows × 4 cols = 24 sprites**

Canvas max: `64×80`. Prompt rows: `oak, birch, pine, maple, palm, dead_tree`.

```text
pixel art sprite sheet contact sheet, grid layout 6 rows × 4 columns = 24 pixel trees,
isolated on solid flat chroma-key green background #00FF6A, 16-bit retro cozy golf tycoon
hand-pixelled crisp 1px outline, warm top-right light, Stardew Valley style,
ROW 1 oak massive dense rounded green canopy thick gnarled brown trunk
ROW 2 birch white trunk black dashes lime canopy
ROW 3 pine conical tiered dark to mint fir
ROW 4 maple broad rounded warm yellow-green amber
ROW 5 palm curved segmented trunk 7 fronds coconuts
ROW 6 dead_tree bare skeletal grey-brown gnarled
each row 4 directional views N | E squashed leaned right lit right | S mirrored darker | W mirrored leaned left,
same silhouette per row, bottom-center anchor + tiny ground shadow every cell,
even spacing, no border, no text --ar 4:3
```

**Group B — Mid Shrubs (64px / 40px) — 2 rows × 4 cols = 8 sprites**

```text
pixel art sprite sheet contact sheet, grid layout 2 rows × 4 columns = 8 pixel shrubs,
isolated on solid flat chroma-key green background #00FF6A, 16-bit retro cozy golf tycoon
hand-pixelled, Stardew Valley style,
ROW 1 classic saguaro cactus two arms rib shading cactus green
ROW 2 low dense hemispherical bush two-tone greens berry dots
each row 4 views N | E squashed leaned right | S mirrored darker | W mirrored leaned left,
same silhouette per row, bottom-center anchor + tiny ground shadow, even spacing, no text --ar 2:1
```

**Group C — Tiny Ground Cover (48px / 32px) — 3 rows × 4 cols = 12 sprites**

```text
pixel art sprite sheet contact sheet, grid layout 3 rows × 4 columns = 12 tiny pixel plants,
isolated on solid flat chroma-key green background #00FF6A, 16-bit retro cozy golf tycoon
hand-pixelled micro sprite crisp outline, Stardew Valley style,
ROW 1 marsh cattails 6 thin reed stalks 3 golden-brown sausage heads
ROW 2 fescue tussock straw-green-beige spiky wispy blades
ROW 3 heather low mound green leaves 15 purple flower dots
each row 4 views N | E squashed leaned right | S mirrored darker | W mirrored leaned left,
same silhouette per row, bottom-center anchor + tiny ground shadow, even spacing, no text --ar 4:1
```

Generate the three groups, strip green → `NEAREST` downscale → slice — you now have all 44 sprites with zero wobble and perfect row uniformity.

### 10d. Seasonal Mega Sheets

Same pattern — swap the canopy line for that season's palette:

```text
# Spring Mega Sheet — 3 rows × 4 cols: birch, maple, oak in spring bloom
pixel art master sprite sheet contact sheet, grid 3 rows × 4 cols, isolated on solid flat
chroma-key green #00FF6A, 16-bit retro cozy golf tycoon, hand-pixelled,
ROW 1 spring birch lime pastel buds 6 tiny pink cherry blossoms
ROW 2 spring maple lime yellow-green buds 6 pink blossoms
ROW 3 spring oak bright lime green 8 pale pink-white blossoms thick brown trunk
each row 4 views N | E squashed leaned right | S mirrored darker | W mirrored leaned left --ar 4:2

# Fall Mega Sheet — same rows, autumn palette
ROW 1 autumn birch golden yellow-orange
ROW 2 autumn maple fiery orange-red-gold
ROW 3 autumn oak warm amber golden-orange

# Winter Mega Sheet — 4 rows × 4 cols: birch, maple, oak bare + pine snow-capped
ROW 1 winter birch bare branches light snow white trunk
ROW 2 winter maple bare twisted snow on limbs
ROW 3 winter oak bare gnarled snow on outer twigs
ROW 4 winter pine snow-capped fir thick white caps on tiers
```

Drop the seasonal mega sheets into `mods/golf_tycoon.seasons/tree_art/{spring,fall,winter}/` after slicing, then `python3 tools/tree_art/generate.py` for the derived `_e/_s/_w`.

---

## 11. File Map

```
assets/sprites/trees/
  oak.png (+ _n/_e/_s/_w)          64×80  ← use oak prompt
  birch.png (+ _n/_e/_s/_w)        48×80
  pine.png (+ _n/_e/_s/_w)         48×80
  maple.png (+ _n/_e/_s/_w)        56×72
  palm.png (+ _n/_e/_s/_w)         56×80
  dead_tree.png (+ _n/_e/_s/_w)    56×80
  cactus.png (+ _n/_e/_s/_w)       40×64
  bush.png (+ _n/_e/_s/_w)         40×40
  cattails.png (+ _n/_e/_s/_w)     32×48
  fescue.png (+ _n/_e/_s/_w)       32×32
  heather.png (+ _n/_e/_s/_w)      32×32

mods/golf_tycoon.seasons/tree_art/
  spring/{birch,maple,oak}.png + _n/_e/_s/_w
  fall/{birch,maple,oak}.png + _n/_e/_s/_w
  winter/{birch,maple,oak,pine}.png + _n/_e/_s/_w

tools/tree_art/
  generate.py            ← derives _e/_s/_w from N if you only ship N
  PROMPTS.md             ← this file (mirrored in docs/)

tmp_preview/tree_facings.png ← --preview contact sheet of all species
  └─ regenerate from mega sheet: generate at 4× on #00FF6A → strip → downscale → montage
```

*Happy growing — may your fairways be lush, your greens neon-free, and your sprite sheets crisp!*
