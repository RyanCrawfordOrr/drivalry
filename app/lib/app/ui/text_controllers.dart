import 'package:flutter/material.dart';

/// Owns the [TextEditingController]s used inside a sheet or dialog body.
///
/// A sheet is still on screen for its exit animation after `Navigator.pop`
/// returns, and the keyboard closing rebuilds it during that time. A
/// controller created in the calling function and disposed right after the
/// `await` is therefore used after disposal and the field throws. Build the
/// fields inside this widget instead; the controllers live exactly as long
/// as the fields do. Hand the typed text back through the pop value.
class TextControllers extends StatefulWidget {
  const TextControllers({
    super.key,
    this.initial = const [''],
    required this.builder,
  });

  /// Initial text for each controller, one entry per controller.
  final List<String> initial;

  final Widget Function(
    BuildContext context,
    List<TextEditingController> controllers,
  )
  builder;

  @override
  State<TextControllers> createState() => _TextControllersState();
}

class _TextControllersState extends State<TextControllers> {
  late final List<TextEditingController> _controllers = [
    for (final text in widget.initial) TextEditingController(text: text),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controllers);
}
