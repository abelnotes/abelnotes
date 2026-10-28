import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/services/folder_merge.dart';
import 'package:abelnotes/shared/models/folder_doc.dart';
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

/// A user-defined notebook folder, as the library UI sees it. The synced
/// source of truth is [AppSettings.folderDoc] (`folders.json` on the remote).
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
  final FolderDoc? _folderDoc;

  /// Folders and notebook assignments with their sync stamps and tombstones.
  FolderDoc get folderDoc => _folderDoc ?? FolderDoc.empty;

  /// Local folder edits not yet merged into the remote `folders.json`.
  final bool folderDirty;

  /// Version of the remote `folders.json` this device last merged.
  final String? folderRemoteVersion;

  List<NotebookFolder> get folders => [
        for (final e in folderDoc.liveFolders)
          NotebookFolder(id: e.key, name: e.value.name)
      ];

  /// notebookId → folderId. A notebook with no entry is unfiled.
  Map<String, String> get notebookFolderId => folderDoc.liveAssignments;
  final Map<String, DateTime> lastOpenedAt;
  final LibrarySortMode sortMode;
  final bool favoritesFirst;
  final bool libraryGridView;
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

  /// Whether touch (finger) input is ignored for drawing tools, treating it
  /// as pan/scroll instead — only stylus/pen draws. Null means off: a finger
  /// draws whatever tool is armed, and the pan tool is how the user says
  /// "don't draw". Stylus owners turn it on from Settings → Stylus & Input
  /// to get palm rejection.
  final bool? stylusOnlyDrawing;

  /// Stylus pressure sets the stroke width. Off, every pen stroke has the
  /// width a pressure-less device gets.
  final bool pressureWidth;

  /// Writing speed thins the pen stroke. Off, width follows pressure only.
  final bool speedWidth;

  /// Stylus lifts shorter than a few ms continue the same stroke instead of
  /// starting a new one (sensor dropouts on iPad).
  final bool strokeContinuation;

  /// Recognized closed shapes get a light tint of the ink colour.
  final bool fillRecognizedShapes;

  /// Which remote the notebooks sync to: 'webdav' for the user's own
  /// server, 'drive' for their Google Drive, null for local-only. One
  /// backend at a time — a notebook living in two places at once would give
  /// the engine two sources of truth to reconcile.
  final String? syncBackend;

  /// Tool the editor arms when a notebook is opened, by [CanvasTool.name].
  /// Null until the user picks one: the editor then starts in navigate mode
  /// (pan) on phones and with the pen on desktop.
  final String? lastTool;

  /// Whether the bottom page-strip (chapter label + page thumbnails) is
  /// shown. Defaults to true; the user can collapse it via its own
  /// chevron to reclaim canvas height, and bring it back with the thin
  /// handle left in its place.
  final bool showPageStrip;

  /// UI language override: 'system' (default) follows the OS locale;
  /// otherwise a supported language code — keep in sync with
  /// MaterialApp's supportedLocales in main.dart.
  final String localeCode;

  /// The [Locale] to force on MaterialApp, or null to follow the system.
  Locale? get localeOverride =>
      localeCode == 'system' ? null : Locale(localeCode);

  const AppSettings({
    this.favoriteNotebookIds = const {},
    FolderDoc? folderDoc,
    this.folderDirty = false,
    this.folderRemoteVersion,
    this.lastOpenedAt = const {},
    this.sortMode = LibrarySortMode.modifiedDesc,
    this.favoritesFirst = true,
    this.libraryGridView = true,
    this.themeMode = ThemeMode.system,
    this.toolPresets = const {},
    this.toolDock = const ToolDockConfig(),
    this.mouseDraws = false,
    this.stylusOnlyDrawing,
    this.pressureWidth = true,
    this.speedWidth = true,
    this.strokeContinuation = true,
    this.fillRecognizedShapes = true,
    this.lastTool,
    this.syncBackend,
    this.showPageStrip = true,
    this.localeCode = 'system',
  }) : _folderDoc = folderDoc;

  /// The 3-slot preset rail belonging to [tool], defaulting to all-empty
  /// when that tool has never saved one. Always a fresh list — never
  /// aliased across tools — so pen and highlighter presets stay
  /// independent even though they share this same lookup.
  List<PenPreset?> presetsFor(CanvasTool tool) =>
      toolPresets[tool.name] ?? const [null, null, null];

  AppSettings copyWith({
    Set<String>? favoriteNotebookIds,
    FolderDoc? folderDoc,
    bool? folderDirty,
    String? folderRemoteVersion,
    bool clearFolderRemoteVersion = false,
    Map<String, DateTime>? lastOpenedAt,
    LibrarySortMode? sortMode,
    bool? favoritesFirst,
    bool? libraryGridView,
    ThemeMode? themeMode,
    Map<String, List<PenPreset?>>? toolPresets,
    ToolDockConfig? toolDock,
    bool? mouseDraws,
    bool? stylusOnlyDrawing,
    bool? pressureWidth,
    bool? speedWidth,
    bool? strokeContinuation,
    bool? fillRecognizedShapes,
    String? lastTool,
    String? syncBackend,
    /// copyWith can't tell "leave it" from "set it to null", and going back
    /// to local-only has to be expressible. Same trick as CanvasState's
    /// clear* flags.
    bool clearSyncBackend = false,
    bool? showPageStrip,
    String? localeCode,
  }) =>
      AppSettings(
        favoriteNotebookIds: favoriteNotebookIds ?? this.favoriteNotebookIds,
        folderDoc: folderDoc ?? _folderDoc,
        folderDirty: folderDirty ?? this.folderDirty,
        folderRemoteVersion: clearFolderRemoteVersion
            ? null
            : (folderRemoteVersion ?? this.folderRemoteVersion),
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        sortMode: sortMode ?? this.sortMode,
        favoritesFirst: favoritesFirst ?? this.favoritesFirst,
        libraryGridView: libraryGridView ?? this.libraryGridView,
        themeMode: themeMode ?? this.themeMode,
        toolPresets: toolPresets ?? this.toolPresets,
        toolDock: toolDock ?? this.toolDock,
        mouseDraws: mouseDraws ?? this.mouseDraws,
        stylusOnlyDrawing: stylusOnlyDrawing ?? this.stylusOnlyDrawing,
        pressureWidth: pressureWidth ?? this.pressureWidth,
        speedWidth: speedWidth ?? this.speedWidth,
        strokeContinuation: strokeContinuation ?? this.strokeContinuation,
        fillRecognizedShapes: fillRecognizedShapes ?? this.fillRecognizedShapes,
        lastTool: lastTool ?? this.lastTool,
        syncBackend:
            clearSyncBackend ? null : (syncBackend ?? this.syncBackend),
        showPageStrip: showPageStrip ?? this.showPageStrip,
        localeCode: localeCode ?? this.localeCode,
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  static const _prefsKey = 'app_settings_v1';

  AppSettingsNotifier() : super(const AppSettings()) {
    ready = _load();
  }

  /// Completes once the stored settings are in [state].
  late final Future<void> ready;

  static int _nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

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

      // Installs from before folders synced only have the plain lists: they
      // get the legacy stamp and are persisted in the new shape.
      final FolderDoc folderDoc;
      final docRaw = map['folder_doc'];
      var migrated = false;
      if (docRaw is Map) {
        folderDoc = FolderDoc.fromJson(docRaw);
      } else {
        final foldersRaw = (map['folders'] as List?) ?? const [];
        final legacy = [
          for (final f in foldersRaw)
            if (f is Map) NotebookFolder.fromJson(f.cast<String, dynamic>()),
        ];
        final assign = (map['notebook_folder'] as Map?)
                ?.map((k, v) => MapEntry(k as String, v as String)) ??
            const <String, String>{};
        folderDoc = FolderDoc.fromLegacy(
            [for (final f in legacy) (id: f.id, name: f.name)], assign);
        migrated = !folderDoc.isEmpty;
      }

      state = AppSettings(
        favoriteNotebookIds: favIds,
        folderDoc: folderDoc,
        folderDirty: migrated || (map['folder_dirty'] as bool? ?? false),
        folderRemoteVersion: map['folder_remote_version'] as String?,
        lastOpenedAt: opened,
        sortMode: sort,
        favoritesFirst: favFirst,
        libraryGridView: map['grid_view'] as bool? ?? true,
        themeMode: theme,
        toolPresets: toolPresets,
        toolDock: dock,
        mouseDraws: map['mouse_draws'] as bool? ?? false,
        stylusOnlyDrawing: map['stylus_only_drawing'] as bool?,
        pressureWidth: map['pressure_width'] as bool? ?? true,
        speedWidth: map['speed_width'] as bool? ?? true,
        strokeContinuation: map['stroke_continuation'] as bool? ?? true,
        fillRecognizedShapes: map['fill_shapes'] as bool? ?? true,
        lastTool: map['last_tool'] as String?,
        syncBackend: map['sync_backend'] as String?,
        showPageStrip: map['show_page_strip'] as bool? ?? true,
        localeCode: map['locale'] as String? ?? 'system',
      );
      if (migrated) await _persist();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode({
        'fav': state.favoriteNotebookIds.toList(),
        // Plain lists stay for older builds; folder_doc is what this one reads.
        'folders': state.folders.map((f) => f.toJson()).toList(),
        'notebook_folder': state.notebookFolderId,
        'folder_doc': state.folderDoc.toJson(),
        'folder_dirty': state.folderDirty,
        if (state.folderRemoteVersion != null)
          'folder_remote_version': state.folderRemoteVersion,
        'opened': state.lastOpenedAt
            .map((k, v) => MapEntry(k, v.toIso8601String())),
        'sort': state.sortMode.name,
        'fav_first': state.favoritesFirst,
        'grid_view': state.libraryGridView,
        'theme': state.themeMode.name,
        'tool_presets': state.toolPresets.map((toolName, list) => MapEntry(
            toolName, list.map((p) => p?.toJson()).toList(growable: false))),
        'dock': state.toolDock.toJson(),
        'mouse_draws': state.mouseDraws,
        if (state.stylusOnlyDrawing != null)
          'stylus_only_drawing': state.stylusOnlyDrawing,
        'pressure_width': state.pressureWidth,
        'speed_width': state.speedWidth,
        'stroke_continuation': state.strokeContinuation,
        'fill_shapes': state.fillRecognizedShapes,
        if (state.lastTool != null) 'last_tool': state.lastTool,
        if (state.syncBackend != null) 'sync_backend': state.syncBackend,
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

  void setLibraryGridView(bool v) {
    if (state.libraryGridView == v) return;
    state = state.copyWith(libraryGridView: v);
    _persist();
  }

  void setMouseDraws(bool v) {
    state = state.copyWith(mouseDraws: v);
    _persist();
  }

  void setStylusOnlyDrawing(bool v) {
    state = state.copyWith(stylusOnlyDrawing: v);
    _persist();
  }

  void setPressureWidth(bool v) {
    state = state.copyWith(pressureWidth: v);
    _persist();
  }

  void setSpeedWidth(bool v) {
    state = state.copyWith(speedWidth: v);
    _persist();
  }

  void setStrokeContinuation(bool v) {
    state = state.copyWith(strokeContinuation: v);
    _persist();
  }

  void setFillRecognizedShapes(bool v) {
    state = state.copyWith(fillRecognizedShapes: v);
    _persist();
  }

  /// Switches which remote new syncs talk to. Null goes back to local-only.
  void setSyncBackend(String? backend) {
    state = state.copyWith(
        syncBackend: backend, clearSyncBackend: backend == null);
    _persist();
  }

  void setLastTool(String toolName) {
    if (state.lastTool == toolName) return;
    state = state.copyWith(lastTool: toolName);
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
    final doc = state.folderDoc.withAssignment(notebookId, null, _nowMs());
    state = state.copyWith(
      favoriteNotebookIds: favs,
      lastOpenedAt: opened,
      folderDoc: doc,
      folderDirty: state.folderDirty || !identical(doc, state.folderDoc),
    );
    _persist();
  }

  void _editFolders(FolderDoc Function(FolderDoc doc, int now) edit) {
    final doc = edit(state.folderDoc, _nowMs());
    if (identical(doc, state.folderDoc)) return;
    state = state.copyWith(folderDoc: doc, folderDirty: true);
    _persist();
  }

  void createFolder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _editFolders((d, now) =>
        d.withFolderCreated(const Uuid().v4(), trimmed, now));
  }

  void renameFolder(String folderId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _editFolders((d, now) => d.withFolderRenamed(folderId, trimmed, now));
  }

  /// Deletes the folder; its notebooks stay in the library, unfiled.
  void deleteFolder(String folderId) =>
      _editFolders((d, now) => d.withFolderDeleted(folderId, now));

  /// Assigns [notebookId] to [folderId], or unfiles it when null.
  void setNotebookFolder(String notebookId, String? folderId) => _editFolders(
      (d, now) => d.withAssignment(notebookId, folderId, now));

  /// Adopts the outcome of a folder sync. Edits made while it ran are merged
  /// back in, and stay dirty if the synced document does not contain them.
  Future<void> applyFolderSync(FolderDoc synced, String? remoteVersion) async {
    await ready;
    final merged = mergeFolderDocs(state.folderDoc, synced, nowMs: _nowMs());
    state = state.copyWith(
      folderDoc: merged.sameContent(state.folderDoc) ? null : merged,
      folderDirty: !merged.sameContent(synced),
      folderRemoteVersion: remoteVersion,
      clearFolderRemoteVersion: remoteVersion == null,
    );
    await _persist();
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});
