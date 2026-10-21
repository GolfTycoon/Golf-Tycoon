# Golf Tycoon — Tree Sprite Sheet Prompt Bible

> **Text-to-Image Prompts for Every Tree Species**
> *Create an amazing 4-view (N / E / S / W) pixel-art sprite sheet for each tree.*
> Covers the 11 base species in `assets/sprites/trees/` + all seasonal variants in `mods/golf_tycoon.seasons/tree_art/`.

---

## How to Read This Guide

- Every tree is **authored once** as the north-facing view (`<species>.png`). The tool `tools/tree_art/generate.py` derives the other three angles automatically — but with AI you can now generate **all four views at once** as a sprite sheet.
- Copy the **Copy-Paste Prompt** for your generator (Stable Diffusion XL, Midjourney v6, Flux, Ideogram, DALL·E 3) — then slice the sheet into `tree_n.png`, `tree_e.png`, `tree_s.png`, `tree_w.png`.
- Keep the **Global Style Fragment** + **Negative Prompt** in every generation. Only the per-tree description changes.

**Preview of what you're building:** a single PNG, transparent background, one horizontal row, four identical trees side-by-side — front, right, back, left — centered on the same ground anchor so `TreeOverlay.SPRITE_BASE_OFFSETS` needs no per-facing fix.

```
┌──────────┬──────────┬──────────┬──────────┐
│  N view  │  E view  │  S view  │  W view  │  ← one row, equal gaps
│  FRONT   │  RIGHT   │  BACK    │  LEFT    │
│ (lit)    │  +lean R │ (dark)   │ +lean L  │
└──────────┴──────────┴──────────┴──────────┘
          transparent background, ground shadow under each
```

---

## 1. Global Art Direction — INCLUDE IN EVERY PROMPT

Golf Tycoon is a **cozy, clean, 16-bit-era pixel art** tycoon — think *Stardew Valley* × *Theme Park (1994)* × *A Short Hike*, not photorealism. Every generation must obey this:

**Positive Style Fragment (paste verbatim):**

```
pixel art game asset, 16-bit retro cozy golf tycoon style, hand-pixelled,
crisp 1px outline, limited vibrant palette, warm soft lighting from top-right,
clean transparent background, centered on canvas, bottom-center trunk anchor on
tiny soft elliptical ground shadow, dithered shading, no anti-aliasing blur,
Stardew Valley meets SimGolf, highly detailed at small resolution, game-ready sprite
```

**Technical Layout Fragment (paste verbatim):**

```
sprite sheet, single horizontal row of 4 identical trees, four cardinal views:
North front view | East right-side view | South back view | West left-side view,
same tree silhouette in every frame, perfectly aligned ground line and trunk base centered,
equal spacing between frames, no border, no background, no text, no watermark,
transparent background, ultra-sharp pixels, nearest-neighbor
```

> **Tip:** If your generator keeps merging frames, add: `four separate sprites in a row, grid layout 4x1, contact sheet` and use `separate`.

**Universal Negative Prompt (always add):**

```
photorealistic, 3d render, CGI, blurry, anti-aliased, gradient mesh, watercolor, oil painting,
sketch, noisy, low-res upscale, background scenery, sky, grass field, multiple different trees,
forest, landscape, text, letters, numbers, watermark, frame, border, drop shadow, vignette,
asymmetric trunks between frames, different species in same sheet
```

---

## 2. Canvas & Tech Specs

These are the **exact canvas sizes** the engine expects. Generate at **4×** then downscale with `Nearest Neighbor` for extra crispness.

