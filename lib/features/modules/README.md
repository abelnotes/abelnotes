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
  lasso selection, in the selection's ⋯ menu and in the context menu. The
  action returns a `SelectionOutcome` (`ReplaceInk` or `ActionFailed`) and the
  editor applies it. Modules never touch the canvas state directly, so every
  action is one undo step and a module only has to produce data.
- `builtin_modules.dart` — the catalog of modules compiled into the app:
  circuit tidy-up (`ml/circuits/README.md`).
- `module_registry.dart` — `moduleEntriesProvider` (each module with its
  status) and `selectionActionsProvider` (actions of ready modules). A
  disabled module's runtime provider is never watched, so its model is never
  loaded, and one switched off later is unloaded (runtimes are `autoDispose`).

Settings → Modules lists every module with its status, version and licences,
and a switch stored in `AppSettings.disabledModules` (`modules_disabled`).
The section is hidden when the catalog is empty (on the web, for now). A
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
