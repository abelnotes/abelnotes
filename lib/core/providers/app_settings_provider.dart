import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Library sort strategies.
enum LibrarySortMode {
  modifiedDesc, // last-edited first (default)
  modifiedAsc,
  titleAsc,
  titleDesc,
  createdDesc,
  createdAsc,
  colorGroup, // group by cover color
}

extension LibrarySortModeLabel on LibrarySortMode {
  /// Localized label — callers pass `AppLocalizations.of(context)`.
  String labelOf(AppLocalizations l10n) {
    switch (this) {
      case LibrarySortMode.modifiedDesc: return l10n.nbSortModifiedDesc;
      case LibrarySortMode.modifiedAsc: return l10n.nbSortModifiedAsc;
      case LibrarySortMode.titleAsc: return l10n.nbSortTitleAsc;
      case LibrarySortMode.titleDesc: return l10n.nbSortTitleDesc;
      case LibrarySortMode.createdDesc: return l10n.nbSortCreatedDesc;
      case LibrarySortMode.createdAsc: return l10n.nbSortCreatedAsc;
      case LibrarySortMode.colorGroup: return l10n.nbSortColorGroup;
    }
  }

  IconData get icon {
    switch (this) {
      case LibrarySortMode.modifiedDesc:
      case LibrarySortMode.modifiedAsc:
        return Icons.edit_calendar_outlined;
      case LibrarySortMode.titleAsc:
      case LibrarySortMode.titleDesc:
        return Icons.sort_by_alpha_rounded;
      case LibrarySortMode.createdDesc:
      case LibrarySortMode.createdAsc:
        return Icons.calendar_today_outlined;
      case LibrarySortMode.colorGroup:
        return Icons.palette_outlined;
    }
  }
}

/// Where the user parked the floating tool dock, persisted so the
/// toolbar stays put across sessions. [edge] is one of
/// `left` | `right` | `top` | `bottom` (left/right render the dock
/// vertically). [align] is the 0..1 position ALONG that edge — for
/// top/bottom it runs left→right, for left/right it runs top→bottom;
/// 0.5 is centred.
class ToolDockConfig {
  final String edge;
  final double align;

  const ToolDockConfig({this.edge = 'bottom', this.align = 0.5});

  ToolDockConfig copyWith({String? edge, double? align}) => ToolDockConfig(
        edge: edge ?? this.edge,
        align: align ?? this.align,
      );

  Map<String, dynamic> toJson() => {'edge': edge, 'align': align};