| # | Species (`<name>.png`) | Canvas | Biome / Theme | Silhouette | Palette Notes |
|---|---|---|---|---|---|
| 1 | **oak** | **64×80** | Parkland, Woodland (flagship) | Huge round dense crown, thick gnarled trunk | Deep greens × 3 tones + warm bark |
| 2 | **birch** | **48×80** | Parkland, Heathland | Tall elegant, slender white trunk, light airy canopy | White + black bark dashes, lime greens |
| 3 | **pine** | **48×80** | Mountain, Heathland | Triangular conical fir, layered branches | Dark forest → mint highlight tiers |
| 4 | **maple** | **56×72** | Parkland, City | Broad rounded, slightly flatter than oak | Yellow-green / warm amber canopy |
| 5 | **palm** | **56×80** | Desert, Tropical | Curved segmented trunk, 7 long fronds | Sandy brown trunk, vivid frond greens |
| 6 | **dead_tree** | **56×80** | Marshland, spooky | Bare gnarled branches, no leaves | Grey-brown bark, hollow, eerie |
| 7 | **cactus** | **40×64** | Desert | Classic saguaro + 2 arms | Cactus green + darker rib shading |
| 8 | **bush** | **40×40** | All / fairway filler | Low hemisphere shrub, dense | Two-tone tuft greens, soft top highlight |
| 9 | **cattails** | **32×48** | Marshland, water edge | 5–6 reeds + 3 brown cattail heads | Reed green + golden brown sausage tips |
| 10 | **fescue** | **32×32** | Links, rough | Spiky tussock grass tuft | Straw-green / beige, wispy tips |
| 11 | **heather** | **32×32** | Heathland, moor | Low ground cover, purple bloom carpet | Green base + 12–15 purple flower dots |

**Anatomy of a frame (for the AI):**

- **Trunk anchor:** bottom-center pixel(s) of canvas, same in all 4 views. `TreeOverlay` pins here.
- **Ground shadow:** tiny soft oval (dark sage / brown, ~40% opacity, 10–18px wide) directly under trunk. Keeps it planted on the tile.
- **East view:** crown **squashed 18% horizontally** toward trunk, **leans 3px right at crown top**, lit from **right** (gradient highlight on right edge).
- **West view:** mirrored East, leans 3px left, lit from left.
- **South view:** mirrored North, **slightly darker** (×0.88 brightness, lost sun), east/west limbs swapped.
- **North view:** your authored hero — brightest, front-lit.

Generate the four with **identical height** so the lean stays subtle.

---

## 3. Master Prompt Template

```
[GLOBAL STYLE FRAGMENT] + [TREE-SPECIFIC DESCRIPTION] + [TECHNICAL LAYOUT FRAGMENT] + --ar 4:1 --style pixel art
```

For SDXL / Flux / Ideogram, keep it as one paragraph. For Midjourney, you can weight with `::`.

**MJ weighting example:**
```
pixel art sprite sheet::2 [tree description]::2 four views in a row::1.5 transparent background::1.5 --ar 4:1 --tile --v 6 --style raw --s 250
```

**Generation Settings (recommended):**

- **Steps:** 28–36
- **Sampler:** Euler a / DPM++ 2M Karras
- **CFG:** 6.5–8 (lower = truer pixels)
- **Resolution:** Generate 4× canvas (e.g., oak 1024×320) then downscale 25% with `NEAREST` to target.
- **Upscaler:** None — or `ESRGAN 4× (Anime6B)` then pixelate back down.
- **Seed:** Lock seed after first good N view, then use `img2img` 0.35 for E/S/W consistency if not sheet-based.

---

## 4. Per-Species Prompts — Copy & Paste

Each block is **ready to paste**. Replace nothing — it already contains global + specific + layout. For brevity the Negative Prompt is listed once above; add it in your generator's negative field.

### 1) OAK — `oak.png` — 64×80 — The Parkland King

**Vibe:** Grand, friendly, storybook parkland oak. The tree players remember.

```text
pixel art game asset sprite sheet, majestic parkland oak tree with massive dense rounded canopy,
three layered shades of vibrant green with soft dithered highlights on top-right, thick gnarled
warm brown trunk with subtle vertical bark texture and two low forked branches peeking through
leaves, tiny soft elliptical ground shadow under trunk, 16-bit retro cozy golf tycoon style,
hand-pixelled crisp 1px outline, warm soft lighting from top-right, transparent background,
centered bottom-center anchor, sprite sheet single horizontal row of 4 identical trees
(North front view | East right-side squashed 18% leaned 3px right lit from right | South back
mirrored darker | West left-side mirrored leaned left), same silhouette every frame, equal spacing,
no border, Stardew Valley meets SimGolf, highly detailed at small resolution --ar 4:1
```

