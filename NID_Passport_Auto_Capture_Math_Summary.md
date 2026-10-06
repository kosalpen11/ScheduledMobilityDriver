# NID & Passport Auto-Capture Math Summary

## 1. Document Aspect Ratio

For a quadrilateral with four corners:

- `TL` = top-left
- `TR` = top-right
- `BR` = bottom-right
- `BL` = bottom-left

Euclidean distance:

\[
d(P_1,P_2)=\sqrt{(x_2-x_1)^2+(y_2-y_1)^2}
\]

Edge lengths:

\[
e_{top}=d(TL,TR)
\]

\[
e_{bottom}=d(BL,BR)
\]

\[
e_{left}=d(TL,BL)
\]

\[
e_{right}=d(TR,BR)
\]

Average opposite edges:

\[
W=rac{e_{top}+e_{bottom}}{2}
\]

\[
H=rac{e_{left}+e_{right}}{2}
\]

Orientation-independent aspect:

\[
oxed{
A=rac{\min(W,H)}{\max(W,H)}
}
\]

Cambodia NID:

\[
A_{NID}=rac{227}{359}pprox0.632
\]

Passport:

\[
A_{passport}pprox0.686
\]

---

## 2. Aspect Score

\[
oxed{
S_{aspect}
=
\max\left(
0,
1-rac{|A-A_{target}|}{T}
ight)
}
\]

Where:

- \(A\) = measured aspect
- \(A_{target}\) = expected document aspect
- \(T\) = tolerated deviation

---

## 3. Rectangle Area

\[
oxed{
Area=width	imes height
}
\]

Use it to reject tiny candidates, rank candidates, and detect sudden size changes.

---

## 4. Intersection over Union — IoU

\[
oxed{
IoU(A,B)=
rac{|A\cap B|}
{|A|+|B|-|A\cap B|}
}
\]

Typical tracking rule:

\[
oxed{
IoU(Q_t,Q_{t-1})\ge0.50
}
\]

Interpretation:

- `1.0` = same rectangle
- `0.8` = very similar
- `0.5` = acceptable continuity
- `0.0` = unrelated

---

## 5. Area Continuity

\[
oxed{
R_A=rac{Area_t}{Area_{t-1}}
}
\]

Recommended range:

\[
oxed{
0.67\le R_A\le1.50
}
\]

---

## 6. Candidate Ranking Score

\[
oxed{
Score(Q)=
w_cS_{confidence}
+w_aS_{aspect}
+w_gS_{guide}
+w_sS_{size}
+w_tS_{continuity}
+w_pS_{anchor}
-P_{boundary}
}
\]

Example:

\[
oxed{
Score=
0.15C+
0.15A+
0.20S+
0.15G+
0.30T+
0.05P-
B
}
\]

---

## 7. Guide Coverage

\[
oxed{
G=
rac{Area(Document\cap Guide)}
{Area(Document)}
}
\]

Recommended:

\[
oxed{
G\ge0.70
}
\]

and:

\[
oxed{
centroid(Document)\in Guide
}
\]

---

## 8. Document Centroid

\[
oxed{
C_x=
rac{x_{TL}+x_{TR}+x_{BR}+x_{BL}}{4}
}
\]

\[
oxed{
C_y=
rac{y_{TL}+y_{TR}+y_{BR}+y_{BL}}{4}
}
\]

---

# Motion & Stability

## 9. Corner Displacement

\[
d_i=
\sqrt{
(x_{i,t}-x_{i,t-1})^2+
(y_{i,t}-y_{i,t-1})^2
}
\]

\[
oxed{
D_{raw}=\max_i d_i
}
\]

Normalize by document diagonal:

\[
oxed{
M_{raw}=rac{D_{raw}}{D_q}
}
\]

---

## 10. Document Diagonal

\[
D_1=d(TL,BR)
\]

\[
D_2=d(TR,BL)
\]

\[
oxed{
D_q=rac{D_1+D_2}{2}
}
\]

---

## 11. EMA Smoothing

\[
oxed{
S_t=
S_{t-1}
+
lpha(X_t-S_{t-1})
}
\]

\[
oxed{
lpha=1-e^{-\Delta t/	au}
}
\]

---

## 12. Median-of-Three Motion

\[
oxed{
M_{median}=median(m_0,m_1,m_2)
}
\]

---

## 13. Rolling Mean Motion

\[
oxed{
ar M=
rac{M_0+M_1+M_2+M_3+M_4}{5}
}
\]

\[
oxed{
M_{peak}=\max(M_0,\ldots,M_4)
}
\]

---

## 14. Anchor Drift

\[
oxed{
D_{anchor}
=
\max_i
rac{
d(Q_{t,i},Q_{0,i})
}{
D_q
}
}
\]

---

## 15. Stability Rule

\[
oxed{
Stable=
M_{raw}\le T_r
\land
M_{corner}\le T_c
\land
D_{anchor}\le T_a
}
\]

Also require:

\[
oxed{
N_{stable}\ge N_{required}
}
\]

and:

\[
oxed{
t_{now}-t_{start}\ge T_{minimum}
}
\]

Example:

- 5 consecutive valid samples
- minimum stable duration ≈ 450 ms

---

# Live → Still Capture

## 16. Still-vs-Live Quad Distance

\[
oxed{
D(Q_s,Q_l)
=
\max_i
\sqrt{
(x_{s,i}-x_{l,i})^2+
(y_{s,i}-y_{l,i})^2
}
}
\]

Recommended:

\[
oxed{
D\le0.05
}
\]

Decision:

\[
D\le0.05
\Rightarrow
	ext{still quad agrees with live}
\]

\[
D>0.05
\Rightarrow
	ext{prefer mapped stable live quad}
\]

---

