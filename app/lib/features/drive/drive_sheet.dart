import 'package:flutter/material.dart';

import '../../app/ui/ui.dart';

/// Snap stops of the Drive sheet, as fractions of the Drive tab's height
/// (docs/12 §5 "Sheet physics": peek, half, full).
abstract final class DriveSheetSizes {
  /// Peek while idle: the handle and the first tile (the last trip).
  static const peekIdle = 0.34;

  /// Peek while recording: the live block and nothing else, so the map stays
  /// the stage.
  static const peekRecording = 0.46;
  static const half = 0.62;
  static const full = 0.92;
}

/// The draggable sheet under the Drive map: `surfaceContainerHigh`, the 28
/// radius, a handle, and three snap stops. When [recording] flips the sheet
/// animates to the matching peek so the live block is visible.
class DriveSheet extends StatefulWidget {
  const DriveSheet({
    super.key,
    required this.recording,
    required this.children,
  });

  final bool recording;

  /// Already in order: live block, prompts, last trip, recents. The sheet
  /// adds the gutters.
  final List<Widget> children;

  @override
  State<DriveSheet> createState() => _DriveSheetState();
}

class _DriveSheetState extends State<DriveSheet> {
  final _controller = DraggableScrollableController();

  double get _peek => widget.recording
      ? DriveSheetSizes.peekRecording
      : DriveSheetSizes.peekIdle;

  @override
  void didUpdateWidget(DriveSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recording != widget.recording) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.isAttached) return;
        _controller.animateTo(
          _peek,
          duration: Motion.screen,
          curve: Motion.standard,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      key: const Key('drive-sheet'),
      controller: _controller,
      initialChildSize: _peek,
      minChildSize: _peek,
      maxChildSize: DriveSheetSizes.full,
      snap: true,
      snapSizes: const [DriveSheetSizes.half],
      snapAnimationDuration: Motion.screen,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.sheetRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            0,
            Space.gutter,
            Space.xxxl,
          ),
          children: [const _Handle(), ...widget.children],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(top: Space.md, bottom: Space.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// The one tile that replaces the permission paragraphs once the first run
/// is over: tap to request what automatic detection still needs.
class AutoDetectTile extends StatelessWidget {
  const AutoDetectTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tile(
      key: const Key('auto-detect-tile'),
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.radar, color: scheme.primary),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Turn on auto-detect', style: context.title),
                const SizedBox(height: Space.xs),
                Text(
                  'Drives start on their own, even with the app closed.',
                  style: context.caption,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