**Alt Midjourney tags:** `giant rounded oak, storybook, lush dithered canopy, gnarled oak trunk --no acorn, forest background`

---

### 2) BIRCH — `birch.png` — 48×80 — Elegant White Sentinel

**Vibe:** Tall, slender, Scandinavian elegance. The white trunk is the hero.

```text
pixel art game asset sprite sheet, elegant birch tree, slender tall pure white trunk with
crisp horizontal black bark dashes and subtle grey shading, light airy lime-green-yellow canopy
with delicate layered clusters and small dark twig speckles, graceful upright silhouette,
tiny soft ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline,
warm soft lighting from top-right, transparent background, centered bottom-center anchor,
sprite sheet single horizontal row of 4 identical trees (North front | East squashed 18%
leaned right lit right | South mirrored darker | West mirrored leaned left), same tree every frame
--ar 4:1
```

**Key detail:** White trunk must stay bright — AI loves to muddy it brown; add to positive: `pure white trunk, black markings` and to negative: `brown trunk`.

---

### 3) PINE — `pine.png` — 48×80 — Alpine Triangle

**Vibe:** Perfect Christmas-tree cone, layered, Mountain theme icon.

```text
pixel art game asset sprite sheet, perfect conical alpine pine / fir tree, triangular silhouette
with 5-6 distinct layered tiers of dark forest green to mint emerald highlights on top-right edges,
narrow straight warm brown trunk barely visible through branches, crisp snow-free evergreen,
tiny soft ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline,
transparent background, centered bottom-center anchor, sprite sheet single horizontal row of 4
identical trees (North front | East side squashed 18% leaned 3px right | South back mirrored darker
| West side mirrored leaned left), identical height all frames --ar 4:1
```

**Winter prompt add-on:** `snow-dusted pine, white snow caps on branch tiers, snowy ground shadow, winter`

---

### 4) MAPLE — `maple.png` — 56×72 — Broad Canopy

**Vibe:** Slightly smaller than oak, warmer, friendly shade tree.

```text
pixel art game asset sprite sheet, broad rounded maple tree, warm yellow-green amber canopy
with soft dithered autumnal glow, slightly flatter crown than oak, medium thick brown trunk
with subtle fork, airy leaf clusters with lighter top-right highlights, tiny soft ground shadow,
16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline, transparent background,
centered bottom-center anchor, sprite sheet single horizontal row of 4 identical trees
(North | East squashed leaned right | South mirrored darker | West mirrored leaned left) --ar 4:1
```

---

### 5) PALM — `palm.png` — 56×80 — Tropical Vacation

**Vibe:** Instant holiday. Curved, breezy, Desert/Tropical.

```text
pixel art game asset sprite sheet, tropical palm tree, thick curved segmented sandy-brown trunk
leaning slightly right with dark ring texture and cross-hatching, crown of 6-7 long arching
vibrant green fronds with yellow-green highlights on top-right, two small coconuts tucked under
fronds, tiny soft ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline,
warm lighting, transparent background, centered bottom-center anchor, sprite sheet horizontal row of 4
identical palms (North front facing | East side profile squashed leaned right | South back mirrored darker
| West side mirrored leaned left), same curved trunk every frame --ar 4:1
```

---

### 6) DEAD TREE — `dead_tree.png` — 56×80 — Haunted Heathland

**Vibe:** Spooky, beautiful, gothic — Halloween heathland star.

```text
pixel art game asset sprite sheet, dead gnarled tree, completely bare leafless silhouette,
twisted grey-brown trunk with deep bark grooves and two main forked skeletal branches
reaching upward like claws, delicate twig fingers on every branch tip, hollow knot on trunk,
no leaves at all, eerie heathland, tiny soft ground shadow, 16-bit retro cozy pixel art,
hand-pixelled crisp outline, transparent background, centered bottom-center anchor,
sprite sheet horizontal row of 4 identical bare trees (North | East side squashed leaned right
lit from right | South back mirrored slightly darker | West mirrored leaned left) --ar 4:1
```

