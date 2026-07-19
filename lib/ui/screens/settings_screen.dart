import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/app_mode_provider.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/webdav_service.dart';
import 'package:abelnotes/features/auth/login_screen.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/screens/trash_screen.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Redesigned settings screen — left rail of sections + content panel.
class SettingsScreenV2 extends ConsumerStatefulWidget {
  const SettingsScreenV2({super.key});

  @override
  ConsumerState<SettingsScreenV2> createState() => _SettingsScreenV2State();
}

/// Below this width there's no room for a permanent 240px rail beside
/// readable content, so we switch to a menu-then-detail phone layout.
const double _kPhoneBreakpoint = 700;

class _SettingsScreenV2State extends ConsumerState<SettingsScreenV2> {
  String _section = 'general';
  bool _phoneMenuOpen = true;

  Widget _buildSection() => switch (_section) {
        'general' => _GeneralSection(),
        'input' => _InputSection(),
        'sync' => _SyncSection(),
        'shortcuts' => _ShortcutsSection(),
        'storage' => _StorageSection(),
        'advanced' => const _AdvancedSection(),
        'about' => _AboutSection(),
        _ => _GeneralSection(),
      };

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _kPhoneBreakpoint) {
              return _phoneMenuOpen
                  ? _PhoneMenu(
                      section: _section,
                      onSelect: (s) => setState(() {
                        _section = s;
                        _phoneMenuOpen = false;
                      }),
                      onClose: () => Navigator.of(context).pop(),
                    )
                  : _PhoneSectionView(
                      onBack: () => setState(() => _phoneMenuOpen = true),
                      child: _buildSection(),
                    );
            }
            return Row(
              children: [
                _Rail(
                  section: _section,
                  onSelect: (s) => setState(() => _section = s),
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(48, 40, 48, 80),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _buildSection(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Section list + label + icon, shared between the desktop rail and the
/// phone menu so both stay in sync.
List<(String, String, String)> _sectionItems(AppLocalizations l10n) => [
      ('general', l10n.setSectionGeneral, 'settings'),
      ('input', l10n.setSectionInput, 'pen'),
      ('sync', l10n.setSectionSync, 'cloud'),
      ('storage', l10n.setSectionStorage, 'pages'),
      ('shortcuts', l10n.setSectionShortcuts, 'keyboard'),
      ('advanced', l10n.setSectionAdvanced, 'arrow'),
      ('about', l10n.setSectionAbout, 'help'),
    ];

class _PhoneMenu extends StatelessWidget {
  final String section;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;
  const _PhoneMenu({
    required this.section,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const HwIcon('chevron-left', size: 18),
                onPressed: onClose,
              ),
              Text(l10n.setSettingsTitle,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.ink0)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final item in _sectionItems(l10n))
                _PhoneMenuItem(
                  label: item.$2,
                  icon: item.$3,
                  selected: section == item.$1,
                  onTap: () => onSelect(item.$1),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhoneMenuItem extends StatelessWidget {
  final String label, icon;
  final bool selected;
  final VoidCallback onTap;
  const _PhoneMenuItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? p.paper2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            HwIcon(icon, size: 16, color: selected ? p.ink0 : p.ink1),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: 15,
                    color: selected ? p.ink0 : p.ink1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  )),
            ),
            HwIcon('chevron-left', size: 12, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

class _PhoneSectionView extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;
  const _PhoneSectionView({required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const HwIcon('chevron-left', size: 18),
                onPressed: onBack,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  final String section;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;
  const _Rail({
    required this.section,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final items = _sectionItems(l10n);
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: p.paper0,
        border: Border(right: BorderSide(color: p.paper3)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HwButton(
            leading: const HwIcon('chevron-left', size: 16),
            label: l10n.setBackToLibrary,
            onPressed: onClose,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              l10n.setSettingsTitle,
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: p.ink2),
            ),
          ),
          for (final item in items)
            _RailItem(
              id: item.$1,
              label: item.$2,
              icon: item.$3,
              selected: section == item.$1,
              onTap: () => onSelect(item.$1),
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String id, label, icon;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? p.paper2 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              HwIcon(icon, size: 14, color: selected ? p.ink0 : p.ink1),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? p.ink0 : p.ink1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: p.ink0,
          )),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget control;
  const _Row({required this.title, this.sub, required this.control});
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.paper2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14, color: p.ink0, fontWeight: FontWeight.w500)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!,
                      style: TextStyle(
                          fontSize: 12, color: p.ink2, height: 1.5)),
                ],
              ],
            ),
          ),
          control,
        ],
      ),
    );
  }
}

