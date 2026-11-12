# Circuit recognition

Lasso a hand-drawn circuit, get it back with clean symbols and straight wires.
Offline half (data, detector training, export) lives here; the runtime is
`lib/features/canvas/data/circuit_recognizer/`. What the shipped model is and
what it was trained on: `MODEL_CARD.md`.

## Data and licence

- **CGHD** (DFKI, CC BY 4.0, zenodo.org/records/15333233): 3,269 photos of
  hand-drawn circuits, 59 classes. Commercially usable with attribution.
- CGHD has **no current sources**. `build_v2.py` makes synthetic ones from
  CGHD's own hand-drawn voltage-source rings (interior erased, jittered arrow
  or diamond drawn along the wire axis). A ring check skips boxes whose ring
  isn't there, so no bare arrows get labelled as sources.
- **Handwritten electronics notes**, used with their authors' permission and
  not redistributed: real current sources, transistors and quick notation
  CGHD doesn't have. Vector PDFs of notes render through `extract_pdf_ink.py`
  (grid lines and highlighter dropped).
- **Digitize-HCD** (Mendeley rngcz5wtv8, CC BY 4.0, 1,277 scans by 150+
  drafters) is a benchmark only. A detector trained on it read the rest worse
  (tight zigzags as inductors, empty rings as non-voltage), so the shipped
  model never saw it in training.

## Pipeline

1. `prep_cghd.py` — binarize photos on the max RGB channel (drops blue
   ruling), YOLO labels, split by drafter.
2. `build_v2.py` — dataset: CGHD + synthetic current sources + tiled pages of
   notes (whole documents held out as test with `--test-pages`).
3. `train.py` — YOLO11 with a VRAM cap: a GPU that also drives the desktop can
   freeze the machine when it runs dry.
4. `export_detector.py` — fused model → flat op list + f16 weights (ABLM).
   A numpy executor of the op list is checked against PyTorch before writing;
   the Dart runtime is checked against its test vectors
   (`test/circuit_detector_parity_test.dart`).

Model: YOLO11n (5 MB, ~2.7x faster than 11s at equal error count on held-out
circuits once per-class score floors are set: current sources 0.2, switches
0.4, rest 0.3).

Scale: the detector expects a page width of ~1024 px and ~3.3 px strokes.
Rendering at 768 px lost current sources and added false switches, so the
app rasterizes at 1024.

## Wire rules (`wires.py`, ported to `circuit_graph.dart`)

- Strokes are cut **exactly on box borders** — stored strokes are sparse on
  straight runs, and the last point before a box can be 10+ px short of it.
- Only wire *ends* join (end near another piece = T or L joint), so crossings
  never connect. The detector's `crossover` class is not needed for that.
- Two ends facing each other across ≤ 35 px are one wire: ports drawn as a
  gap, or a terminal "o" drawn inside the wire stroke.
- Small closed strokes (dots, "o") are nodes; dashes are not.
- A ground symbol is one node.
- Only nets that reach a component are wires: unlabelled text, braces and
  arrows stay as drawn.

## Redraw rules

Redrawn: resistors (zigzag, or a rectangle when the drawing's middle is
empty — IEC style / impedance), capacitors, batteries, inductors, diodes,
switches, source rings (the sign or arrow inside gives polarity and
direction), grounds fed from above (a "ground" fed from below is usually a
VDD rail), MOSFETs and BJTs (n/p from the drawn arrow), op-amps. Kept as
drawn: ICs, transformers, polarized capacitors, VSS. Each redrawn part is
laid on the line of the wires reaching it, so wires stay straight.

Before the rules run, the detector's reading is patched where it is known
to fail:
- Coils drawn as cursive loops score low as inductors (or read as a BJT).
  Three or more small loops in a row along one stroke, each closed by the
  stroke crossing itself, alike in size, lined up along an axis, with a
  straight wire running on from the coil, become an inductor; a part read
  across the coil goes, one beside it shortens the coil. On the note and
  photo benches this never fires on writing, port rings or scribbles.
- One part read as two kinds in one place (fet and bjt) keeps its best
  reading; overlapping source kinds are merged as before.
- A low-scored "capacitor" fed from below only is a VDD bar.
- A source ring with three or more straight sides is a diamond: a
  controlled source, drawn as CircuiTikZ's 0.7 R diamond. The detector has
  no class for it (synthetic diamonds were trained as current sources).
  Sides drawn one stroke each count too: a lone side spans ~0.7 radius
  both ways, so the test looks at a run's diagonal, and the "label inside
  the box" rule only applies when the widest stroke is a closed ring.
- A ring split into arcs (a traced picture breaks it where wires meet it)
  is fitted as one circle (least squares, worst arc dropped until all lie
  within 0.15 r, covering 9 of 12 sectors); the circle replaces the box,
  which on prints often slides onto the "V_s" beside it. Arcs left outside
  a redrawn source's box are dropped with it.
