// What a module is and what it may do. Built-ins declare theirs in Dart;
// external modules would ship the same shape as module.json (see README.md).

/// Host API version. A manifest asking for a newer one is refused.
const int kModuleApiVersion = 1;

enum ModulePermission {
  /// Read the ink and shapes in the lasso selection.
  selectionRead('selection.read'),

  /// Replace the selection with new ink.
  selectionWrite('selection.write'),

  /// Run a model file shipped with the module through the host's runtime.
  modelRun('model.run');

  const ModulePermission(this.key);
  final String key;

  static ModulePermission? fromKey(String key) {
    for (final p in values) {
      if (p.key == key) return p;
    }
    return null;
  }
}

/// Who may use the module. Parsed, not enforced: every module is free today.
enum ModuleEntitlement { free, supporter }

enum ModuleSource { builtin, external }

/// A file the module needs at runtime, relative to the module folder.
class ModuleAsset {
  const ModuleAsset(this.path, {this.sha256, this.license});

  final String path;
  final String? sha256;

  /// Licence of the asset when it differs from the module code's
  /// (model weights often do).
  final String? license;

  Map<String, dynamic> toJson() => {
        'path': path,
        if (sha256 != null) 'sha256': sha256,
        if (license != null) 'license': license,
      };
}

class ModuleManifest {
  const ModuleManifest({
    required this.id,
    required this.version,
    required this.license,
    this.apiVersion = kModuleApiVersion,
    this.source = ModuleSource.builtin,
    this.entitlement = ModuleEntitlement.free,
    this.permissions = const {},
    this.assets = const [],
    this.selectionActions = const [],
    this.name = const {},
    this.description = const {},
  });

  /// Dotted lowercase id, e.g. `abelnotes.circuits`.
  final String id;
  final String version;
  final int apiVersion;

  /// SPDX id of the module code.
  final String license;
  final ModuleSource source;
  final ModuleEntitlement entitlement;
  final Set<ModulePermission> permissions;
  final List<ModuleAsset> assets;

  /// Ids of the lasso actions the module contributes.
  final List<String> selectionActions;

  /// Language code → text, for external modules. Built-ins use l10n instead.
  final Map<String, String> name;
  final Map<String, String> description;

  static final _idPattern = RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$');
  static final _versionPattern = RegExp(r'^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$');
  static final _shaPattern = RegExp(r'^[0-9a-f]{64}$');
  static const _contributionKinds = {'selectionActions'};

  /// Parses an external `module.json`. Throws [FormatException] on anything
  /// malformed, unknown or unsafe, since the file comes from a third party.
  factory ModuleManifest.fromJson(Map<String, dynamic> json) {
    String str(String key) {
      final v = json[key];
      if (v is! String || v.isEmpty) throw FormatException('missing "$key"');
      return v;
    }

    final id = str('id');
    if (!_idPattern.hasMatch(id) || id.length > 64) {
      throw FormatException('bad id "$id"');
    }
    if (id.startsWith('abelnotes.')) throw FormatException('reserved id "$id"');
    final version = str('version');
    if (!_versionPattern.hasMatch(version)) {
      throw FormatException('bad version "$version"');
    }
    final api = json['apiVersion'];
    if (api is! int || api < 1) throw const FormatException('bad "apiVersion"');
    if (api > kModuleApiVersion) {
      throw FormatException('needs module API $api, this app has $kModuleApiVersion');
    }

    final permissions = <ModulePermission>{};
    for (final key in _list(json, 'permissions')) {
      final p = key is String ? ModulePermission.fromKey(key) : null;
      if (p == null) throw FormatException('unknown permission "$key"');
      permissions.add(p);
    }

    final assets = <ModuleAsset>[];
    for (final a in _list(json, 'assets')) {
      if (a is! Map) throw const FormatException('bad asset');
      final path = a['path'];
      if (path is! String || !_safeRelative(path)) {
        throw FormatException('bad asset path "$path"');
      }
      final sha = a['sha256'];
      if (sha != null && (sha is! String || !_shaPattern.hasMatch(sha))) {
        throw FormatException('bad sha256 for "$path"');
      }
      final lic = a['license'];
      assets.add(ModuleAsset(path, sha256: sha as String?, license: lic is String ? lic : null));
    }

    final contributes = json['contributes'] ?? const {};
    if (contributes is! Map) throw const FormatException('bad "contributes"');
    for (final key in contributes.keys) {
      if (!_contributionKinds.contains(key)) {
        throw FormatException('unknown contribution "$key"');
      }
    }
    final rawActions = contributes['selectionActions'] ?? const [];
    if (rawActions is! List) throw const FormatException('"selectionActions" must be a list');
    final actions = [
      for (final a in rawActions)
        if (a is String && a.startsWith('$id.') && _idPattern.hasMatch(a)) a
        else throw FormatException('bad selectionActions id "$a"'),
    ];
    if (actions.isNotEmpty && !permissions.contains(ModulePermission.selectionWrite)) {
      throw const FormatException('selection actions need "selection.write"');
    }

    final entitlement = switch (json['entitlement']) {
      null || 'free' => ModuleEntitlement.free,
      'supporter' => ModuleEntitlement.supporter,
      final e => throw FormatException('unknown entitlement "$e"'),
    };

    return ModuleManifest(
      id: id,
      version: version,
      apiVersion: api,
      license: str('license'),
      source: ModuleSource.external,
      entitlement: entitlement,
      permissions: permissions,
      assets: assets,
      selectionActions: actions,
      name: _texts(json, 'name', required: true),
      description: _texts(json, 'description'),
    );
  }

  /// [name] in [languageCode], falling back to English, then to the id.
  String nameIn(String languageCode) =>
      name[languageCode] ?? name['en'] ?? id;

  String? descriptionIn(String languageCode) =>
      description[languageCode] ?? description['en'];

  static List<dynamic> _list(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) return const [];
    if (v is! List) throw FormatException('"$key" must be a list');
    return v;
  }

  static Map<String, String> _texts(Map<String, dynamic> json, String key,
      {bool required = false}) {
    final v = json[key];
    if (v == null && !required) return const {};
    if (v is! Map || v.isEmpty) throw FormatException('missing "$key"');
    final out = <String, String>{};
    for (final e in v.entries) {
      final text = e.value;
      if (e.key is! String || text is! String || text.isEmpty || text.length > 500) {
        throw FormatException('bad "$key"');
      }
      out[e.key as String] = text;
    }
    return out;
  }

  static bool _safeRelative(String path) =>
      path.isNotEmpty &&
      path.length <= 200 &&
      !path.startsWith('/') &&
      !path.contains('\\') &&
      !path.contains(':') &&
      !path.split('/').any((s) => s.isEmpty || s == '.' || s == '..');
}
