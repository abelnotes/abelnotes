import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';

import 'builtin_modules.dart';
import 'selection_action.dart';

enum ModuleStatus { ready, loading, unavailable, disabled }

class ModuleEntry {
  const ModuleEntry(this.module, this.status, this.actions);
  final AppModule module;
  final ModuleStatus status;

  /// Contributed actions; empty unless [status] is ready.
  final List<SelectionAction> actions;
}

/// Overridable in tests.
final moduleCatalogProvider = Provider<List<AppModule>>((ref) => builtinModules);

/// Every known module with its live status. A disabled module's runtime is
/// never watched, so its model is not loaded.
final moduleEntriesProvider = Provider<List<ModuleEntry>>((ref) {
  final disabled = ref.watch(appSettingsProvider.select((s) => s.disabledModules));
  return [
    for (final m in ref.watch(moduleCatalogProvider))
      if (disabled.contains(m.manifest.id))
        ModuleEntry(m, ModuleStatus.disabled, const [])
      else
        switch (m.runtime == null ? const AsyncData<Object?>(true) : ref.watch(m.runtime!)) {
          AsyncData(value: null) || AsyncError() =>
            ModuleEntry(m, ModuleStatus.unavailable, const []),
          AsyncData() => ModuleEntry(m, ModuleStatus.ready, m.actions(ref)),
          _ => ModuleEntry(m, ModuleStatus.loading, const []),
        },
  ];
});

final selectionActionsProvider = Provider<List<SelectionAction>>((ref) => [
      for (final e in ref.watch(moduleEntriesProvider)) ...e.actions,
    ]);