- Supply arrows and triangle grounds come out as the symbol drawn, with
  its standard meaning (no guessing per user): an up arrow or triangle read
  as "gnd" (fed from below) is CircuiTikZ's vcc; down, a closed triangle or
  an open "v" is its sground (signal ground, as small-signal notes draw it:
  a quick open "v" is a ground far more often than a VEE arrow); a T bar
  stays a rail, three bars stay a ground. A head must narrow to a tip on the
  stem's line going away from the wire. A head is ink mostly slanted off the
  stem (>= 0.3) with at most one level bar at least half its width; a ground
  has two or more bars, often joined by slanted strokes drawn in one go, so
  the slant alone is not enough. The detector misses small heads at a wire's
  free end, so they are also found in the ink: the end of an upright wire
  capped by a head on both sides of it, narrowing to a tip on its line, with
  nothing but a label past the tip and no part's box over it (an arrow drawn
  on a wire, a transistor's lead, fail those); the stem's other end must meet
  the circuit and the head must not be writing (the "1/" of "1/g_m" passed
  the shape tests). A rail sits on the line of the upright part below it, so
  its stem has no jog.

Shapes made with the shape tool (a filled circle for a source, lines for
wires, a rhombus) are traced as their outlines, so they take part like ink.

Symbols are CircuiTikZ's (`circuitikz` 1.x defaults: american resistor,
cute inductor, american sources, empty diode, `nos` switch, nmos/npn, op
amp), ported from its PGF code (GPL-3.0, see `ACKNOWLEDGMENTS.md`) and
sized in its basic length R = 1.05 x the drawing's median part size. Wires
and symbols are stored as technical strokes: even width, sharp corners, no
pen smoothing. Weights are CircuiTikZ's: wires and leads (`technical`)
0.01 R, as its 0.4 pt on a 1.4 cm R, never under 0.3 page units; part
outlines (`technical_body`) twice that, as its `bipoles/thickness = 2`;
dots and arrow heads `technical_fill`. Outlines end flat as in TikZ; wires
end square so two meeting end to end leave no anti-aliased seam. Points
stay dense and evenly paced at a pressure the fountain pen draws at
baseWidth, so a client predating these tools shows the same lines with its
pen. `test/circuit_render_test.dart` renders fixtures before and after with
the app's renderer for checking by eye (`ABELNOTES_CIRCUIT_SCALE=6` puts R
near 200 px, as a LaTeX figure on screen).

Last pass on the output: a wire's end hair (a turn under 3 px from
snapping to a node a pixel off) goes, and an end within 2 px short of or
past a crossing line meets it exactly; both drew as ticks at nodes.

## Benches

`test/fixtures/circuits/` holds a few synthetic mouse-drawn circuits;
`test/circuit_pipeline_test.dart` runs them with the bundled model.
`test/circuit_batch_test.dart` runs any folder of stroke fixtures
(`ABELNOTES_CIRCUIT_BATCH`, `_OUT`, optionally `ABELNOTES_CIRCUIT_MODEL`) and
`batch_report.py` scores the result. `notes_circuits.py` cuts such fixtures out
of vector PDFs of notes, `photos_to_strokes.py` out of CGHD photos.

## Pictures (`image_ink.dart`, `image_circuit.dart`)

An image's "Recognize circuit" (its ⋯ menu, with the circuits module on)
traces the picture into strokes and runs the same pipeline, with the image
as the page so the circuit fills the detector's input wherever it sits.
The detector reads the picture's ink mask (what the lines are thinned
from, as it saw binarised photos in training), not the thin lines redrawn
at a fixed pen width; the lines are what gets rewritten.
The parts and wires come out redrawn; everything else (labels, notes, what
was not recognised) stays as the picture itself: a new image of the ink
left once the redrawn lines are cut out (their width plus 2.5 px of
fringe), on a clear background, cropped, under the drawing; ink running
off the picture's edge (the table, the sheet's border in a photo) is left
out. On tinted paper every traced line is black ink (it takes the paper's
hue otherwise). Skeletons of serif text looked wrong, the original pixels
do not. One undo step.

