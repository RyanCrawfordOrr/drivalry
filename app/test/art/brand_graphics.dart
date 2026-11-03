import 'package:drivalry/app/brand/drivalry_mark.dart';
import 'package:flutter/material.dart';

/// Wordmark plus tagline on the dark brand field. Used for the Play feature
/// graphic (1024x500), the GitHub social preview (1280x640) and the README
/// banner (1600x480); everything scales from the logical height.
class BrandBanner extends StatelessWidget {
  const BrandBanner({
    super.key,
    required this.width,
    required this.height,
    this.tagline = 'The step challenge for driving.',
    this.chips = const [
      'Drive Score 0 to 100',
      'Friend leagues',
      'Convoy radio',
      'Roasts, not speed',
    ],
  });

  final double width;
  final double height;
  final String tagline;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final h = height;
    final tile = h * 0.58;
    final showChips = width / height > 1.9;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1C2639), Color(0xFF0E1320)],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // A huge faint ribbon as texture.
              Positioned(
                right: -h * 0.55,
                top: -h * 0.45,
                child: Opacity(
                  opacity: 0.07,
                  child: DrivalryMark(
                    size: h * 1.9,
                    style: MarkStyle.monochrome,
                    contentScale: 1,
                  ),
                ),
              ),
              Positioned(
                right: -h * 0.3,
                top: -h * 0.5,
                child: Container(
                  width: h * 1.3,
                  height: h * 1.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        DrivalryBrand.orange.withValues(alpha: 0.30),
                        DrivalryBrand.orange.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: h * 0.14),
                child: Row(
                  children: [
                    DrivalryMark.tile(size: tile),
                    SizedBox(width: h * 0.12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: width - tile - h * 0.4,
                          padding: EdgeInsets.symmetric(vertical: h * 0.07),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drivalry',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w900,
                                  fontSize: h * 0.2,
                                  height: 1,
                                  letterSpacing: -h * 0.006,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: h * 0.035),
                              Text(
                                tagline,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w400,
                                  fontSize: h * 0.082,
                                  height: 1.15,
                                  color: const Color(0xFFC9D0DD),
                                ),
                              ),
                              if (showChips) ...[
                                SizedBox(height: h * 0.065),
                                Wrap(
                                  spacing: h * 0.03,
                                  runSpacing: h * 0.025,
                                  children: [
                                    for (final c in chips) _Chip(text: c, h: h),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.h});
  final String text;
  final double h;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: h * 0.045, vertical: h * 0.018),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(h),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w500,
          fontSize: h * 0.054,
          color: const Color(0xFFE6EAF2),
        ),
      ),
    );
  }
}