---

### 7) CACTUS — `cactus.png` — 40×64 — Desert Guardian

**Vibe:** Friendly saguaro, two arms, instant Desert theme.

```text
pixel art game asset sprite sheet, classic saguaro cactus, central column with two upward-curved
arms at mid-height, vibrant cactus green with darker green vertical rib shading and soft
top-right highlights, small creamy spines dots on ribs, tiny sandy ground shadow, 16-bit retro
cozy golf tycoon style, hand-pixelled crisp 1px outline, transparent background,
centered bottom-center anchor, sprite sheet horizontal row of 4 identical cacti
(North front | East side squashed leaned right | South back mirrored darker | West mirrored leaned left)
--ar 4:1
```

---

### 8) BUSH — `bush.png` — 40×40 — The Fairway Filler

**Vibe:** Cute, dense, low hemisphere — fills gaps, defines rough.

```text
pixel art game asset sprite sheet, low dense hemispherical bush shrub, two-tone vibrant greens
with lighter top-right tuft highlights and darker underside, compact rounded puff with
3-4 leaf clusters and tiny red berry dots, tiny soft ground shadow, 16-bit retro cozy pixel art,
hand-pixelled crisp 1px outline, transparent background, centered bottom-center anchor,
sprite sheet horizontal row of 4 identical bushes (North | East squashed leaned right | South mirrored darker
| West mirrored leaned left), same puff shape every frame --ar 4:1
```

---

### 9) CATTAILS — `cattails.png` — 32×48 — Marsh Reeds

**Vibe:** Waterside detail, tall thin, whispers of wind.

```text
pixel art game asset sprite sheet, marsh cattails reeds cluster, 5-6 thin upright reed-green stalks
of varying height with 2-3 golden-brown sausage-shaped cattail heads on top, delicate leaf blades
and small drooping seed fluff, waterside plant, tiny soft ground shadow, 16-bit retro cozy pixel art,
hand-pixelled crisp outline, transparent background, centered bottom-center anchor,
sprite sheet horizontal row of 4 identical reed clusters (North front | East side squashed leaned right
| South back mirrored darker | West mirrored leaned left) --ar 4:1
```

---

### 10) FESCUE — `fescue.png` — 32×32 — Links Tussock

**Vibe:** Wispy, wild, linksland rough — straw wind-blown grass.

```text
pixel art game asset sprite sheet, fescue tussock grass tuft, spiky wild straw-green-beige clump
with thin wispy blades splaying outward and lighter tips on top-right, dense base fading to airy tips,
links rough plant, tiny soft ground shadow, 16-bit retro cozy pixel art, hand-pixelled crisp outline,
transparent background, centered bottom-center anchor, sprite sheet horizontal row of 4 identical tufts
(North | East squashed leaned right | South mirrored darker | West mirrored leaned left) --ar 4:1
```

---

### 11) HEATHER — `heather.png` — 32×32 — Moorland Carpet

**Vibe:** Tiny, precious, purple jewel — heathland ground cover.

```text
pixel art game asset sprite sheet, low heather ground cover plant, compact mound of tiny green leaves
with 12-15 scattered small vibrant purple-pink flower dots and lighter top highlights, moorland carpet
plant, tiny soft ground shadow, 16-bit retro cozy pixel art, hand-pixelled crisp outline,
transparent background, centered bottom-center anchor, sprite sheet horizontal row of 4 identical heather
mounds (North | East squashed leaned right | South mirrored darker | West mirrored leaned left) --ar 4:1
```

---

## 5. Seasonal Variant Prompts (Seasons Mod `mods/golf_tycoon.seasons/tree_art/`)

These **replace only the canopy description** in the base prompt. Keep everything else (canvas, layout, style, negative).

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

**Example: Spring Oak Sprite Sheet (64×80 ×4)**