class _GeneralSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final variant = HwThemeScope.variantOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.setSectionGeneral),
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.setThemeLabel,
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      color: p.ink2,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final t in [
                    ('light', l10n.setThemeLight, 'sun', HwThemeVariant.light),
                    ('paper', l10n.setThemePaper, 'pages',
                        HwThemeVariant.paper),
                    ('dark', l10n.setThemeDark, 'moon', HwThemeVariant.dark),
                  ]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // Map our variant onto Flutter's ThemeMode for
                          // persistence; the wrapper picks the actual palette.
                          ref.read(appSettingsProvider.notifier).setThemeMode(
                                t.$4 == HwThemeVariant.dark
                                    ? ThemeMode.dark
                                    : t.$4 == HwThemeVariant.paper
                                        ? ThemeMode.system
                                        : ThemeMode.light,
                              );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 20),
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: variant == t.$4
                                ? p.accentSoft
                                : p.paper0,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: variant == t.$4
                                  ? p.accent
                                  : p.paper3,
                              width: variant == t.$4 ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              HwIcon(t.$3, size: 20, color: p.ink0),
                              const SizedBox(height: 8),
                              Text(t.$2,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: p.ink0,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        _Row(
            title: l10n.setLanguage,
            sub: l10n.setLanguageSub,
            control: HwButton(
              label: _localeLabel(l10n, settings.localeCode),
              trailing: const HwIcon('chevron-down', size: 12),
              style: HwButtonStyle.solid,
              onPressed: () => _showLanguagePicker(context, ref),
            )),
        _Row(
            title: l10n.setFavoritesFirst,
            sub: l10n.setFavoritesFirstSub,
            control: HwSwitch(
              value: settings.favoritesFirst,
              onChanged: (v) =>
                  ref.read(appSettingsProvider.notifier).setFavoritesFirst(v),
            )),
      ],
    );
  }

  String _localeLabel(AppLocalizations l10n, String code) {
    switch (code) {
      case 'it':
        return l10n.setLanguageItalian;
      case 'en':
        return l10n.setLanguageEnglish;
      case 'es':
        return l10n.setLanguageSpanish;
      default:
        return l10n.setLanguageSystem;
    }
  }

  /// Bottom-sheet language picker, mirroring the sort-mode sheet used in
  /// the library so the settings UI stays visually consistent.
  Future<void> _showLanguagePicker(BuildContext context, WidgetRef ref) async {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final current = ref.read(appSettingsProvider).localeCode;
    final options = [
      ('system', l10n.setLanguageSystem),
      ('it', l10n.setLanguageItalian),
      ('en', l10n.setLanguageEnglish),
      ('es', l10n.setLanguageSpanish),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.paper0,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(l10n.setLanguage,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink0)),
            const SizedBox(height: 8),
            for (final o in options)
              ListTile(
                title: Text(o.$2,
                    style: TextStyle(color: p.ink0, fontSize: 14)),
                trailing: o.$1 == current
                    ? HwIcon('check', size: 16, color: p.accent)
                    : null,
                onTap: () => Navigator.of(ctx).pop(o.$1),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(appSettingsProvider.notifier).setLocaleCode(picked);
    }
  }
}

class _InputSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.setSectionInput),
        _Row(
            title: l10n.setStylusOnly,
            sub: l10n.setStylusOnlySub,
            control: HwSwitch(value: true, onChanged: (_) {})),
        _Row(
            title: l10n.setPalmRejection,
            sub: l10n.setPalmRejectionSub,
            control: HwSwitch(value: true, onChanged: (_) {})),
        _Row(
            title: l10n.setPressureThickness,
            sub: l10n.setPressureThicknessSub,
            control: HwSwitch(value: true, onChanged: (_) {})),
        _Row(
            title: l10n.setTiltCalligraphy,
            sub: l10n.setTiltCalligraphySub,
            control: HwSwitch(value: true, onChanged: (_) {})),
        _Row(
            title: l10n.setStrokeContinuation,
            sub: l10n.setStrokeContinuationSub,
            control: HwSwitch(value: true, onChanged: (_) {})),
      ],
    );
  }
}

