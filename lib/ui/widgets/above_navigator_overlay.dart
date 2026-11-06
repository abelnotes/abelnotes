import 'package:flutter/widgets.dart';

/// An Overlay for what the app draws above its Navigator (the pages tray,
/// the sign-in banner). Tooltips and menus there need one: the Navigator's
/// own Overlay sits below them, and a tooltip shown without one failed to
/// build and replaced its widget with a grey box.
class AboveNavigatorOverlay extends StatefulWidget {
  const AboveNavigatorOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<AboveNavigatorOverlay> createState() => _AboveNavigatorOverlayState();
}

class _AboveNavigatorOverlayState extends State<AboveNavigatorOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(AboveNavigatorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