```text
pixel art game asset sprite sheet, spring oak tree, fresh bright lime green young leaves
with 8 tiny pale pink-white blossoms scattered on outer canopy, thick warm brown gnarled trunk,
soft ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline,
transparent background, centered bottom-center anchor, sprite sheet horizontal row of 4 identical trees
(North front | East side squashed 18% leaned 3px right lit from right | South back mirrored darker
| West side mirrored leaned left), same tree every frame, no border --ar 4:1
```

**Example: Fall Maple Sprite Sheet**

```text
pixel art game asset sprite sheet, autumn maple tree, fiery orange-red-gold dense warm fall canopy
with glowing dappled highlights, medium brown trunk, tiny ground shadow, 16-bit retro cozy golf tycoon style,
hand-pixelled, transparent background, centered, sprite sheet horizontal row of 4 identical trees
(North | East squashed leaned right | South mirrored darker | West mirrored leaned left) --ar 4:1
```

**Example: Winter Pine Sprite Sheet**

```text
pixel art game asset sprite sheet, winter snow-capped alpine pine fir tree, triangular tiers with thick
white snow caps on every branch ledge, dark green peeking through snow, narrow brown trunk, tiny snowy
ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled, transparent background, centered
bottom-center anchor, sprite sheet horizontal row of 4 identical snowy pines (North | East | South | West)
--ar 4:1
```

---

## 6. Tool-Specific Tweaks

### Stable Diffusion XL / Flux / Ideogram / Leonardo
- Paste the full block as **Prompt**, Negative Prompt in negative field.
- Use `Euler a`, 32 steps, CFG 7, 1024×256 generation → downscale to target.
- Add trigger words at start: `pixel art, sprite sheet` — these dominate SDXL's attention.
- If trunk drifts, add `ControlNet: canny edge of N view, weight 0.75` for E/S/W consistency.

### Midjourney v6
- Add `--ar 4:1 --v 6 --style raw --s 250 --chaos 4` (low chaos keeps frames identical).
- Use `--no photorealistic, 3d, background, text` rather than a separate negative box.
- Try `repeat` with `::` weights: `oak tree::2 pixel art sprite sheet::2 four views::1.5`
- For tiny foliage (heather/fescue/cattails) add `micro sprite, 32x32 canvas` — MJ tends to over-detail these.

### DALL·E 3 / Firefly / GPT-Image
- Use the **full sentence** variant (no `--ar` tags). Add at end: `Make a horizontal sprite sheet with four equal panels side by side, transparent background, no text. Each panel shows the same tree from a different cardinal direction.`
- Request `pixel art, crisp pixels, no blur` twice — DALL·E loves to smooth.

### Ideogram / Playground
- Enable `Magic Prompt: OFF` (it adds scenery).
- Set `Tile: OFF`, `Background: Transparent`.

---

## 7. Workflow: From Prompt to Engine

```
1. Generate 4× sheet (e.g., oak 256×320 → native 64×80×4)
       │
2. Downscale with NEAREST NEIGHBOR to exact canvas ×4 width
       e.g., PIL:  Image.resize((target_w, target_h), Image.NEAREST)
       │
3. Slice into 4 PNGs:
       oak_n.png = sheet[0:64, 0:80]        (North = shipped source)
       oak_e.png = sheet[64:128, 0:80]      (East  = squashed leaned right, lit right)
       oak_s.png = sheet[128:192, 0:80]     (South = mirrored darker)
       oak_w.png = sheet[192:256, 0:80]     (West  = mirrored squashed leaned left)
       │
4. Drop into:
       assets/sprites/trees/<species>.png        (copy of _n, per docs)
       assets/sprites/trees/<species>_{n,e,s,w}.png
       mods/golf_tycoon.seasons/tree_art/<season>/<species>.png (+ _n/_e/_s/_w via generate.py)
       │
5. Run:  python3 tools/tree_art/generate.py --check   # verifies no stale view
       or python3 tools/tree_art/generate.py           # regenerates _e/_s/_w if you keep N only
```

