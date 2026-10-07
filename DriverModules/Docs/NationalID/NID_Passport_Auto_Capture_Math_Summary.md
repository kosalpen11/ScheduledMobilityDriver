# NID & Passport Auto-Capture — Complete Mathematical Specification

## 1. Constants

```
documentAspectRatio  = 359 / 227 ≈ 1.582   (NID ID-1 card)
passportAspectRatio  = 287 / 418 ≈ 0.687
sampleW = 256,  sampleH = 162               (live-frame analysis sample)
stillMin  = 1000.0                           (normal still sharpness floor)
liveMin   =   80.0                           (live-frame sharpness floor)
readyMin  = 8000.0                           (focus gate, live frames)
α         =    0.35                          (EMA decay factor)
```

---

## 2. Guide Rectangle

Given image size (W, H) and target ratio r = w/h:

```
if W/H > r:   guideW = H·r,  guideH = H
else:         guideW = W,    guideH = W/r

guideLeft = (W − guideW) / 2
guideTop  = (H − guideH) / 2
```

---

## 3. Luma Conversion (BT.601 approximation)

**BGRA** (iOS camera stream, index order B G R _):
```
Y = (29·B + 150·G + 77·R) >> 8
```

**RGB** (decoded JPEG still):
```
Y = (77·R + 150·G + 29·B) >> 8
```

Coefficients ≈ 0.114 R + 0.587 G + 0.299 B (integer-shifted).

---

## 4. Sharpness — Laplacian Variance

For pixel at index i in a W×H luma buffer:

```
L[i] = 4·Y[i] − Y[i−1] − Y[i+1] − Y[i−W] − Y[i+W]

μ  = (1/N) Σ L[i]
σ² = (1/N) Σ L[i]² − μ²      ← sharpness score
```

Range: 0 (flat/blurry) → ~100 000 (sharp full-res still).

---

## 5. Motion Sample — 3×3 Box Filter

Reduces sensor noise before inter-frame comparison.

**Horizontal pass** (output width W−2):
```
H[y, x] = Y[y, x] + Y[y, x+1] + Y[y, x+2]
```

**Vertical pass** (output (W−2) × (H−2)):
```
M[y, x] = ( H[y,x] + H[y+1,x] + H[y+2,x] ) / 9
```

---

## 6. Frame Motion

Given previous motion sample P and current C (same size N):

```
δ = (1/N) Σ (C[i] − P[i])          ← uniform exposure offset removed

motion = (1/N) Σ |C[i] − P[i] − δ|
```

Range: 0 (identical frames) → ~50+ (fast movement).
Gate: rawMotion > 8.0 → high-motion frame.

---

## 7. Edge Detection

For each of the 4 sides, scan candidate lines near the guide perimeter.

**Search range:** center c ∈ {3 … ⌊normalSize × 0.20⌋} pixels from the edge.
**Angles:** θ ∈ {−12°, −10°, …, +12°} (2° steps, 13 candidates).

For each (c, θ):
```
slope     = tan(θ · π/180)
intercept = position − slope · (tangentSize/2)
```

For 40 sample points along the scan line (t = tangent coordinate):
```
t       = tangentSize · (0.22 + 0.56 · i/39)
n       = slope · t + intercept          ← normal coordinate
delta   = Y[after] − Y[before]           (±2 px offset in normal direction)

positive++  if delta ≥  18
negative++  if delta ≤ −18
strength += |delta|.clamp(0, 100)
```

**Acceptance** (consistent polarity):
```
support = max(positive, negative) / 40

if support < 0.85 → reject this candidate

score = 100 · support + strength/40
```

**Best line** = argmax score.

**Sub-pixel refinement** — refit using actual strongest-gradient positions:
```
slope_fit     = Σ(t − t̄)(n − n̄) / Σ(t − t̄)²
intercept_fit = n̄ − slope_fit · t̄
```

Accept fit if inliers (residual ≤ 1.5 px) ≥ 34.

---

## 8. Corner Intersection

**Vertical edge** (xv): x = slopeᵥ · y + iceptᵥ
**Horizontal edge** (yh): y = slopeₕ · x + iceptₕ