Tracing is `photos_to_strokes.py` ported (Zhang-Suen thinning, staircase
removal, junction-split paths, Douglas-Peucker 0.8 px) at a 1600 px long
side. Ink is darkness against the paper level around each pixel (max over
a ~1/25-image window), threshold max(8, min(6 x median, 2 x median + 12)),
because a textbook schematic's anti-aliased wires sit at 235 on 255 next to
120 text and any global threshold loses one or the other. The median is
the noise level: 6 x it is right up to 3 (scans, renders), but a photo of
grid paper or a shadowed page has 8-30, and 6 x that threw the pen away
(cghd on the mask: 0.62 found; 0.85 with this rule, best per image
between 2.5 and 3 x the median). Grey is the darkest channel (keeps
light coloured pen) unless the paper is tinted (median colour chroma > 30:
green paper is as dark as its ink there), then luminance; a noisy picture
(median darkness >= 2, a photo) is blurred 3x3 first, a clean one is not
(blur merged coil loops: recall on notes 0.77 -> 0.69 when always on).
Frames go (rows/columns > 80% ink, long thin pieces and dashes near the
edge). Filled heads (a printed transistor's arrow) thin to a dot, so they
go in as nested outlines, about the ink of a head filled by hand, which
the polarity reader then reads: a head is a thick core of at least
max(10, 1.2 half-width^2) pixels (heads measured 22-70, crossings in bold
text 1-7) grown down the distance slope only (so it stops at the wire or
bar it touches), not round, under 20 half-widths. Each traced line keeps
its ink width (at half the local darkness, so the fringe does not fatten
it) and colour (greys black, coloured pen kept).

Bench (`image_bench.py`, `printed_bench.py`, `test/circuit_image_bench_test.dart`;
`prep_dhcd.py` converts the Digitize-HCD scans it uses): labelled parts found
(any class / right class), detector on the binarised picture itself vs on the
traced ink, and parts redrawn:

| set (30 images; printed 36) | on the picture | on the traced ink | redrawn | redraw precision |
|---|---|---|---|---|
| Digitize-HCD scans | 0.97 / 0.85 | 0.95 / 0.84 | 0.95 / 0.82 | 0.82 |
| handwritten notes, rendered | 0.94 / 0.91 | 0.90 / 0.89 | 0.90 / 0.89 | 0.88 |
| CGHD phone photos (held-out drafters) | 0.87 / 0.81 | 0.83 / 0.78 | 0.83 / 0.77 | 0.73 |
| CircuiTikZ prints, clean / screenshot / downsampled | | | 0.97 of drawn parts, right class | |

Two photos (`drafter_17_C195_D1_P2`, `drafter_3_C33_D1_P1`, 25 of 438 parts)
have labels that do not fit the picture (EXIF-rotated originals), so nothing
finds them: 0.94 is the photo ceiling. `ABELNOTES_IMAGE_DETECT=strokes` runs
the bench on the redrawn lines.

Redrawn "precision" counts only labelled parts: a junction dot read as a
ground (`_withSupplyArrows`) is a false part there but keeps the dot as
drawn, which dropping it does not (tried: 6 of 169 note drawings lost
their dots). Remaining photo failures: coils on thick blurry ink thin to
ladders (`drafter_3_C34_D1_P3`), dim or shadowed ink (`drafter_17_C204_D2_P2`,
left half of the sheet), a thin strip crop (`drafter_3_C31_D1_P2`). Known
gaps: a label touching a part is cut with it (a subscript next to a
capacitor plate), a wire drawn through a label takes a letter.

## Native engine (`packages/circuit_engine`)

The detector's forward pass also exists in C (no dependencies, under
100 KB on Linux, a few tens of KB per Android ABI): the Dart detector
hands it the same op list and weights it runs itself, once, then calls it
per raster and decodes the six head maps as before. Dense convolutions are
im2col strips of 48 output pixels times 4 x 16 register tiles (an AVX2+FMA
clone picked at load time on x86-64 desktop; NEON is ARM's baseline), on
every core through its own thread pool. Same decoded output as Dart to
2e-5 relative, same detections; a 928 x 640 raster went 3.6 s -> 108 ms,
1088 x 832 5.4 s -> 189 ms. The picture bench's mean per image (trace +
detect + rewrite) 5.4 s -> 0.89 s. Where the library is missing the Dart
path runs; ABELNOTES_CIRCUIT_NATIVE=0 forces it. It is an FFI plugin: every
platform's Flutter build compiles the C from source (gcc or clang on Linux,
MSVC on Windows, the NDK on Android, Xcode on Apple), so no binary is
committed. ncnn was measured first: 25 ms with Vulkan, but 20 MB of library
plus 5 MB of model per platform, against this engine's 64 KB and no extra
model.

The picture passes run there too (`packages/circuit_engine/src/image_ink.c`:
resample, darkness, frame and specks, distance, thinning; the leftover mask),
line for line the Dart ones, checked bit for bit
(`test/circuit_engine_parity_test.dart`, on a synthetic picture by default,
on any others in `ABELNOTES_ENGINE_IMAGES`). Images are composited once, then
banded over the cores; the vertical max filter walks rows with one deque per
column. The whole trace (filled heads, Moore outlines, paths split at
junctions, Douglas-Peucker, widths and colours) and rasterizeInk's area
average are there as well; Dart's insertion-ordered sets become ascending
pixel scans and the used-edge set a bit per direction. Trace 450-1420 ms ->
60-190 ms, leftover up to 1.2 s -> 140 ms, identical output on 7 test pictures.