> **Prefer AI for N only:** The canonical pipeline is AI → N view → `generate.py` derives E/S/W via precise `PROFILES` (squash 0.82, shear ±3px, light gradients). This guarantees `TreeOverlay.SPRITE_BASE_OFFSETS` alignment. The 4-view sheet prompts above bake those transforms in so you can **compare** — pick whichever looks better, but keep N as source of truth.

**Python slicer (one-liner):**

```python
from PIL import Image
sheet = Image.open("sheet_oak.png")  # 256x80
w = sheet.width // 4
for i, facing in enumerate("n e s w".split()):
    sheet.crop((i*w, 0, (i+1)*w, sheet.height)).save(f"oak_{facing}.png")
```

---

## 8. Quick Copy Block — All 11 Species (SDXL Ready)

<details>
<summary>Click to expand: 11-prompt cheat sheet for bulk generation</summary>

```text
# OAK 64x80
pixel art game asset sprite sheet, majestic parkland oak massive dense rounded canopy three greens gnarled brown trunk, ground shadow, 16-bit retro cozy golf tycoon hand-pixelled crisp outline, transparent background centered, sprite sheet horizontal row 4 identical trees N|E squashed leaned right|S mirrored darker|W mirrored leaned left --ar 4:1

# BIRCH 48x80
pixel art game asset sprite sheet, elegant birch pure white trunk black horizontal dashes lime airy canopy, ground shadow, 16-bit retro cozy golf tycoon hand-pixelled crisp outline, transparent background centered, sprite sheet row 4 identical N|E squashed|S mirrored darker|W --ar 4:1

# PINE 48x80
pixel art game asset sprite sheet, conical alpine pine fir triangular 5-6 tiered dark to mint greens narrow brown trunk, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# MAPLE 56x72
pixel art game asset sprite sheet, broad rounded maple warm yellow-green amber canopy medium brown trunk, ground shadow, 16-bit retro cozy hand-pixelled, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# PALM 56x80
pixel art game asset sprite sheet, tropical palm thick curved segmented sandy brown trunk 7 long arching green fronds, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# DEAD_TREE 56x80
pixel art game asset sprite sheet, dead bare gnarled grey-brown tree no leaves skeletal claw branches hollow knot, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# CACTUS 40x64
pixel art game asset sprite sheet, classic saguaro cactus green two arms rib shading, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# BUSH 40x40
pixel art game asset sprite sheet, low dense hemispherical bush two-tone greens berry dots, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# CATTAILS 32x48
pixel art game asset sprite sheet, marsh cattails 6 thin reed stalks 3 golden brown heads, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# FESCUE 32x32
pixel art game asset sprite sheet, fescue tussock straw-green spiky tuft wispy tips, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1

# HEATHER 32x32
pixel art game asset sprite sheet, heather ground cover green mound 15 purple flower dots, ground shadow, 16-bit retro cozy pixel art crisp outline, transparent background centered, sprite sheet row 4 identical N|E|S|W --ar 4:1
```

</details>

---

## 9. Pro Tips for Amazing Results

1. **Lock the trunk.** Add `bottom-center trunk anchor at exact same pixel in every frame` — stops AI drifting the base between views.
2. **Name the light.** `top-right light` + `East lit from right, West lit from left, South darker` gives the engine's shading model.
3. **Say "same tree".** Repeat `same tree silhouette every frame, identical tree` — otherwise AI invents 4 different oaks.
4. **Tiny canvas discipline.** For 32×32 (heather/fescue) add `micro sprite, 32x32, minimal detail` — prevents over-rendering.
5. **No scenery.** `no background, no grass field, no sky` must be explicit; AI wants to place trees in forests.
6. **Generate big, deliver small.** 4× then `NEAREST` downscale preserves pixel crispness and beats native small-res generation.
7. **Seasonal recolor, not reshape.** For seasonal variants, keep `same silhouette and trunk, only canopy color changes` — ensures fall birch is recognizably the same birch.

---

## 10. File Map

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

tools/tree_art/generate.py  ← derives _e/_s/_w from N if you only ship N
tmp_preview/tree_facings.png ← --preview contact sheet of all species
```

*Happy growing — may your fairways be lush and your sprite sheets crisp!*

