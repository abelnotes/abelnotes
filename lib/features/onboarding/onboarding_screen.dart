import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/app_mode_provider.dart';
import 'package:abelnotes/features/auth/login_screen.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// First-run screen. Lets the user start immediately (local-only), connect
/// their own Nextcloud/WebDAV server, or (soon) use the managed AbelNotes
/// server. Themed with HwTheme so it matches the rest of the modern UI.
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

                  // ── Option 1: local-only, try now ──
                  _OnboardCard(
                    icon: 'pen',
                    accent: true,
                    title: l10n.onbTryNowTitle,
                    subtitle: l10n.onbTryNowSubtitle,
                    onTap: () async {
                      await ref.read(localModeProvider.notifier).enable();
                    },
                  ),
                  const SizedBox(height: 12),

                  // ── Option 2: personal server ──
                  _OnboardCard(
                    icon: 'cloud',
                    title: l10n.onbConnectNextcloudTitle,
                    subtitle: l10n.onbConnectNextcloudSubtitle,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ));
                    },
                  ),
                  const SizedBox(height: 12),

                  // ── Option 3: managed server (placeholder) ──
                  _OnboardCard(
                    icon: 'globe',
                    title: l10n.onbManagedServerTitle,
                    subtitle: l10n.onbManagedServerSubtitle,
                    badge: l10n.onbComingSoonBadge,
                    onTap: null, // disabled until the hosted server is live
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

class _OnboardCard extends StatefulWidget {
  final String icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool accent;
  final VoidCallback? onTap;

  const _OnboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.accent = false,
    required this.onTap,
  });

  @override
  State<_OnboardCard> createState() => _OnboardCardState();
}

class _OnboardCardState extends State<_OnboardCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final disabled = widget.onTap == null;
    final borderColor = widget.accent && !disabled ? p.accent : p.paper3;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: MouseRegion(
        cursor:
            disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (_hover && !disabled) ? p.paper2 : p.paper0,
              border: Border.all(
                  color: borderColor, width: widget.accent ? 1.5 : 1),
              borderRadius: BorderRadius.circular(HwTheme.rLg),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.accent ? p.accentSoft : p.paper2,
                    borderRadius: BorderRadius.circular(HwTheme.rMd),
                  ),
                  child: HwIcon(widget.icon,
                      size: 22,
                      color: widget.accent ? p.accentDeep : p.ink1),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              style: TextStyle(
                                fontFamily: HwTheme.fontSans,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: p.ink0,
                              ),
                            ),
                          ),
                          if (widget.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: HwTheme.teal.withValues(
                                    alpha: HwTheme.alphaMedium),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                widget.badge!,
                                style: const TextStyle(
                                  fontFamily: HwTheme.fontSans,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: HwTheme.teal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontFamily: HwTheme.fontSans,
                          fontSize: 13,
                          height: 1.4,
                          color: p.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!disabled) ...[
                  const SizedBox(width: 8),
                  HwIcon('chevron-right', size: 18, color: p.ink3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