class _SyncSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final creds = ref.watch(credentialsProvider);
    final connected = creds != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.setSectionSync),
        Text(
          connected
              ? l10n.setSyncConnectedDesc
              : l10n.setSyncLocalOnlyDesc,
          style: TextStyle(fontSize: 14, color: p.ink2, height: 1.5),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.paper0,
            border: Border.all(color: p.paper3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (connected ? HwTheme.syncOk : p.ink3)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                    child: HwIcon(connected ? 'cloud-check' : 'cloud-off',
                        size: 20,
                        color: connected ? HwTheme.syncOk : p.ink2)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connected ? l10n.setSyncWebdav : l10n.setSyncLocalOnly,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.ink0)),
                    const SizedBox(height: 2),
                    Text(
                        connected
                            ? l10n.setSyncAccountInfo(
                                _hostOf(creds.serverUrl), creds.username)
                            : l10n.setSyncNoServer,
                        style: TextStyle(fontSize: 12, color: p.ink2)),
                  ],
                ),
              ),
              connected
                  ? HwButton(
                      label: l10n.setDisconnect,
                      style: HwButtonStyle.solid,
                      onPressed: () => _confirmDisconnect(context, ref))
                  : HwButton(
                      label: l10n.setConnect,
                      style: HwButtonStyle.primary,
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ));
                      }),
            ],
          ),
        ),
        if (connected) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _checkCertificate(context, ref, creds),
              child: Text(l10n.setCheckCert),
            ),
          ),
        ],
      ],
    );
  }

  /// Manual recovery path for a legitimate server-certificate renewal: the
  /// pinned fingerprint only ever changes via this explicit, confirmed
  /// action — never silently, and never automatically re-pinned just
  /// because the old one stopped matching (see WebDavService's
  /// trust-on-first-use pinning).
  Future<void> _checkCertificate(
      BuildContext context, WidgetRef ref, NextcloudCredentials creds) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final newFingerprint =
        await WebDavService.probeCertificateFingerprint(creds.serverUrl);
    if (newFingerprint == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.setCertCheckFailed)));
      return;
    }
    if (newFingerprint == creds.certFingerprint) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.setCertUnchanged)));
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.setCertChangedTitle),
        content: Text(l10n.setCertChangedBody(
          creds.certFingerprint == null
              ? '—'
              : WebDavService.formatFingerprint(creds.certFingerprint!),
          WebDavService.formatFingerprint(newFingerprint),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.setCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l10n.setCertConfirmNew),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(credentialsProvider.notifier).pinCertificate(newFingerprint);
    }
  }

  String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.setDisconnectTitle),
        content: Text(l10n.setDisconnectBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(l10n.setCancel)),
          TextButton(
              style:
                  TextButton.styleFrom(foregroundColor: HwTheme.syncConflict),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(l10n.setDisconnect)),
        ],
      ),
    );
    if (ok != true) return;
    // Logout, then stay in the app in local-only mode instead of bouncing
    // to onboarding (the user still has their local notebooks).
    await ref.read(credentialsProvider.notifier).logout();
    await ref.read(localModeProvider.notifier).enable();
  }
}

