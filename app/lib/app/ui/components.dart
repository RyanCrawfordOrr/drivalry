import 'package:flutter/material.dart';

import 'haptics.dart';
import 'motion.dart';
import 'tokens.dart';
import 'typography.dart';

/// Shared building blocks (docs/12-ux-direction.md §4). Screens compose
/// these instead of styling Cards, Paddings and Texts by hand, so the whole
/// app moves together when a token changes.

/// Small uppercase label above a number or a section.
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.color, this.textAlign});
  final String text;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: textAlign,
      style: context.kicker.copyWith(color: color),
    );
  }
}

/// Kicker, optional trailing text action, then the content, with the
/// section gap below.
class EditorialSection extends StatelessWidget {
  const EditorialSection({
    super.key,
    required this.kicker,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.padding = Space.screen,
    this.gap = Space.section,
  });

  final String kicker;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: padding,
            child: Row(
              children: [
                Expanded(child: Kicker(kicker)),
                if (actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

enum TileTone { resting, raised, primary, danger }

/// Tonal rounded surface. No border, no shadow; [onTap] adds a ripple and a
/// light haptic.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tone = TileTone.resting,
    this.padding = const EdgeInsets.all(Space.gutter),
    this.radius,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final TileTone tone;
  final EdgeInsets padding;
  final BorderRadius? radius;

  /// Overrides [tone].
  final Color? color;

  static Color colorFor(ColorScheme scheme, TileTone tone) => switch (tone) {
    TileTone.resting => scheme.surfaceContainerLow,
    TileTone.raised => scheme.surfaceContainerHigh,
    TileTone.primary => scheme.primaryContainer,
    TileTone.danger => scheme.errorContainer,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = radius ?? Radii.cardRadius;
    final tappable = onTap != null || onLongPress != null;
    final surface = Material(
      color: color ?? colorFor(scheme, tone),
      borderRadius: r,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                Haptics.tap();
                onTap!();
              },
        onLongPress: onLongPress == null
            ? null
            : () {
                Haptics.select();
                onLongPress!();
              },
        child: Padding(padding: padding, child: child),
      ),
    );
    if (!tappable) return surface;
    // Passive PressScale: the InkWell keeps the tap and the ripple, the
    // whole tile gets the spring.
    return PressScale(child: surface);
  }
}

/// Kicker, big tabular number with its unit beside it, optional caption.
class HeroNumber extends StatelessWidget {
  const HeroNumber({
    super.key,
    required this.value,
    this.kicker,
    this.unit,
    this.caption,
    this.color,
    this.small = false,
    this.alignment = CrossAxisAlignment.start,
  });

  final String value;
  final String? kicker;
  final String? unit;
  final String? caption;
  final Color? color;
  final bool small;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final number = (small ? context.displaySmall : context.display).copyWith(
      color: color,
    );
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kicker != null) ...[
          Kicker(kicker!),
          const SizedBox(height: Space.sm),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: number),
            if (unit != null) ...[
              const SizedBox(width: Space.sm),
              Text(unit!, style: context.label.copyWith(color: color)),
            ],
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: Space.xs),
          Text(caption!, style: context.caption),
        ],
      ],
    );
  }
}

/// Small number plus label, for two- or three-column grids.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.color,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tile(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: color ?? context.caption.color),
            const SizedBox(height: Space.sm),
          ],
          Text(
            value,
            style: context.title.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Lays [StatTile]s out in fixed columns with the standard gaps.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.columns = 3});
  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(
        i,
        (i + columns).clamp(0, children.length),
      );
      rows.add(
        // IntrinsicHeight keeps tiles in a row the same height without
        // needing a bounded parent (lists and sheets give none).
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: Space.md),
                Expanded(
                  child: j < slice.length ? slice[j] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
      if (i + columns < children.length) {
        rows.add(const SizedBox(height: Space.md));
      }
    }
    return Column(children: rows);
  }
}

