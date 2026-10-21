# Golf Tycoon — Tree Sprite Sheet Prompt Bible

> **Text-to-Image Prompts for Every Tree Species**
> *Create an amazing 4-view (N / E / S / W) pixel-art sprite sheet for each tree.*
> Covers the 11 base species in `assets/sprites/trees/` + all seasonal variants in `mods/golf_tycoon.seasons/tree_art/` + **one mega-sheet with every species together**.

---

## How to Read This Guide

- Every tree is **authored once** as the north-facing view (`<species>.png`). The tool `tools/tree_art/generate.py` derives the other three angles automatically — but with AI you can now generate **all four views at once** as a sprite sheet.
- Copy the **Copy-Paste Prompt** for your generator (Stable Diffusion XL, Midjourney v6, Flux, Ideogram, DALL·E 3) — then slice the sheet into `tree_n.png`, `tree_e.png`, `tree_s.png`, `tree_w.png`.
- Keep the **Global Style Fragment** + **Negative Prompt** in every generation. Only the per-tree description changes.

**Preview of what you're building — single species (4 frames):**

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

Golf Tycoon is a **cozy, clean, 16-bit-era pixel art** tycoon — think *Stardew Valley* × *Theme Park (1994)* × *A Short Hike*, not photorealism.

### Positive Style Fragment (paste verbatim)

```
pixel art game asset, 16-bit retro cozy golf tycoon style, hand-pixelled,
crisp 1px outline, limited vibrant palette, warm soft lighting from top-right,
centered on canvas, bottom-center trunk anchor on tiny soft elliptical ground shadow,
dithered shading, no anti-aliasing blur, Stardew Valley meets SimGolf,
highly detailed at small resolution, game-ready sprite, ultra-sharp pixels, nearest-neighbor
```

### Background Handling — PICK ONE (see §1a below)

Add **either** of these to the end of every prompt, depending on your generator:

**A) Transparent BG (only if your tool supports it):**
```
isolated on transparent background, no background, alpha channel, transparent PNG
```

**B) Solid Chroma-Key BG (recommended for Midjourney / DALL·E / SDXL / Flux):**
```
isolated on solid flat pure chroma-key green background #00FF6A, even flat color,
no gradient, no shadow except tiny ground oval under trunk, no scenery, no sky, no grass field,
studio sprite on solid color for easy background removal
```

> **Why B is the default:** Midjourney, DALL·E 3, Flux, SDXL, and most Midjourney-style tools **cannot output transparency** — they always fill the background. Don't fight it: ask for a solid, removable color (see §1a) and strip it in one click afterwards. Transparent-native tools (Leonardo `Transparent PNG`, Ideogram `Canvas`, Recraft `Remove BG`) can use variant A.

### Technical Layout Fragment (single species, 4 frames)

```
sprite sheet, single horizontal row of 4 identical trees, four cardinal views:
North front view | East right-side view | South back view | West left-side view,
same tree silhouette in every frame, perfectly aligned ground line and trunk base centered,
equal spacing between frames, no border, no text, no watermark, no labels
```

### Technical Layout Fragment (all 11 species mega-sheet)

```
master sprite sheet contact sheet, grid layout 11 rows × 4 columns, 44 sprites total,
columns are N | E | S | E→W mirrored views, rows top-to-bottom are: oak, birch, pine, maple,
palm, dead_tree, cactus, bush, cattails, fescue, heather — same species in each row with 4
directional views, each row centered with bottom-center trunk anchor and tiny ground shadow,
even spacing between rows and columns, no border, no text, no labels, no scenery
```

> **Tip:** If your generator merges frames, add: `four separate sprites in a row, grid layout 4x1, contact sheet, separated cells with small gap`.

### Universal Negative Prompt (always add)

```
photorealistic, 3d render, CGI, blurry, anti-aliased, gradient mesh, watercolor, oil painting,
sketch, noisy, low-res upscale, background scenery, sky, grass field, clouds, forest, landscape,
multiple different trees blended, text, letters, numbers, watermark, frame, border, vignette,
drop shadow beyond ground oval, asymmetric trunks between frames, different species in same row
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

---

## 3. Master Prompt Template

```
[GLOBAL STYLE FRAGMENT] + [BACKGROUND VARIANT A or B] + [TREE-SPECIFIC DESCRIPTION] + [TECHNICAL LAYOUT FRAGMENT] + --ar 4:1
```

For SDXL / Flux / Ideogram, keep it as one paragraph. For Midjourney, you can weight with `::`.

**MJ weighting example:**
```
pixel art sprite sheet::2 [tree description]::2 four views in a row::1.5 solid green background::1.5 --ar 4:1 --tile --v 6 --style raw --s 250 --no photorealistic, forest, sky
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
pixel art game asset sprite sheet, majestic parkland oak tree with massive dense rounded canopy,
three layered shades of vibrant green with soft dithered highlights on top-right, thick gnarled
warm brown trunk with subtle vertical bark texture and two low forked branches peeking through
leaves, tiny soft elliptical ground shadow under trunk, 16-bit retro cozy golf tycoon style,
hand-pixelled crisp 1px outline, warm soft lighting from top-right, isolated on solid flat
chroma-key green background #00FF6A, even flat color, centered bottom-center anchor,
sprite sheet single horizontal row of 4 identical trees (North front view | East right-side
squashed 18% leaned 3px right lit from right | South back mirrored darker | West left-side
mirrored leaned left), same silhouette every frame, equal spacing, no border, Stardew Valley
meets SimGolf, highly detailed at small resolution --ar 4:1
```
*For transparent-capable tools, swap `isolated on solid flat chroma-key green background #00FF6A, even flat color` → `isolated on transparent background, alpha channel`.*

