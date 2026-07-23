import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Configurazione centralizzata dell'app AbelNotes.
class AppConfig {
  // ── App Version ──
  //
  // Single source of truth is the `version:` line in pubspec.yaml. Flutter
  // regenerates `version.json` (bundled at `flutter_assets/version.json`)
  // from it on EVERY build, so [loadVersion] reads that at startup and the
  // in-app crash log / about dialog always match the built version — no
  // hand-maintained constant to forget (which is exactly how it drifted to
  // 0.37.0+39 while pubspec was already 0.37.1+40).
  //
  // The constants below are only a pre-load fallback (used if the asset read
  // fails, e.g. in a unit test with no rootBundle). Bump semver in pubspec:
  // patch for bug-only commits, minor for visible feature work; the build
  // number after "+" is the absolute counter and never resets.
  static String _appVersion = '0.0.0';
  static int _appBuildNumber = 0;
  static bool _versionLoaded = false;

  static String get appVersion => _appVersion;
  static int get appBuildNumber => _appBuildNumber;
  static String get fullVersion => '$_appVersion+$_appBuildNumber';

  /// Reads Flutter's auto-generated `version.json` into the fields above.
  /// Call once at startup AFTER `WidgetsFlutterBinding.ensureInitialized()`
  /// and BEFORE anything that reads [fullVersion] (e.g. CrashLogger.init).
  /// Idempotent; never throws.
  static Future<void> loadVersion() async {
    if (_versionLoaded) return;
    try {
      final raw = await rootBundle.loadString('version.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final v = json['version'];
      final b = json['build_number'];
      if (v is String && v.isNotEmpty) _appVersion = v;
      if (b is String && b.isNotEmpty) {
        _appBuildNumber = int.tryParse(b) ?? _appBuildNumber;
      } else if (b is num) {
        _appBuildNumber = b.toInt();
      }
      _versionLoaded = true;
    } catch (_) {
      // Keep the fallback constants; not fatal.
    }
  }

  /// Short git commit the binary was built from, injected at build time via
  /// `--dart-define=GIT_COMMIT=...` (CI passes the full github.sha; see
  /// .github/workflows/build.yml). Truncated here rather than in the
  /// workflow so the same syntax works on both bash and PowerShell runners.
  /// Local builds without the define show 'dev'. Shown in About and
  /// prefixed to the crash log so a pasted log always identifies the build.
  static String get gitCommit {
    const raw = String.fromEnvironment('GIT_COMMIT', defaultValue: 'dev');
    return raw.length > 7 ? raw.substring(0, 7) : raw;
  }

  // ── WebDAV / Nextcloud ──
  /// The app was renamed HandWriter → AbelNotes; this used to be
  /// '/HandWriter/'. Existing installs' locally-stored `remote_path` rows
  /// still have the old prefix baked in from when each notebook was
  /// registered — [FileService._migrateRemotePathPrefix] rewrites them to
  /// this value on next launch. The *server-side* folder must be renamed
  /// to match (not recreated — an actual rename so existing files move
  /// with it), otherwise sync starts looking in a folder that doesn't
  /// exist and either fails or silently creates a new empty one.
  static const String legacyRemotePath = '/HandWriter/';
  static const String defaultRemotePath = '/AbelNotes/';
  static const int webdavTimeoutSeconds = 120;
  /// Shorter timeout for lightweight delta operations (page JSON, metadata).
  static const int webdavDeltaTimeoutSeconds = 30;
  /// Longer timeout for downloading the root .ncnote ZIP — these can be
  /// 60+ MB on a heavy notebook (e.g. Automotive with ~200 PDF page assets)
  /// and a 120 s overall deadline kills the request before the body is
  /// fully streamed in over a Tailscale link.  10 minutes covers the worst
  /// realistic case (≈100 KB/s sustained).
  static const int webdavLargeDownloadTimeoutSeconds = 600;
  static const int maxRetries = 3;

  // ── Sync ──
  static const Duration syncDebounce = Duration(seconds: 5);
  static const Duration syncInterval = Duration(minutes: 5);
  static const int maxConcurrentSyncs = 3;

  // ── Delta Sync ──
  /// How often the canvas checks for remote page changes from other devices.
  /// Tuned to 2 s so a stroke made on PC surfaces on iPad in ~3-4 s on a
  /// Tailscale HTTPS link. Actual network load stays low because most polls
  /// short-circuit on the cached meta ETag (HEAD only, no body).
  static const Duration deltaPullInterval = Duration(seconds: 2);
  /// Random jitter added to each poll so multiple devices don't all PROPFIND
  /// the server on the same 2 s beat. Prevents thundering-herd on the
  /// Nextcloud side when user has PC + iPad + phone all open.
  static const Duration deltaPullJitter = Duration(milliseconds: 600);
  /// Remote sub-folder that holds exploded per-page files for each notebook.
  static const String deltaSyncDir = '_delta/';

  // ── Canvas ──
  // 1.5 is the user-preferred fine handwriting default (matches a
  // 0.5 mm fineliner at typical writing zoom). Tool-specific widths
  // are remembered separately in CanvasNotifier and persisted in
  // SharedPreferences, so each tool keeps its last chosen size across
  // restarts.
  static const double defaultStrokeWidth = 1.5;
  static const double minStrokeWidth = 0.5;
  static const double maxStrokeWidth = 20.0;
  static const double pressureSensitivity = 1.0;
  static const int catmullRomSegments = 4; // punti interpolati tra 2 raw
  static const double defaultPageWidth = 595.0; // A4 in punti (72dpi)
  static const double defaultPageHeight = 842.0;

  // ── Infinite / scratch canvas ──
  // Free-sketch notebooks use one big square "page" instead of an A4
  // sheet. Large-but-bounded (no A4 border/shadow painted) so it reads
  // as an infinite whiteboard for quick sketches without needing a
  // dynamic-grow codepath. Identified by `metadata.paperType == 'infinite'`.
  static const String infinitePaperType = 'infinite';
  static const double scratchPageSize = 6000.0;

  // ── File Format ──
  static const String fileExtension = '.ncnote';
  static const String metadataFile = 'metadata.json';
  static const String documentFile = 'document.json';
  static const String pagesDir = 'pages';
  static const String assetsDir = 'assets';
  static const String thumbnailsDir = 'thumbnails';
  static const int formatVersion = 1;

  // ── Cache ──
  static const int maxCachedPages = 10; // pagine in memoria
  static const Duration cacheExpiry = Duration(hours: 24);
  static const int maxThumbnailCacheSize = 50; // MB

  // ── Database ──
  static const String dbName = 'abelnotes.db';
  static const int dbVersion = 1;

  // ── Local storage directory ──
  /// Root folder name under the app documents dir.
  static const String appDirName = 'AbelNotes';
}