```
x = (slopeᵥ · iceptₕ + iceptᵥ) / (1 − slopeᵥ · slopeₕ)
y = slopeₕ · x + iceptₕ
```

---

## 9. Geometry Validation

```
topW    = ‖corner₁ − corner₀‖
bottomW = ‖corner₂ − corner₃‖
leftH   = ‖corner₃ − corner₀‖
rightH  = ‖corner₂ − corner₁‖

cardW   = (topW + bottomW) / 2
cardH   = (leftH + rightH) / 2
ratio   = cardW / cardH
```

Reject if any of:
```
cardW < 0.82 · sampleW
cardH < 0.78 · sampleH
|ratio / documentAspectRatio − 1| > 0.12
min(topW,  bottomW) / max(topW,  bottomW) < 0.80
min(leftH, rightH)  / max(leftH, rightH)  < 0.80
```

---

## 10. Point-in-Quad (Winding Test)

For clockwise corner order, point P is inside iff for every edge A → B:

```
cross(B−A, P−A) = (B.x−A.x)(P.y−A.y) − (B.y−A.y)(P.x−A.x) ≥ 0

containsRect(r) = all four corners {TL, TR, BL, BR} satisfy the above.
```

---

## 11. Quad Distance

```
distanceTo(Q₁, Q₂) = max_{i ∈ {0,1,2,3}} ‖Q₁[i] − Q₂[i]‖
```

Euclidean distance in normalised [0,1]² coordinates.

---

## 12. Projective Transform

Given quad corners p₀ (TL), p₁ (TR), p₂ (BR), p₃ (BL):

```
dx₁ = p₁.x−p₂.x,  dx₂ = p₃.x−p₂.x,  dx₃ = p₀.x−p₁.x+p₂.x−p₃.x
dy₁ = p₁.y−p₂.y,  dy₂ = p₃.y−p₂.y,  dy₃ = p₀.y−p₁.y+p₂.y−p₃.y

det = dx₁·dy₂ − dx₂·dy₁

g = (dx₃·dy₂ − dx₂·dy₃) / det
h = (dx₁·dy₃ − dx₃·dy₁) / det

a = p₁.x − p₀.x + g·p₁.x
b = p₃.x − p₀.x + h·p₃.x,  c = p₀.x
d = p₁.y − p₀.y + g·p₁.y
e = p₃.y − p₀.y + h·p₃.y,  f = p₀.y
```

**Forward map** (u, v) → (x, y):
```
denom = g·u + h·v + 1
x = (a·u + b·v + c) / denom
y = (d·u + e·v + f) / denom
```

(u,v) = (0,0) → TL,  (1,0) → TR,  (1,1) → BR,  (0,1) → BL.

---

## 13. Quality Assessment (per patch)

**Patches:** OCR text-region rects, or fallback 2×3 grid:
```
row ∈ {0,1},  col ∈ {0,1,2}
rect = [ 0.08+col·0.28,  0.12+row·0.38,  0.26,  0.34 ]   (left, top, w, h)
```

**Per patch:**
```
score   = Var(L)      (Laplacian variance, §4)
clipped = count of pixels with Y ≥ clippingLuma
glare   = (clipped / patchPixels) > 0.25
```

clippingLuma: 248 (BGRA/JPEG full-range), 235 (YUV video-range Android).

**Blurry decision:**
```
if OCR regions:  enoughSharp = validPatches ≥ 3  AND  sharpPatches = validPatches
if grid:         enoughSharp = validPatches ≥ 6  AND  sharpPatches ≥ 4

where sharpPatches = count(score ≥ minimumSharpness).
```

**Output flags:**
```
tooDark   = meanLuma < 25  OR  any patch mean < 25 (when using OCR regions)
tooBright = meanLuma > maximumMeanLuma   (235 BGRA / 225 YUV)
glare     = any patch has > 25% clipped
blurry    = NOT enoughSharp
acceptable = NOT (tooDark OR tooBright OR glare OR blurry)
```

---