**Alt Midjourney tags:** `giant rounded oak, storybook, lush dithered canopy, gnarled oak trunk --no acorn, forest background`

---

### 2) BIRCH — `birch.png` — 48×80 — Elegant White Sentinel

**Vibe:** Tall, slender, Scandinavian elegance. The white trunk is the hero.

```text
pixel art game asset sprite sheet, elegant birch tree, slender tall pure white trunk with
crisp horizontal black bark dashes and subtle grey shading, light airy lime-green-yellow canopy
with delicate layered clusters and small dark twig speckles, graceful upright silhouette,
tiny soft ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline,
warm soft lighting from top-right, isolated on solid flat chroma-key green background #00FF6A,
centered bottom-center anchor, sprite sheet single horizontal row of 4 identical trees
(North front | East squashed 18% leaned right lit right | South mirrored darker | West mirrored
leaned left), same tree every frame --ar 4:1
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
isolated on solid flat chroma-key green background #00FF6A, even flat color, centered
bottom-center anchor, sprite sheet single horizontal row of 4 identical trees (North front |
East side squashed 18% leaned 3px right | South back mirrored darker | West side mirrored
leaned left), identical height all frames --ar 4:1
```

**Winter prompt add-on:** `snow-dusted pine, white snow caps on branch tiers, snowy ground shadow, winter`

---

### 4) MAPLE — `maple.png` — 56×72 — Broad Canopy

**Vibe:** Slightly smaller than oak, warmer, friendly shade tree.

```text
pixel art game asset sprite sheet, broad rounded maple tree, warm yellow-green amber canopy
with soft dithered autumnal glow, slightly flatter crown than oak, medium thick brown trunk
with subtle fork, airy leaf clusters with lighter top-right highlights, tiny soft ground shadow,
16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline, isolated on solid flat
chroma-key green background #00FF6A, even flat color, centered bottom-center anchor, sprite sheet
single horizontal row of 4 identical trees (North | East squashed leaned right | South mirrored
darker | West mirrored leaned left) --ar 4:1
```

---

### 5) PALM — `palm.png` — 56×80 — Tropical Vacation

**Vibe:** Instant holiday. Curved, breezy, Desert/Tropical.

```text
pixel art game asset sprite sheet, tropical palm tree, thick curved segmented sandy-brown trunk
leaning slightly right with dark ring texture and cross-hatching, crown of 6-7 long arching
vibrant green fronds with yellow-green highlights on top-right, two small coconuts tucked under
fronds, tiny soft ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline,
warm lighting, isolated on solid flat chroma-key green background #00FF6A, even flat color,
centered bottom-center anchor, sprite sheet horizontal row of 4 identical palms (North front facing |
East side profile squashed leaned right | South back mirrored darker | West side mirrored leaned left),
same curved trunk every frame --ar 4:1
```

---

### 6) DEAD TREE — `dead_tree.png` — 56×80 — Haunted Heathland

**Vibe:** Spooky, beautiful, gothic — Halloween heathland star.

```text
pixel art game asset sprite sheet, dead gnarled tree, completely bare leafless silhouette,
twisted grey-brown trunk with deep bark grooves and two main forked skeletal branches
reaching upward like claws, delicate twig fingers on every branch tip, hollow knot on trunk,
no leaves at all, eerie heathland, tiny soft ground shadow, 16-bit retro cozy pixel art,
hand-pixelled crisp outline, isolated on solid flat chroma-key green background #00FF6A,
centered bottom-center anchor, sprite sheet horizontal row of 4 identical bare trees
(North | East side squashed leaned right lit from right | South back mirrored slightly darker |
West mirrored leaned left) --ar 4:1
```

---

### 7) CACTUS — `cactus.png` — 40×64 — Desert Guardian

**Vibe:** Friendly saguaro, two arms, instant Desert theme.

```text
pixel art game asset sprite sheet, classic saguaro cactus, central column with two upward-curved
arms at mid-height, vibrant cactus green with darker green vertical rib shading and soft
top-right highlights, small creamy spines dots on ribs, tiny sandy ground shadow, 16-bit retro
cozy golf tycoon style, hand-pixelled crisp 1px outline, isolated on solid flat chroma-key
green background #00FF6A, even flat color, centered bottom-center anchor, sprite sheet
horizontal row of 4 identical cacti (North front | East side squashed leaned right |
South back mirrored darker | West mirrored leaned left) --ar 4:1
```

