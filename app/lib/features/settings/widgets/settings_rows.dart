import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// One tonal surface holding a run of [SettingsRow]s. Space, not dividers,
/// separates the rows (docs/12 §4); the group clips their ripples.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.tone = TileTone.resting,
  });

  final List<Widget> children;
  final TileTone tone;

  @override
  Widget build(BuildContext context) {
    return Tile(
      tone: tone,
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A settings row: optional icon or [leading], a title in `body` weight 600,
/// one caption line, and a trailing widget (a chevron when the row navigates).
/// [below] renders under the text for rows that hold a control such as a
/// SegmentedButton. Lives inside a [SettingsGroup] or any other Material.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.caption,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.below,
    this.danger = false,
    this.captionColor,
    this.haptic = true,
  });

  final String title;
  final String? caption;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? below;
  final bool danger;
  final Color? captionColor;

  /// Light tap haptic on [onTap]; switch rows bring their own.
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : scheme.onSurface;
    final lead =
        leading ??
        (icon == null
            ? null
            : Icon(
                icon,
                size: 24,
                color: danger ? scheme.error : scheme.onSurfaceVariant,
              ));
    final trail =
        trailing ??
        (onTap == null
            ? null
            : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant));
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              if (haptic) Haptics.tap();
              onTap!();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.touch),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (lead != null) ...[lead, const SizedBox(width: Space.lg)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: context.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                        if (caption != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            caption!,
                            style: context.caption.copyWith(
                              color: captionColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trail != null) ...[
                    const SizedBox(width: Space.md),
                    trail,
                  ],
                ],
              ),
              if (below != null) ...[const SizedBox(height: Space.md), below!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A [SettingsRow] with a switch; tapping anywhere on the row toggles it and
/// fires the select haptic. A null [onChanged] disables both the switch and
/// the row.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.caption,
    this.icon,
  });

  final String title;
  final String? caption;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    void toggle(bool v) {
      Haptics.select();
      change!(v);
    }

    return SettingsRow(
      title: title,
      caption: caption,
      icon: icon,
      haptic: false,
      trailing: Switch(value: value, onChanged: change == null ? null : toggle),
      onTap: change == null ? null : () => toggle(!value),
    );
  }
}