/// The one primary action on a screen state: 56 tall, full width.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = busy
        ? SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: danger ? scheme.onError : scheme.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22),
                const SizedBox(width: Space.sm),
              ],
              Text(label),
            ],
          );
    return SizedBox(
      height: Sizes.button,
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: danger
            ? FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              )
            : null,
        child: child,
      ),
    );
  }
}

/// Tonal companion to [PrimaryButton].
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Sizes.button,
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: Space.sm),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

enum PillTone { neutral, positive, warning, danger, live, primary }

/// Status capsule: a word or two, optional icon or dot.
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.tone = PillTone.neutral,
    this.icon,
    this.dot = false,
    this.compact = false,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;
  final bool dot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      PillTone.neutral => (scheme.surfaceContainerHigh, scheme.onSurface),
      PillTone.positive => (
        const Color(0xFF2ECC71).withValues(alpha: 0.18),
        const Color(0xFF2ECC71),
      ),
      PillTone.warning => (
        const Color(0xFFF1C40F).withValues(alpha: 0.18),
        const Color(0xFFF1C40F),
      ),
      PillTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
      PillTone.live => (scheme.primary, scheme.onPrimary),
      PillTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.sm : Space.md,
        vertical: compact ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: context.label.copyWith(color: fg)),
        ],
      ),
    );
  }
}

enum AvatarSize { sm, md, lg }

/// Initials (or an image) in a circle; [isMe] draws the primary ring.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.size = AvatarSize.md,
    this.image,
    this.isMe = false,
    this.color,
  });

  final String name;
  final AvatarSize size;
  final ImageProvider? image;
  final bool isMe;
  final Color? color;

  double get _dimension => switch (size) {
    AvatarSize.sm => 32,
    AvatarSize.md => 40,
    AvatarSize.lg => 56,
  };

  static String initials(String name) {
    final parts = name
        .replaceAll('@', '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = _dimension;
    final bg = color ?? scheme.surfaceContainerHighest;
    final fg = color != null ? Colors.white : scheme.onSurface;
    final circle = Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        image: image == null
            ? null
            : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image == null
          ? Text(
              initials(name),
              style: context.label.copyWith(
                color: fg,
                fontSize: d * 0.38,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
    if (!isMe) return circle;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: circle,
    );
  }
}

/// Kicker, headline, one line, one action. Never an icon in grey.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.headline,
    this.top = Space.xxxl,
    this.kicker,
    this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String headline;
  final String? kicker;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Space above the kicker. Under a LargeTitleBar, 16 to 24 reads right;
  /// the default suits a plain AppBar.
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kicker != null) ...[
            Kicker(kicker!),
            const SizedBox(height: Space.md),
          ],
          Text(headline, style: context.headline),
          if (body != null) ...[
            const SizedBox(height: Space.md),
            Text(body!, style: context.bodyMuted),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: Space.xl),
            PrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: Space.sm),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Modal bottom sheet with the house radius, handle and title.
Future<T?> showDrivalrySheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool scrollable = false,
}) {
  Haptics.select();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      // The sheet draws over the nav bar and home indicator, so the last row
      // must clear them as well as keep its own breathing room.
      final content = Padding(
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.xl + MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title, style: ctx.title),
              const SizedBox(height: Space.lg),
            ],
            builder(ctx),
          ],
        ),
      );
      if (!scrollable) return content;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            SingleChildScrollView(controller: controller, child: content),
      );
    },
  );
}

/// Thin progress bar used for score breakdowns and challenge progress.
class ThinBar extends StatelessWidget {
  const ThinBar({
    super.key,
    required this.fraction,
    this.color,
    this.height = 6,
  });

  final double fraction;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: scheme.surfaceContainerHighest),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0, 1).toDouble(),
              child: AnimatedContainer(
                duration: Motion.reveal,
                curve: Motion.enter,
                color: color ?? scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmering placeholder while a list loads; never a bare spinner.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key, this.height = 88});
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: Radii.cardRadius,
        ),
      ),
    );
  }
}
