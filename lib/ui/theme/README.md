# Theme and motion

Tokens live in `hw_theme.dart`, motion in `hw_motion.dart`, and the shared
widgets in `lib/ui/primitives/` (`hw_glass.dart`, `hw_motion_widgets.dart`,
`hw_open_route.dart`).

## Palette

The colors come from abelnotes.app so the site and the app read as one
product: logo blue `#2A7A9E` as the accent (`#5DB3D6` in dark), slate ink
`#22303A`, chalk and paper neutrals, and the site's "void" blue-black for
dark mode. Shadows are tinted with that void color instead of neutral black.

There are three variants. *Paper* (warm) is the default light theme, *light*
is the cooler chalk one, *dark* lifts elevated surfaces (cards, dock) above
the background rather than sinking them.

Notebook cover colors are stored as ARGB in each notebook, so the cover
palette only changes what new notebooks can pick.

## Type

Instrument Sans, the site's face, is bundled under the SIL Open Font
License (`assets/fonts/InstrumentSans-OFL.txt`, registered in
`LicenseRegistry` in `main.dart`). Bundling it keeps the UI identical on
every Linux distro instead of falling back to whatever the system has.

Roboto Regular (Apache-2.0, `assets/fonts/Roboto-LICENSE.txt`) is bundled
only because the web engine uses it as the global fallback and would
otherwise download it from fonts.gstatic.com on every launch. Glyphs neither
font has (CJK, emoji) still come from Google's Noto fallbacks, on demand.

`HwType` holds the scale. Tracking is set per size: large text is tightened,
small text gets a little air. Values are in logical pixels because Flutter's
`letterSpacing` is not relative to the font size.

## Materials

`HwGlass` is the translucent chrome used by the dock, the tool popup and the
library bar: a blurred and slightly saturated backdrop, a tinted fill, a one
pixel bright top edge and an outer-only shadow (an ordinary shadow would show
through the fill and muddy it). Popups use the `strong` fill so light glass
never sits on light glass. With the system's high-contrast setting the glass
becomes a solid surface with a visible border.

The library bar is clear while the list is at rest and turns into glass only
once content scrolls under it, with blur and fill growing together.

On the web build the glass has no backdrop blur. CanvasKit has no raster
cache, so every frame in which anything moves (a stroke, a scroll, the dock)
re-blurs every glass surface on screen, which is what made the chrome lag in
iPad Safari. The fill becomes opaque instead, as iOS does with Reduce
Transparency, and the shadow uses the normal blur style, the only one Skia
draws analytically. The notebook-open transition does not fade the page in on
the web either, since that costs a full-screen layer per frame; the cover
dissolving on top already hides the page early on.

## Motion

Springs are described the way Apple's design talks describe them, with a
damping ratio (1 means no overshoot) and a response time in seconds.
`hwSpring()` converts that to a Flutter `SpringDescription`.

| Use | Damping | Response |
| --- | --- | --- |
| Indicators, segmented controls, press release | 1.0 | 0.30 s |
| Press down | 1.0 | 0.15 s |
| Tool popup | 1.0 | 0.28 s |
| Notebook open/close | 1.0 | 0.45 s |
| After a throw (dock) | 0.8 | 0.35 s |

Overshoot is only used after a gesture that carried momentum. Animations
start from the value on screen and keep its velocity (`springTo`), so they
can be interrupted and reversed without a jump.

A thrown dock does not snap to the edge nearest where it was let go: its
release velocity is projected forward (`hwProject`, the same exponential
decay as scrolling) and the edge nearest that point wins. Past the screen
edges the drag rubber-bands (`hwRubberband`) instead of stopping dead.

Press feedback (`HwPressable`, and the button pressed state) listens to
pointer-down directly, so it shows without the gesture arena's tap delay.

Every animation checks `MediaQuery.disableAnimations`: with reduced motion
springs jump to their target and the notebook transition becomes a fade.