## 14. EMA Sharpness (live frame)

```
S̃[0] = S[0]
S̃[t] = α · S[t] + (1−α) · S̃[t−1]       α = 0.35
```

Reset to null on frame gap (> 300 ms).

**Focus gate:**
```
focusOk = S[t] ≥ 8000
```

---

## 15. EMA CornerStep + Freeze

```
rawBoxMotion[t] = distanceTo(boundary[t], prevBoundary[t−1])   if both exist
                = ∞                                              otherwise

rawMotionHigh = hadPreviousFrame  AND  rawMotion[t] > 8.0
```

**Freeze rule:**
```
if NOT rawMotionHigh:
    prevBoundary ← boundary[t]
    ẽ[t] = rawBoxMotion[t].isFinite
           ? (ẽ[t−1] == null ? rawBoxMotion[t]
                              : α·rawBoxMotion[t] + (1−α)·ẽ[t−1])
           : null
else:
    if boundary[t] == null: prevBoundary ← null
    ẽ[t] ← null                           ← reset EMA

effectiveCornerStep = ẽ[t] ?? ∞
```

Reset ẽ and prevBoundary also on gap.

---

## 16. Capture Stability Gate

**Thresholds:**

| Symbol | Value    |
|--------|----------|
| M_max  | 8.0      |
| C_max  | 0.018    |
| D_max  | 0.015    |
| L_max  | 12.0     |
| F_req  | 5 frames |
| T_req  | 450 ms   |

**Blocker** (first match wins):
```
1. qualityOrPresence   if NOT eligible
2. frameGap            if Δt > 300 ms
3. missingBoundary     if boundary = null
4. rawMotion           if rawMotion > M_max
5. cornerStep          if ẽ > C_max
6. cornerDrift         if distanceTo(anchor) > D_max
7. lumaDrift           if motion(anchorPixels, pixels) > L_max
8. null                (all pass)
```

On any blocker: frames = 0,  holdMs = 0,  anchor = null.

**Progress:**
```
progress = min( frames/F_req,  holdMs/T_req )  ∈ [0, 1]
```

**Ready:**
```
ready = (blocker = null)  AND  (frames ≥ 5)  AND  (holdMs ≥ 450)
```

---

## 17. UI Vote Filter (guidance labels)

Prevents single-frame flicker on guidance text:

```
vote[t] = clamp(vote[t−1] + (flag[t] ? +1 : −1),  −3,  +3)

display = true   if vote ≥  2
        = false  if vote ≤ −2
        = display[t−1]  otherwise
```

---

## 18. Output Crop — Projective Sampling

**Card pixel dimensions** (in guide-pixel space):

```
edgeLen(a, b) = ‖((a.x−b.x)·guideW,  (a.y−b.y)·guideH)‖

outW = floor( (edgeLen(TL,TR) + edgeLen(BL,BR)) / 2 )
outH = round( outW / documentAspectRatio )
```

**Padding:** pad = 16 px on all sides → totalW = outW + 2·pad, totalH = outH + 2·pad.

For each output pixel (ox, oy):
```
u = (ox − pad) / max(1, outW − 1)
v = (oy − pad) / max(1, outH − 1)

(gx, gy) = projection.map(u, v)        (§12)

srcX = guidePadX + gx · (guideW − 1)
srcY = guidePadY + gy · (guideH − 1)
```

Sample cropped at (srcX, srcY) with bilinear interpolation.

---

## 19. Still Image Validation Thresholds

**Normal image:**

| Scale   | minimumSharpness (per patch) |
|---------|------------------------------|
| 256×162 | 1000                         |
| 512×324 | 250                          |

**Flash image** (skipGlare = true):

| Scale   | minimumSharpness |
|---------|------------------|
| 256×162 | 1000 × 0.20 = 200|
| 512×324 | 120              |

**Checks skipped for flash:** glare, blurry, moved (distanceTo > 0.025), textRegions containment.
If boundary detection fails for flash: fall back to expectedBoundary (pre-capture live-frame quad).
**Still enforced for flash:** tooDark, tooBright.
