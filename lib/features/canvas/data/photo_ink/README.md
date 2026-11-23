# Photo to ink

A photo of handwritten paper notes becomes centre-line strokes on the page
(image menu "Convert to ink", or "Photo of notes as ink" in the page menu).
The strokes are ordinary page ink, so the handwriting search indexes them.

`photo_ink.dart` is pure Dart (no Flutter, no FFI): it runs in an isolate on
native platforms and on the main thread on the web. `photo_ink_strokes.dart`
decodes, places the result over the picture's box and picks pen colours.

## Steps
1. **Sheet.** On a 512 px copy, paper = bright and grey (V - 0.8 S, Otsu);
   the largest region's outline is simplified and its 4 longest sides are
   extended to meet, so a shadow or a finger cutting a corner does not move
   it; each side is then refitted to the outline points along it. No quad
   when a side runs along the frame (sheet cropped) or the corners are not
   near right angles: the photo is traced as it is. A found sheet is
   straightened and the result keeps its proportions in the picture's box.
2. **Scale.** The pen width is measured on a 1600 px copy (ridge of the
   distance to paper); the picture is then resized so the pen is about
   6 px wide, the grey upsampled cubic (not linear): on a 1600 px photo the
   gaps inside N, M, E, K are 1-2 px and only survive at this scale (3.5 px
   lost them: OCR words 0.31 -> 0.37 on the lab split).
3. **Paper level.** A grey closing (max then min filter, 6 pen widths)
   removes the ink and keeps shadow edges, unlike a plain max filter, which
   left a dark band along a sun shadow's edge. Measured per channel on a copy
   a few times smaller (it is smooth). Darkness = 1 - grey / paper level.
4. **Not ink.** Highlighter (light, strongly coloured, paper measured over a
   window 3x wider since its bands are wider than the pen) is taken out of
   the ink and traced apart as highlighter strokes, only where the paper
   level is that of the sheet (wood and cloth look tinted against
   themselves). Background far darker than the sheet is dropped.
5. **Threshold.** Hysteresis on darkness (0.30 / 0.55 of the page's ink
   level, its 90th percentile), then a pixel must be at least 0.55 of the
   darkest ink within 2 pen widths: gaps between close strokes and small
   loops (e, a, o) stay open.
6. **Ruling.** Per strip of 1.5% of the page, along the page's dominant
   angle, the median darkness of each row is a profile; rows peaking above
   the strip's own noise floor (median + 6 deviations) are linked across
   neighbouring strips (a line drifts or bends) into chains reaching 40% of
   the page; four or more chains = ruling, both directions. The median
   ignores writing crossing a line; the old full-row mask missed rulings as
   thick as the pen and faint ones under noise (real lined photos kept every
   line). Each chain's darkness and thickness are its medians over the
   strips; its pixels lighter than max(1.4x the line, line + 0.35 of the way
   to the ink) go, ink crossing it stays. A single long ink line (fraction
   bar, box) is not a ruling.
7. **Clean-up.** 3x3 majority, pinholes filled, specks under half a pen
   squared dropped, components touching the frame dropped unless they are as
   thin as the pen (writing cut by the frame stays), nothing traced along
   the frame itself (a grid line or sheet edge there).
8. **Lines.** Ink deeper than 1.5 half pen widths (half = median ridge
   distance) in a component spanning 3 pen widths is a loop the photo filled
   (o, a, e, the bowl of d): a hole is cut there, so it thins to a ring and
   not to a stub (the main OCR loss before). Zhang-Suen skeleton, staircases
   removed; spurs shorter than 0.8 pen widths off a junction pruned; branches
   meeting head-on at a junction are joined (a crossing is two strokes, not
   four); lone dots stay (i dots, punctuation). Gaussian smoothing (1.5 px).
   Paths up to 6 pen widths long (bars, hooks, rings) join a longer path of
   the same colour they touch as a there-and-back detour: strokes stay letter
   sized like pen strokes (traced/true stroke count 1.9 -> 1.0), which the
   search's line grouping needs (it uses the median stroke height).
   Douglas-Peucker 0.4 px. Width = twice the median distance to paper.
   Strokes are ballpoint ink: the search skips technical lines.
9. **Colour.** Each stroke's ink over the paper level, median of its darker
   half, mapped to black / blue / red / green; when one covers 90% of the
   ink, all strokes take it.

## Bench (not in the repo)
Synthetic phone photos with known strokes: ruled and squared paper, a second
ink colour, perspective, shadows, light gradient, blur, noise and JPEG.
Scores in page points: centre-line recall / precision within 1.5 pt, strokes
found, short strokes found (bars, dots, hooks), and words the app's
handwriting search reads back ("OCR words", against the same search on the
true strokes).

| held out (20 pages) | recall | precision | strokes found | short found | OCR words (ceiling 0.50) | page OCR |
|---|---|---|---|---|---|---|
| circuit picture tracer (image_ink) | 0.857 | 0.879 | 0.675 | 0.451 | 0.06 | 0.01 |
| first version | 0.926 | 0.981 | 0.879 | 0.815 | 0.17 | 0.06 |
| this pipeline | 0.937 | 0.996 | 0.935 | 0.887 | 0.33 | 0.14 |

The gap left: letters 10-12 px tall on 1600 px photos (blur closes them),
and pages where the sheet is not found on a light desk (the desk grain is
traced).

Time (AOT, desktop, machine busy): 5-8 s for a 1600 px photo, about 8 s
for a 5 MP one in the app (pen scale 6 px costs about 2x the 3.5 px one).

## Known limits
- Pencil on a grid as dark as the writing: most writing goes with the grid.
- Printed text and screen photos are traced like handwriting (legible but
  stroke-shaped), not turned into text.
- A photo turned 90 degrees is traced sideways: rotate the picture first.
- Rulings on bent paper or printed thicker than usual can stay as lines.