---

### 8) BUSH — `bush.png` — 40×40 — The Fairway Filler

**Vibe:** Cute, dense, low hemisphere — fills gaps, defines rough.

```text
pixel art game asset sprite sheet, low dense hemispherical bush shrub, two-tone vibrant greens
with lighter top-right tuft highlights and darker underside, compact rounded puff with
3-4 leaf clusters and tiny red berry dots, tiny soft ground shadow, 16-bit retro cozy pixel art,
hand-pixelled crisp 1px outline, isolated on solid flat chroma-key green background #00FF6A,
centered bottom-center anchor, sprite sheet horizontal row of 4 identical bushes
(North | East squashed leaned right | South mirrored darker | West mirrored leaned left),
same puff shape every frame --ar 4:1
```

---

### 9) CATTAILS — `cattails.png` — 32×48 — Marsh Reeds

**Vibe:** Waterside detail, tall thin, whispers of wind.

```text
pixel art game asset sprite sheet, marsh cattails reeds cluster, 5-6 thin upright reed-green stalks
of varying height with 2-3 golden-brown sausage-shaped cattail heads on top, delicate leaf blades
and small drooping seed fluff, waterside plant, tiny soft ground shadow, 16-bit retro cozy pixel art,
hand-pixelled crisp outline, isolated on solid flat chroma-key green background #00FF6A,
centered bottom-center anchor, sprite sheet horizontal row of 4 identical reed clusters
(North front | East side squashed leaned right | South back mirrored darker |
West mirrored leaned left) --ar 4:1
```

---

### 10) FESCUE — `fescue.png` — 32×32 — Links Tussock

**Vibe:** Wispy, wild, linksland rough — straw wind-blown grass.

```text
pixel art game asset sprite sheet, fescue tussock grass tuft, spiky wild straw-green-beige clump
with thin wispy blades splaying outward and lighter tips on top-right, dense base fading to airy tips,
links rough plant, tiny soft ground shadow, 16-bit retro cozy pixel art, hand-pixelled crisp outline,
isolated on solid flat chroma-key green background #00FF6A, centered bottom-center anchor,
sprite sheet horizontal row of 4 identical tufts (North | East squashed leaned right |
South mirrored darker | West mirrored leaned left) --ar 4:1
```

---

### 11) HEATHER — `heather.png` — 32×32 — Moorland Carpet

**Vibe:** Tiny, precious, purple jewel — heathland ground cover.

```text
pixel art game asset sprite sheet, low heather ground cover plant, compact mound of tiny green leaves
with 12-15 scattered small vibrant purple-pink flower dots and lighter top highlights, moorland carpet
plant, tiny soft ground shadow, 16-bit retro cozy pixel art, hand-pixelled crisp outline,
isolated on solid flat chroma-key green background #00FF6A, centered bottom-center anchor,
sprite sheet horizontal row of 4 identical heather mounds (North | East squashed leaned right |
South mirrored darker | West mirrored leaned left) --ar 4:1
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
pixel art game asset sprite sheet, spring oak tree, fresh bright lime green young leaves
with 8 tiny pale pink-white blossoms scattered on outer canopy, thick warm brown gnarled trunk,
soft ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled crisp 1px outline,
isolated on solid flat chroma-key green background #00FF6A, even flat color, centered
bottom-center anchor, sprite sheet horizontal row of 4 identical trees (North front | East side
squashed 18% leaned 3px right lit from right | South back mirrored darker | West side mirrored
leaned left), same tree every frame, no border --ar 4:1
```

**Example: Fall Maple Sprite Sheet**

```text
pixel art game asset sprite sheet, autumn maple tree, fiery orange-red-gold dense warm fall canopy
with glowing dappled highlights, medium brown trunk, tiny ground shadow, 16-bit retro cozy golf
tycoon style, hand-pixelled, isolated on solid flat chroma-key green background #00FF6A,
centered, sprite sheet horizontal row of 4 identical trees (North | East squashed leaned right |
South mirrored darker | West mirrored leaned left) --ar 4:1
```

**Example: Winter Pine Sprite Sheet**

```text
pixel art game asset sprite sheet, winter snow-capped alpine pine fir tree, triangular tiers with thick
white snow caps on every branch ledge, dark green peeking through snow, narrow brown trunk, tiny snowy
ground shadow, 16-bit retro cozy golf tycoon style, hand-pixelled, isolated on solid flat chroma-key
green background #00FF6A, centered bottom-center anchor, sprite sheet horizontal row of 4 identical
snowy pines (North | East | South | West) --ar 4:1
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
# OAK 64x80 — solid green for easy key
pixel art game asset sprite sheet, majestic parkland oak massive dense rounded canopy three greens gnarled brown trunk, ground shadow, 16-bit retro cozy golf tycoon hand-pixelled crisp outline, isolated on solid flat chroma-key green background #00FF6A centered, sprite sheet horizontal row 4 identical trees N|E squashed leaned right|S mirrored darker|W mirrored leaned left --ar 4:1

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
