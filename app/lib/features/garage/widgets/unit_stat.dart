import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// A stat tile whose number counts up (docs/12 §5b) with the unit beside it
/// in `label`, never inside the figure (§3). When a tile is too narrow for
/// both, the unit drops under the number instead of cutting it, so a
/// two-column grid holds "12.3 L/100 km" at 360 wide. A null [value] shows
/// a dash.
class UnitStat extends StatelessWidget {
  const UnitStat({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.decimals = 0,
  });

  final num? value;
  final String label;
  final String? unit;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final number = context.title.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final v = value;
    return Tile(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v == null)
            Text('–', style: number)
          else
            // The title and label line boxes share a baseline offset, so
            // aligning their bottoms aligns the baselines.
            Wrap(
              spacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                AnimatedNumber(value: v, decimals: decimals, style: number),
                if (unit != null)
                  Text(
                    unit!,
                    style: context.label.copyWith(color: context.caption.color),
                  ),
              ],
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
