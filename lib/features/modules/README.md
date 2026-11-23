# Modules

Optional features that plug into fixed extension points instead of being
wired by hand into the editor. Today every module is built in; the same API
is meant to carry external modules later.

## Pieces

- `module_manifest.dart` — what a module is: id, version, licence, the
  permissions it needs, its assets (with their own licence, since model
  weights are often licensed differently from code), what it contributes.
  `ModuleManifest.fromJson` is the parser for a future third-party
  `module.json`, so it rejects anything unknown: unknown permissions or
  contribution kinds, newer API versions, asset paths that could escape the
  module folder, action ids outside the module's own id.
- `selection_action.dart` — the one extension point: an action offered for a
  lasso selection, in the selection's ⋯ menu and in the context menu (the two
  recognizers excepted: they are reached through Recognize). The
  action returns a `SelectionOutcome` (`ReplaceInk` or `ActionFailed`) and the
  editor applies it. Modules never touch the canvas state directly, so every
  action is one undo step and a module only has to produce data.
- `builtin_modules.dart` — the catalog of modules compiled into the app:
  circuit recognition (`ml/circuits/README.md`) and formula recognition
  (`canvas/data/ink_recognizer/`, `ml/README.md`).
- `bundled_model.dart` — copies a model asset to the support folder once,
  with a hash stamp beside it, because the recogniser isolates load by path.
- `module_registry.dart` — `moduleEntriesProvider` (each module with its
  status) and `selectionActionsProvider` (actions of ready modules). A
  disabled module's runtime provider is never watched, so its model is never
  loaded, and one switched off later is unloaded (runtimes are `autoDispose`).

Settings → Modules lists every module with its status, version and licences,
and a switch stored in `AppSettings.disabledModules` (`modules_disabled`).
The section is hidden when the catalog is empty. A
module still in testing sets `AppModule.beta` and shows a Beta chip.

## Manifest

```json
{
  "id": "org.example.stamps",
  "version": "0.2.0",
  "apiVersion": 1,
  "license": "MIT",
  "name": {"en": "Stamps", "it": "Timbri"},
  "description": {"en": "Replaces a selection with a stamp."},
  "permissions": ["selection.read", "selection.write"],
  "contributes": {"selectionActions": ["org.example.stamps.apply"]}
}
```

Ids under `abelnotes.` are reserved for built-ins. `entitlement`
(`free` | `supporter`) is parsed but not enforced: every module is free.

## API freeze

No new extension points until a module needs one. Each one added without a
user is a guess at an API that third parties would then depend on.

## Formula recognition

The lasso action recognises pen strokes and line shapes (fraction bars) as
one expression and swaps them for a `MathElement` (`InsertMath`), fitted to
the ink's box, in its colour, one undo step. A transformer in pure Dart
(`ink_to_latex.dart`, checked against PyTorch by
`test/ink_recognizer_parity_test.dart`) runs on a long-lived isolate; where
packages/circuit_engine is built, its dense layers run in C (`ce_linear`,
about 3x faster). On the web it runs inline in Dart, there are no isolates
(adopted C weights would be views on WebAssembly memory that moves when it grows).

The weights are `assets/models/math_ink.ablm`, listed by name in
pubspec.yaml like the circuit detector. Weights trained on non-commercial
data (MathWriting ink, CROHME) must never go there: the shipped model is
licence-clean, see `ml/MODEL_CARD.md`. `test/ink_model_asset_test.dart`
pins its hash.

## Recognize (router)

The only recognizer entry: first item of the lasso action bar, and in the
context menu, shown for ink while the formula or circuit module is ready. The
region router (`features/search/region_router.dart`, WebAssembly in the
engine's worker on the web) looks at the selected ink and the selection goes
to that module's own action (`recognize_route.dart`), so the outcome, the undo
step and the failure messages are the module's. Text is left alone (it is
searchable, there is no ink-to-text element), a drawing too, each with a short
note. When the top class is under 0.6 or the runner-up within 0.15, or the
router cannot load, a small sheet asks formula / circuit / text. A module
switched off in Settings is named in the note.

The two module actions are not offered on their own. A wrong guess is fixed
from the result's snackbar: "Change" undoes the conversion (only while it is
still the last edit on that page), selects the ink again and opens the same
formula / circuit / text sheet.

On a canvas narrower than 560 px Duplicate moves from the bar into ⋯, so the
bar (Recognize, Copy, Cut, Colour, Thickness, Delete, ⋯, close) fits a phone.