class _ShortcutsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final shortcuts = [
      (l10n.setShortcutPen, 'P'),
      (l10n.setShortcutUndo, '⌘ Z'),
      (l10n.setShortcutBrush, 'B'),
      (l10n.setShortcutRedo, '⌘ ⇧ Z'),
      (l10n.setShortcutEraser, 'E'),
      (l10n.setShortcutSelectAll, '⌘ A'),
      (l10n.setShortcutLasso, 'L'),
      (l10n.setShortcutCopy, '⌘ C'),
      (l10n.setShortcutHand, 'H'),
      (l10n.setShortcutCut, '⌘ X'),
      (l10n.setShortcutText, 'T'),
      (l10n.setShortcutPaste, '⌘ V'),
      (l10n.setShortcutShape, 'S'),
      (l10n.setShortcutDuplicate, '⌘ D'),
      (l10n.setShortcutChangePage, '↑ ↓'),
      (l10n.setShortcutSave, '⌘ S'),
      (l10n.setShortcutFit, '⌘ 0'),
      (l10n.setShortcutCheatSheet, '?'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.setKeyboardShortcutsTitle),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 0,
            crossAxisSpacing: 32,
            mainAxisExtent: 40,
          ),
          itemCount: shortcuts.length,
          itemBuilder: (_, i) {
            final s = shortcuts[i];
            return Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.paper2)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s.$1, style: TextStyle(fontSize: 13, color: p.ink0)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.paper2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(s.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: HwTheme.fontMono,
                          color: p.ink1,
                        )),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StorageSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.setSectionStorage),
        _Row(
            title: l10n.setClearCache,
            sub: l10n.setClearCacheSub,
            control: HwButton(
                label: l10n.setClear,
                style: HwButtonStyle.solid,
                onPressed: () => _clearCache(context, ref))),
        _Row(
            title: l10n.setTrash,
            sub: l10n.setTrashSub,
            control: HwButton(
                label: l10n.setOpenTrash,
                style: HwButtonStyle.solid,
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TrashScreen(),
                  ));
                })),
        _Row(
            title: l10n.setExportLibrary,
            sub: l10n.setExportLibrarySub,
            control: HwButton(
                label: l10n.setExport,
                style: HwButtonStyle.solid,
                onPressed: () => _exportLibrary(context, ref))),
      ],
    );
  }

  /// Thumbnails are the only real disk-backed, safely-regenerable cache in
  /// this app (render/image caches are in-memory only, notebook files
  /// themselves are data, not cache). They're re-rendered lazily on next
  /// library view, so wiping them is always safe.
  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(thumbnailServiceProvider).clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.setClearCacheDone)),
    );
  }

  Future<void> _exportLibrary(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final entries = ref.read(notebookListProvider).valueOrNull ?? const [];
    if (entries.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.setExportLibraryEmpty)));
      return;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.setExportLibraryInProgress),
        duration: const Duration(seconds: 30)));
    try {
      final fileService = ref.read(fileServiceProvider);
      final archive = Archive();
      for (final entry in entries) {
        final bytes = await fileService.readNotebookFile(entry.metadata.id);
        if (bytes == null) continue;
        final name = '${_sanitiseForFilename(entry.metadata.title)}_${entry.metadata.id}.ncnote';
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
      final zipBytes = ZipEncoder().encode(archive);
      messenger.hideCurrentSnackBar();
      if (zipBytes == null) {
        if (!context.mounted) return;
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.setExportLibraryFailed('zip encode'))));
        return;
      }
      if (!context.mounted) return;
      final fileName =
          'abelnotes_library_${DateTime.now().toIso8601String().split('T').first}.zip';
      if (Platform.isIOS || Platform.isMacOS) {
        final dir = await getTemporaryDirectory();
        final tmp = File(p.join(dir.path, fileName));
        await tmp.writeAsBytes(zipBytes);
        await SharePlus.instance.share(ShareParams(files: [XFile(tmp.path)]));
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: l10n.setExportLibrary,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['zip'],
        );
        if (savePath == null) return;
        await File(savePath).writeAsBytes(zipBytes);
      }
      if (!context.mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.setExportLibraryDone(entries.length))));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.setExportLibraryFailed(e.toString()))));
    }
  }

  String _sanitiseForFilename(String title) =>
      title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
}