## 17. Still-vs-Live Box Match

\[
oxed{
R_h=
rac{
Area(Still\cap Hint)
}{
Area(Hint)
}
}
\]

Recommended:

\[
oxed{
R_h\ge0.70
}
\]

and:

\[
oxed{
IoU(Still,Hint)\ge0.50
}
\]

---

# Orientation

## 18. Preview Landscape Decision

After mapping Vision corners into preview coordinates:

\[
H_p=
rac{
d(TL,TR)+d(BL,BR)
}{2}
\]

\[
V_p=
rac{
d(TL,BL)+d(TR,BR)
}{2}
\]

Then:

\[
oxed{
Landscape=H_p>V_p
}
\]

Only do this after Vision coordinates are transformed into the same coordinate system as the preview.

---

## 19. Orientation Classification Score

For:

\[
r\in\{0^\circ,90^\circ,180^\circ,270^\circ\}
\]

\[
oxed{
S_r=
w_tT_r+
w_fF_r+
w_lL_r
}
\]

Example:

\[
oxed{
S_r=
0.60T_r+
0.25F_r+
0.15L_r
}
\]

Choose:

\[
oxed{
r^*=rg\max_r S_r
}
\]

Reject uncertain orientation if:

\[
oxed{
S_{best}-S_{second}<0.10
}
\]

---

# Perspective Crop / Homography

## 20. Homography

Map:

\[
TL,TR,BR,BL
\]

to:

\[
(0,0),(W,0),(W,H),(0,H)
\]

\[
oxed{
x'=
rac{
h_{11}x+h_{12}y+h_{13}
}{
h_{31}x+h_{32}y+1
}
}
\]

\[
oxed{
y'=
rac{
h_{21}x+h_{22}y+h_{23}
}{
h_{31}x+h_{32}y+1
}
}
\]

\[
H=
egin{bmatrix}
h_{11}&h_{12}&h_{13}\
h_{21}&h_{22}&h_{23}\
h_{31}&h_{32}&1
\end{bmatrix}
\]

On iOS this maps conceptually to `CIPerspectiveCorrection`.

---

# Image Quality

## 21. Composite Quality Score

\[
oxed{
Q=
w_mS_{motion}
+w_pS_{position}
+w_cS_{card}
+w_sS_{sharp}
+w_lS_{luma}
}
\]

Example:

\[
oxed{
Q=
0.30S_{motion}
+
0.25S_{position}
+
0.20S_{card}
+
0.15S_{sharp}
+
0.10S_{luma}
}
\]

---

## 22. Highlight / Clipping Score

\[
f_{clip}
=
rac{
\#pixels\ge250
}{
N
}
\]

\[
oxed{
S_{glare}
=
clamp(1-6f_{clip},0,1)
}
\]

---

## 23. Mean Luminance

\[
oxed{
L=
rac{1}{N}
\sum_{i=1}^{N}I_i
}
\]

Example valid range:

\[
oxed{
45\le L\le240
}
\]

---

# Performance

## 24. Live Vision Pixel Reduction

Camera:

\[
1128	imes1504=1,696,512
\]

Live Vision:

\[
360	imes480=172,800
\]

Reduction:

\[
oxed{
R=
rac{1,696,512}{172,800}
pprox9.8
}
\]

---

## 25. Vision Frequency

For:

\[
T=0.12s
\]

\[
oxed{
f=rac1Tpprox8.3Hz
}
\]

Recommended:

```text
Camera: 30/60 FPS
        ↓
Cheap luma/motion
        ↓
Vision: ~8 Hz
        ↓
Track/interpolate quad
        ↓
Stable
        ↓
Full-resolution capture
```

---

# Full Pipeline

```text
Camera
  ↓
Vision candidate detection
  ↓
Candidate ranking
  ↓
Aspect validation
  ↓
Size / area validation
  ↓
Guide validation
  ↓
Boundary rejection
  ↓
Track continuity / IoU
  ↓
Motion + anchor drift
  ↓
Stable duration
  ↓
READY
  ↓
Full-resolution capture
  ↓
Live → still coordinate mapping
  ↓
Still-vs-live quad matching
  ↓
Best quad selection
  ↓
Perspective correction
  ↓
Final orientation normalization
  ↓
Quality validation
  ↓
Final cropped document
```

## Valid Document

\[
oxed{
ValidDocument=
AspectOK
\land
SizeOK
\land
AreaOK
\land
GuideOK
\land
BoundaryOK
}
\]

## Valid Track

\[
oxed{
TrackOK=
ValidDocument
\land
IoU\ge0.50
}
\]

## Ready to Capture

\[
oxed{
Ready=
TrackOK
\land
MotionOK
\land
CornerStepOK
\land
AnchorDriftOK
\land
StableTimeOK
}
\]

## Final Crop Quad

\[
oxed{
CropQuad=
egin{cases}
Q_{still}, & D(Q_s,Q_l)\le0.05\
Q_{live}, & D(Q_s,Q_l)>0.05\
arnothing, & 	ext{neither valid}
\end{cases}
}
\]

## Final Output

\[
oxed{
FinalImage=
QualityCheck(
Orientation(
Homography(CropQuad)
))
}
\]

---

# Document-Specific Constants

| Property | Cambodia NID | Passport |
|---|---:|---:|
| Physical orientation | Landscape | Portrait/page |
| Short/long target aspect | ~0.632 | ~0.686 |
| Live tracking | Same pipeline | Same pipeline |
| Stability | Same math | Same math |
| Perspective correction | Same math | Same math |
| Final orientation | NID landscape | Passport page orientation |

The main difference between NID and Passport should be document-specific geometry/configuration. Detection, tracking, stability, live-to-still matching, homography, and quality should share the same overall mathematical model.
