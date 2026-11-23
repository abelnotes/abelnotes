import 'package:flutter/widgets.dart';

/// Owns a [TextEditingController] for a dialog's content and disposes it when
/// the route is gone. Disposing right after `await showDialog` breaks the
/// still-animating TextField (`_dependents.isEmpty` assertion).
class TextControllerScope extends StatefulWidget {
  const TextControllerScope({super.key, this.text, required this.builder});

  final String? text;
  final Widget Function(BuildContext context, TextEditingController controller)
      builder;

  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