/// Manual heal/recovery actions for the rare case where a notebook gets
/// stuck in a sync loop because of durable server-side corruption that
/// the verified upload/download paths can no longer prevent (i.e. bytes
/// that were already poisoned before the verifications shipped).
class _AdvancedSection extends ConsumerWidget {
  const _AdvancedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final notebooksAsync = ref.watch(notebookListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.setSectionAdvanced),
        Text(
          l10n.setAdvancedIntro,
          style: TextStyle(fontSize: 14, color: p.ink2, height: 1.5),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.setForceReloadTitle,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: p.ink0),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            l10n.setForceReloadDesc,
            style: TextStyle(fontSize: 12, color: p.ink2, height: 1.5),
          ),
        ),
        notebooksAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Text(l10n.setErrorGeneric(e.toString()),
              style: TextStyle(fontSize: 12, color: p.ink2)),
          data: (entries) => Column(
            children: [
              for (final entry in entries)
                _Row(
                  title: entry.metadata.title,
                  sub: l10n.setPagesCount(entry.metadata.pageCount),
                  control: HwButton(
                    label: l10n.setReload,
                    style: HwButtonStyle.solid,
                    onPressed: () =>
                        _forceReload(context, ref, entry.metadata.id,
                            entry.metadata.title, entry.remotePath),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _forceReload(BuildContext context, WidgetRef ref,
      String notebookId, String title, String remotePath) async {
    final l10n = AppLocalizations.of(context);
    // Block reload of the currently-open notebook — replacing its on-disk
    // bytes while the canvas holds an older state in memory leads to
    // a save-after-reload that re-publishes the stale state.
    final canvas = ref.read(canvasProvider);
    if (canvas != null && canvas.metadata.id == notebookId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.setCloseNotebookFirst)),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.setReloadConfirmTitle(title)),
        content: Text(l10n.setReloadConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.setCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.setReload)),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.setReloadInProgress(title)),
        duration: const Duration(seconds: 30)));

    try {
      final syncService = ref.read(syncServiceProvider);
      final fileService = ref.read(fileServiceProvider);
      if (syncService == null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.setNotConnectedWebdav)));
        return;
      }

      final result = await syncService.downloadExplodedFull(notebookId);
      final bytes = SyncService.buildPackageBytes(
        metadata: result.metadata,
        document: result.document,
        pages: result.pages,
        assets: result.assets,
        symbolLibraries: result.symbolLibraries,
      );
      await fileService.saveNotebookFile(notebookId, bytes);
      await fileService.upsertNotebookMeta(
        id: notebookId,
        title: result.metadata.title,
        remotePath: remotePath,
        localModifiedAt: result.metadata.modifiedAt,
        syncStatus: 'synced',
        fileSize: bytes.length,
        coverColor: result.metadata.coverColor,
        paperType: result.metadata.paperType,
        pageCount: result.metadata.pageCount,
        createdAt: result.metadata.createdAt,
      );

      // Wipe the per-notebook sync caches so the next open re-runs the
      // delta diff from a clean slate (no stale ETags blocking refresh).
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('delta_meta_etag_$notebookId');
      // Must match _pageEtagsPrefsKey in canvas_provider.dart — previously
      // wrote 'last_page_etags_…' which silently no-op'd, leaving the user's
      // last-resort recovery only half-effective.
      await prefs.remove('page_etags_$notebookId');
      // Also drain the persistent delete queue so a stale backlog from the
      // wedged session doesn't immediately re-poison the freshly reloaded
      // state.
      await prefs.remove('pending_page_deletes_$notebookId');
      await prefs.remove('pending_asset_deletes_$notebookId');

      // Refresh the library card to reflect the new pageCount immediately.
      // Skip if the settings page was disposed while the long-running download
      // was in flight — touching `ref` after disposal throws
      // "Bad state: Cannot use 'ref' after the widget was disposed."
      if (context.mounted) {
        await ref.read(notebookListProvider.notifier).refresh();
      }

      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text(
              l10n.setReloadDone(title, result.metadata.pageCount))));
    } catch (e) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text(l10n.setReloadFailed(e.toString())),
          duration: const Duration(seconds: 6)));
    }
  }
}

class _AboutSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.setSectionAbout),
        Row(
          children: [
            Image.asset(
              'assets/branding/logo.png',
              width: 40,
              height: 40,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(width: 12),
            Text(l10n.setAboutAppName,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: p.ink0)),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.setAboutTagline,
            style: TextStyle(fontSize: 14, color: p.ink1, height: 1.7)),
        const SizedBox(height: 4),
        Text(l10n.setAboutOffline,
            style: TextStyle(fontSize: 14, color: p.ink1, height: 1.7)),
        const SizedBox(height: 12),
        Text(
            l10n.setAboutVersion(
                AppConfig.fullVersion, AppConfig.gitCommit),
            style: TextStyle(
                fontSize: 12,
                color: p.ink2,
                fontFamily: HwTheme.fontMono)),
        const SizedBox(height: 32),
        _Row(
            title: l10n.setReportProblem,
            sub: l10n.setReportProblemSub,
            control: HwButton(
                label: l10n.setCopyLog,
                style: HwButtonStyle.solid,
                onPressed: () => _copyLog(context))),
        const SizedBox(height: 16),
        _Row(
            title: l10n.setOpenSourceLicenses,
            sub: l10n.setOpenSourceLicensesSub,
            control: HwButton(
                label: l10n.setOpenSourceLicenses,
                style: HwButtonStyle.solid,
                onPressed: () => showLicensePage(
                    context: context,
                    applicationName: l10n.setAboutAppName,
                    applicationVersion: AppConfig.fullVersion))),
      ],
    );
  }

  Future<void> _copyLog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final log = await CrashLogger.read();
    await Clipboard.setData(ClipboardData(
        text: log.isEmpty ? l10n.setReportProblemEmpty : log));
    messenger.showSnackBar(SnackBar(
        content: Text(
            log.isEmpty ? l10n.setReportProblemEmpty : l10n.setCopyLogDone)));
  }
}