  static ToolDockConfig fromJson(Map<String, dynamic> json) {
    const valid = {'left', 'right', 'top', 'bottom'};
    final e = json['edge'] as String?;
    return ToolDockConfig(
      edge: valid.contains(e) ? e! : 'bottom',
      align: ((json['align'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
    );
  }
}

/// A user-defined notebook folder. Local-only, like [AppSettings.favoriteNotebookIds]
/// — folder membership doesn't sync across devices (same accepted trade-off
/// favorites already ship with), so a real per-notebook `folderId` field
/// living inside the synced `.ncnote` metadata isn't worth the sync/migration
/// surface it would add.
class NotebookFolder {
  final String id;
  final String name;

  const NotebookFolder({required this.id, required this.name});

  NotebookFolder copyWith({String? name}) =>
      NotebookFolder(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static NotebookFolder fromJson(Map<String, dynamic> json) => NotebookFolder(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
      );
}

/// Combined settings blob so we only touch SharedPreferences once per write.
class AppSettings {
  final Set<String> favoriteNotebookIds;
  final List<NotebookFolder> folders;
  /// notebookId → folderId. A notebook with no entry is unfiled.
  final Map<String, String> notebookFolderId;
  final Map<String, DateTime> lastOpenedAt;
  final LibrarySortMode sortMode;
  final bool favoritesFirst;
  final ThemeMode themeMode;
  /// OneNote-style preset rail, independent per ink tool — keyed by
  /// CanvasTool.name (pen/ballpoint/brush/highlighter each get their own
  /// 3 slots so saving or clearing one tool's preset never touches
  /// another's). Each list is fixed-length 3; a `null` entry means the
  /// slot is empty and the popup shows a "+" placeholder. A tool with no
  /// entry yet has saved nothing — see [presetsFor].
  final Map<String, List<PenPreset?>> toolPresets;
  /// Parked position of the editor's movable tool dock.
  final ToolDockConfig toolDock;

  /// When true the MOUSE draws like a pen; when false (default) the mouse is a
  /// selection device (click selects text/elements, drag = marquee) and only
  /// the pen/touch draw. Toggled from the editor's top-right control.
  final bool mouseDraws;

  /// Whether the bottom page-strip (chapter label + page thumbnails) is
  /// shown. Defaults to true; the user can collapse it via its own
  /// chevron to reclaim canvas height, and bring it back with the thin
  /// handle left in its place.
  final bool showPageStrip;

  /// UI language override: 'system' (default) follows the OS locale;
  /// otherwise a supported language code ('it' / 'en' / 'es').
  final String localeCode;

  /// The [Locale] to force on MaterialApp, or null to follow the system.
  Locale? get localeOverride =>
      localeCode == 'system' ? null : Locale(localeCode);

  const AppSettings({
    this.favoriteNotebookIds = const {},
    this.folders = const [],
    this.notebookFolderId = const {},
    this.lastOpenedAt = const {},
    this.sortMode = LibrarySortMode.modifiedDesc,
    this.favoritesFirst = true,
    this.themeMode = ThemeMode.system,
    this.toolPresets = const {},
    this.toolDock = const ToolDockConfig(),
    this.mouseDraws = false,
    this.showPageStrip = true,
    this.localeCode = 'system',
  });

  /// The 3-slot preset rail belonging to [tool], defaulting to all-empty
  /// when that tool has never saved one. Always a fresh list — never
  /// aliased across tools — so pen and highlighter presets stay
  /// independent even though they share this same lookup.
  List<PenPreset?> presetsFor(CanvasTool tool) =>
      toolPresets[tool.name] ?? const [null, null, null];

  AppSettings copyWith({
    Set<String>? favoriteNotebookIds,
    List<NotebookFolder>? folders,
    Map<String, String>? notebookFolderId,
    Map<String, DateTime>? lastOpenedAt,
    LibrarySortMode? sortMode,
    bool? favoritesFirst,
    ThemeMode? themeMode,
    Map<String, List<PenPreset?>>? toolPresets,
    ToolDockConfig? toolDock,
    bool? mouseDraws,
    bool? showPageStrip,
    String? localeCode,
  }) =>
      AppSettings(
        favoriteNotebookIds: favoriteNotebookIds ?? this.favoriteNotebookIds,
        folders: folders ?? this.folders,
        notebookFolderId: notebookFolderId ?? this.notebookFolderId,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        sortMode: sortMode ?? this.sortMode,
        favoritesFirst: favoritesFirst ?? this.favoritesFirst,
        themeMode: themeMode ?? this.themeMode,
        toolPresets: toolPresets ?? this.toolPresets,
        toolDock: toolDock ?? this.toolDock,
        mouseDraws: mouseDraws ?? this.mouseDraws,
        showPageStrip: showPageStrip ?? this.showPageStrip,
        localeCode: localeCode ?? this.localeCode,
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  static const _prefsKey = 'app_settings_v1';

  AppSettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;

      final favIds = (map['fav'] as List?)?.cast<String>().toSet() ?? <String>{};
      final openedRaw = (map['opened'] as Map?)?.cast<String, dynamic>() ?? {};
      final opened = <String, DateTime>{};
      openedRaw.forEach((k, v) {
        final dt = DateTime.tryParse(v as String? ?? '');
        if (dt != null) opened[k] = dt;
      });
      final sort = LibrarySortMode.values.firstWhere(
        (m) => m.name == (map['sort'] as String?),
        orElse: () => LibrarySortMode.modifiedDesc,
      );
      final favFirst = map['fav_first'] as bool? ?? true;
      final theme = ThemeMode.values.firstWhere(
        (m) => m.name == (map['theme'] as String?),
        orElse: () => ThemeMode.system,
      );

      final toolPresetsRaw =
          (map['tool_presets'] as Map?)?.cast<String, dynamic>() ?? const {};
      final toolPresets = <String, List<PenPreset?>>{};
      toolPresetsRaw.forEach((toolName, listRaw) {
        if (listRaw is! List) return;
        toolPresets[toolName] = List<PenPreset?>.generate(3, (i) {
          if (i >= listRaw.length) return null;
          final entry = listRaw[i];
          if (entry == null) return null;
          return PenPreset.fromJson((entry as Map).cast<String, dynamic>());
        }, growable: false);
      });

      final dockRaw = (map['dock'] as Map?)?.cast<String, dynamic>();
      final dock = dockRaw == null
          ? const ToolDockConfig()
          : ToolDockConfig.fromJson(dockRaw);

      final foldersRaw = (map['folders'] as List?) ?? const [];
      final folders = [
        for (final f in foldersRaw)
          if (f is Map) NotebookFolder.fromJson(f.cast<String, dynamic>()),
      ];
      final notebookFolderId =
          (map['notebook_folder'] as Map?)?.cast<String, String>() ?? const {};

      state = AppSettings(
        favoriteNotebookIds: favIds,
        folders: folders,
        notebookFolderId: notebookFolderId,
        lastOpenedAt: opened,
        sortMode: sort,
        favoritesFirst: favFirst,
        themeMode: theme,
        toolPresets: toolPresets,
        toolDock: dock,
        mouseDraws: map['mouse_draws'] as bool? ?? false,
        showPageStrip: map['show_page_strip'] as bool? ?? true,
        localeCode: map['locale'] as String? ?? 'system',
      );
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode({
        'fav': state.favoriteNotebookIds.toList(),
        'folders': state.folders.map((f) => f.toJson()).toList(),
        'notebook_folder': state.notebookFolderId,
        'opened': state.lastOpenedAt
            .map((k, v) => MapEntry(k, v.toIso8601String())),
        'sort': state.sortMode.name,
        'fav_first': state.favoritesFirst,
        'theme': state.themeMode.name,
        'tool_presets': state.toolPresets.map((toolName, list) => MapEntry(
            toolName, list.map((p) => p?.toJson()).toList(growable: false))),
        'dock': state.toolDock.toJson(),
        'mouse_draws': state.mouseDraws,
        'show_page_strip': state.showPageStrip,
        'locale': state.localeCode,
      }));
    } catch (_) {}
  }

  /// Save the current pen-class tool settings into [slot] (0..2) of
  /// [tool]'s own preset rail. Used by the popup's preset rail when the
  /// user long-presses an empty slot or chooses "salva qui" from a
  /// filled slot. Each ink tool keeps an independent rail — this never
  /// touches another tool's slots.
  void savePenPreset(CanvasTool tool, int slot, PenPreset preset) {
    if (slot < 0 || slot > 2) return;
    final next = List<PenPreset?>.from(state.presetsFor(tool));
    while (next.length < 3) {
      next.add(null);
    }
    next[slot] = preset;
    state = state.copyWith(toolPresets: {
      ...state.toolPresets,
      tool.name: next,
    });
    _persist();
  }

  void clearPenPreset(CanvasTool tool, int slot) {
    if (slot < 0 || slot > 2) return;
    final next = List<PenPreset?>.from(state.presetsFor(tool));
    while (next.length < 3) {
      next.add(null);
    }
    next[slot] = null;
    state = state.copyWith(toolPresets: {
      ...state.toolPresets,
      tool.name: next,
    });
    _persist();
  }

  void toggleFavorite(String notebookId) {
    final next = Set<String>.from(state.favoriteNotebookIds);
    if (next.contains(notebookId)) {
      next.remove(notebookId);
    } else {
      next.add(notebookId);
    }
    state = state.copyWith(favoriteNotebookIds: next);
    _persist();
  }

  void markOpened(String notebookId) {
    final next = Map<String, DateTime>.from(state.lastOpenedAt);
    next[notebookId] = DateTime.now();
    state = state.copyWith(lastOpenedAt: next);
    _persist();
  }

  void setSortMode(LibrarySortMode mode) {
    state = state.copyWith(sortMode: mode);
    _persist();
  }

  void setMouseDraws(bool v) {
    state = state.copyWith(mouseDraws: v);
    _persist();
  }

  void setShowPageStrip(bool v) {
    state = state.copyWith(showPageStrip: v);
    _persist();
  }

  void setFavoritesFirst(bool v) {
    state = state.copyWith(favoritesFirst: v);
    _persist();
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _persist();
  }

  /// 'system' to follow the OS locale, or a supported code ('it'/'en'/'es').
  void setLocaleCode(String code) {
    state = state.copyWith(localeCode: code);
    _persist();
  }

  /// Park the tool dock on [edge] (`left`/`right`/`top`/`bottom`) at the
  /// 0..1 [align] position along that edge. Called when the user finishes
  /// dragging the dock to a new spot.
  void setToolDock(String edge, double align) {
    state = state.copyWith(
        toolDock: ToolDockConfig(edge: edge, align: align.clamp(0.0, 1.0)));
    _persist();
  }

  /// Clean up entries for deleted notebooks.
  void purgeNotebook(String notebookId) {
    final favs = Set<String>.from(state.favoriteNotebookIds)..remove(notebookId);
    final opened = Map<String, DateTime>.from(state.lastOpenedAt)..remove(notebookId);
    final folderAssign = Map<String, String>.from(state.notebookFolderId)
      ..remove(notebookId);
    state = state.copyWith(
      favoriteNotebookIds: favs,
      lastOpenedAt: opened,
      notebookFolderId: folderAssign,
    );
    _persist();
  }

  void createFolder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final next = List<NotebookFolder>.from(state.folders)
      ..add(NotebookFolder(id: const Uuid().v4(), name: trimmed));
    state = state.copyWith(folders: next);
    _persist();
  }

  void renameFolder(String folderId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final next = [
      for (final f in state.folders)
        if (f.id == folderId) f.copyWith(name: trimmed) else f,
    ];
    state = state.copyWith(folders: next);
    _persist();
  }

  /// Deletes the folder and unfiles every notebook that was in it (they
  /// stay in the library, just with no folder assigned).
  void deleteFolder(String folderId) {
    final next = List<NotebookFolder>.from(state.folders)
      ..removeWhere((f) => f.id == folderId);
    final assign = Map<String, String>.from(state.notebookFolderId)
      ..removeWhere((_, v) => v == folderId);
    state = state.copyWith(folders: next, notebookFolderId: assign);
    _persist();
  }

  /// Assigns [notebookId] to [folderId], or unfiles it when null.
  void setNotebookFolder(String notebookId, String? folderId) {
    final next = Map<String, String>.from(state.notebookFolderId);
    if (folderId == null) {
      next.remove(notebookId);
    } else {
      next[notebookId] = folderId;
    }
    state = state.copyWith(notebookFolderId: next);
    _persist();
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});
