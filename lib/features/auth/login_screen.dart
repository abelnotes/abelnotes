import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/app_mode_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/services/webdav_service.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Connect-a-server screen. Pushed from onboarding (or Settings). On a
/// successful connection it stores credentials, leaves local-only mode,
/// and pops back — the auth gate then shows the library.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _serverController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;
  WebDavServerType _serverType = WebDavServerType.nextcloud;

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final creds = NextcloudCredentials(
      serverUrl: _serverController.text.trim(),
      username: _userController.text.trim(),
      password: _passController.text,
      serverType: _serverType,
    );

    final l10n = AppLocalizations.of(context);

    // Trust-on-first-use, SSH-style: fetch whatever certificate the server
    // presents right now and make the user confirm it BEFORE any real
    // request (credentials included) goes over this connection — not
    // trust-then-hope. Null means either plain HTTP (nothing to pin) or the
    // TCP/TLS probe itself failed, in which case testConnection() below
    // will surface the real error.
    final fingerprint =
        await WebDavService.probeCertificateFingerprint(creds.serverUrl);
    if (fingerprint != null) {
      final trusted = await _confirmCertificate(fingerprint);
      if (!trusted) {
        setState(() => _isLoading = false);
        return;
      }
    }
    if (!mounted) return;

    // Test connection with the (now user-confirmed) fingerprint pre-pinned
    // — a throwaway client so we never persist credentials that can't
    // actually reach the server.
    final webdav = WebDavService(
      serverUrl: creds.serverUrl,
      username: creds.username,
      password: creds.password,
      serverType: creds.serverType,
      pinnedCertFingerprint: fingerprint,
    );

    try {
      final connected = await webdav.testConnection();
      if (!connected) {
        setState(() {
          _error = webdav.certificateMismatchDetected
              ? l10n.logCertificateChanged
              : l10n.logConnectionFailed;
          _isLoading = false;
        });
        return;
      }

      await webdav.ensureBaseDirectory();
      await ref.read(credentialsProvider.notifier).login(
            NextcloudCredentials(
              serverUrl: creds.serverUrl,
              username: creds.username,
              password: creds.password,
              serverType: creds.serverType,
              certFingerprint: fingerprint,
            ),
          );
      // Connecting a server supersedes local-only mode.
      await ref.read(localModeProvider.notifier).disable();

      if (!mounted) return;
      // Pop back to whatever pushed us (onboarding / settings). The auth
      // gate rebuilds to the library now that credentials exist.
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = webdav.certificateMismatchDetected
            ? l10n.logCertificateChanged
            : l10n.logConnectionError(e.toString());
        _isLoading = false;
      });
    } finally {
      webdav.dispose();
    }
  }

  /// SSH-style "authenticity of host can't be established" prompt: shows
  /// the fingerprint the server just presented and blocks until the user
  /// explicitly accepts it. Runs BEFORE any credentialed request, so an
  /// attacker positioned for this exact connection is the only way TOFU's
  /// trust decision is ever wrong — and even then, this at least gives the
  /// user the chance to notice (comparing against the server's real
  /// fingerprint out of band) instead of trusting silently.
  Future<bool> _confirmCertificate(String fingerprint) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.logCertConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.logCertConfirmBody),
            const SizedBox(height: 12),
            SelectableText(
              WebDavService.formatFingerprint(fingerprint),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 13, letterSpacing: 0.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.setCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l10n.logCertConfirmTrust),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: Stack(
          children: [
            if (Navigator.of(context).canPop())
              Padding(
                padding: const EdgeInsets.all(8),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: HwIcon('chevron-left', size: 22, color: p.ink1),
                    tooltip: l10n.logBackTooltip,
                    onPressed:
                        _isLoading ? null : () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.accentSoft,
                            borderRadius: BorderRadius.circular(HwTheme.rLg),
                          ),
                          child: const HwIcon('cloud', size: 28),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.logTitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: HwTheme.fontSans,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: p.ink0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.logSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: HwTheme.fontSans,
                            fontSize: 14,
                            height: 1.5,
                            color: p.ink2,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _serverTypeSelector(p, l10n),
                        if (_serverType == WebDavServerType.generic) ...[
                          const SizedBox(height: 10),
                          Text(
                            l10n.logWebdavExperimental,
                            style: const TextStyle(
                              fontFamily: HwTheme.fontSans,
                              fontSize: 12,
                              height: 1.4,
                              color: HwTheme.syncConflict,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _field(
                          p,
                          controller: _serverController,
                          label: l10n.logServerUrlLabel,
                          hint: _serverType == WebDavServerType.nextcloud
                              ? l10n.logServerUrlHint
                              : l10n.logServerUrlHintWebdav,
                          icon: 'cloud',
                          keyboardType: TextInputType.url,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return l10n.logServerUrlRequired;
                            }
                            if (!v.trim().startsWith('http')) {
                              return l10n.logServerUrlInvalid;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _field(
                          p,
                          controller: _userController,
                          label: l10n.logUsernameLabel,
                          icon: 'home',
                          validator: (v) => v == null || v.trim().isEmpty
                              ? l10n.logUsernameRequired
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _field(
                          p,
                          controller: _passController,
                          label: l10n.logPasswordLabel,
                          icon: 'lock',
                          obscure: _obscurePassword,
                          onToggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          onSubmitted: (_) => _login(),
                          validator: (v) => v == null || v.isEmpty
                              ? l10n.logPasswordRequired
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _serverType == WebDavServerType.nextcloud
                              ? l10n.logAppPasswordHint
                              : l10n.logWebdavUrlHint,
                          style: TextStyle(
                            fontFamily: HwTheme.fontSans,
                            fontSize: 12,
                            color: p.ink3,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: HwTheme.syncConflict
                                  .withValues(alpha: HwTheme.alphaMedium),
                              borderRadius:
                                  BorderRadius.circular(HwTheme.rMd),
                            ),
                            child: Row(
                              children: [
                                const HwIcon('cloud-off',
                                    size: 18, color: HwTheme.syncConflict),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      fontFamily: HwTheme.fontSans,
                                      fontSize: 13,
                                      color: HwTheme.syncConflict,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _connectButton(p, l10n),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle a due opzioni Nextcloud/ownCloud ↔ WebDAV generico, nello
  /// stesso linguaggio visivo dei campi sottostanti (bordo, raggio, fill).
  Widget _serverTypeSelector(HwPalette p, AppLocalizations l10n) {
    Widget option(WebDavServerType type, String label) {
      final selected = _serverType == type;
      return Expanded(
        child: GestureDetector(
          onTap: _isLoading
              ? null
              : () => setState(() => _serverType = type),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? p.paper0 : Colors.transparent,
              borderRadius: BorderRadius.circular(HwTheme.rMd - 2),
              border: selected
                  ? Border.all(color: p.accent, width: 1.5)
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: HwTheme.fontSans,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? p.ink0 : p.ink2,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.paper2,
        borderRadius: BorderRadius.circular(HwTheme.rMd),
      ),
      child: Row(
        children: [
          option(WebDavServerType.nextcloud, l10n.logServerTypeNextcloud),
          const SizedBox(width: 3),
          option(WebDavServerType.generic, l10n.logServerTypeWebdav),
        ],
      ),
    );
  }

  Widget _field(
    HwPalette p, {
    required TextEditingController controller,
    required String label,
    required String icon,
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: TextStyle(
          fontFamily: HwTheme.fontSans, fontSize: 15, color: p.ink0),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: p.ink2),
        hintStyle: TextStyle(color: p.ink3),
        filled: true,
        fillColor: p.paper0,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: HwIcon(icon, size: 18, color: p.ink3),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 0),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                icon: HwIcon(obscure ? 'cloud-off' : 'check',
                    size: 18, color: p.ink3),
                onPressed: onToggleObscure,
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HwTheme.rMd),
          borderSide: BorderSide(color: p.paper3),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HwTheme.rMd),
          borderSide: BorderSide(color: p.paper3),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HwTheme.rMd),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _connectButton(HwPalette p, AppLocalizations l10n) {
    return MouseRegion(
      cursor:
          _isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isLoading ? null : _login,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isLoading ? p.ink2 : p.ink0,
            borderRadius: BorderRadius.circular(HwTheme.rMd),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: p.paper0),
                )
              : Text(
                  l10n.logConnectButton,
                  style: TextStyle(
                    fontFamily: HwTheme.fontSans,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.paper0,
                  ),
                ),
        ),
      ),
    );
  }
}
