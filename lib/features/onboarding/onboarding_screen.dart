import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/app_mode_provider.dart';
import 'package:abelnotes/features/sync/drive_connect.dart';
import 'package:abelnotes/features/auth/login_screen.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// First-run screen. Asks one question — where the notebooks should live —
/// and answers it with the two services by their own marks, because a
/// generic cloud glyph made the user tap to find out which was which.
/// Starting with no sync at all stays a full-width button underneath: it is
/// subordinate to the question, not hidden from it.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Brand ──
                  Image.asset(
                    'assets/branding/logo.png',
                    width: 72,
                    height: 72,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.onbAppName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: HwTheme.fontSans,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: p.ink0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.onbTagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: HwTheme.fontSans,
                      fontSize: 15,
                      height: 1.5,
                      color: p.ink2,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── The question ──
                  Text(
                    l10n.onbSyncQuestion,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: HwTheme.fontSans,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: p.ink0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.onbSyncQuestionSub,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: HwTheme.fontSans,
                      fontSize: 13,
                      height: 1.4,
                      color: p.ink2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── The two answers, side by side and equal ──
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _SyncChoice(
                            logo: 'assets/branding/google-drive.png',
                            label: l10n.onbDriveShort,
                            note: driveSignInSupported
                                ? null
                                : l10n.onbDriveUnavailable,
                            onTap: driveSignInSupported
                                ? () async {
                                    if (await connectDrive(context, ref)) {
                                      // Onboarding's question is answered;
                                      // the gate also accepts a Drive account
                                      // on its own.
                                      await ref
                                          .read(localModeProvider.notifier)
                                          .enable();
                                    }
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SyncChoice(
                            logo: 'assets/branding/nextcloud.png',
                            label: l10n.onbNextcloudShort,
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Neither: local-only ──
                  _SecondaryButton(
                    label: l10n.onbStartWithoutSync,
                    onTap: () async {
                      await ref.read(localModeProvider.notifier).enable();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.onbTryNowSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: HwTheme.fontSans,
                      fontSize: 12,
                      height: 1.4,
                      color: p.ink3,
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    l10n.onbLicenseNote,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: HwTheme.fontSans,
                      fontSize: 12,
                      height: 1.4,
                      color: p.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One sync destination, shown by its own mark.
///
/// Both marks are the services' official artwork and are never tinted: their
/// colours are the recognisable part, and recolouring them is what their
/// brand guidelines forbid.
class _SyncChoice extends StatefulWidget {
  final String logo;
  final String label;
  final String? note;
  final VoidCallback? onTap;

  const _SyncChoice({
    required this.logo,
    required this.label,
    this.note,
    required this.onTap,
  });

  @override
  State<_SyncChoice> createState() => _SyncChoiceState();
}

class _SyncChoiceState extends State<_SyncChoice> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final disabled = widget.onTap == null;

    final logo = Image.asset(
      widget.logo,
      height: 32,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            decoration: BoxDecoration(
              color: (_hover && !disabled) ? p.paper2 : p.paper0,
              border: Border.all(color: p.paper3),
              borderRadius: BorderRadius.circular(HwTheme.rLg),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 52, child: Center(child: logo)),
                const SizedBox(height: 12),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: HwTheme.fontSans,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink0,
                  ),
                ),
                if (widget.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.note!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: HwTheme.fontSans,
                      fontSize: 11,
                      height: 1.3,
                      color: p.ink3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width, quiet, and still unmistakably a button: the way out of the
/// question without making it look like the wrong answer.
class _SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton({required this.label, required this.onTap});

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? p.paper2 : Colors.transparent,
            border: Border.all(color: p.paper3),
            borderRadius: BorderRadius.circular(HwTheme.rLg),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: HwTheme.fontSans,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.ink1,
            ),
          ),
        ),
      ),
    );
  }
}
