import 'package:drivalry/app/brand/drivalry_mark.dart';
import 'package:flutter/material.dart';

/// The Good Company wordmark and mark on a quiet aubergine field. The layout
/// scales for the Play feature graphic, social preview and README banner.
class BrandBanner extends StatelessWidget {
  const BrandBanner({
    super.key,
    required this.width,
    required this.height,
    this.tagline = 'Good drives. Good company.',
  });

  final double width;
  final double height;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final h = height;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: DrivalryBrand.ink,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: h * 0.15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Drivalry',
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w900,
                            fontSize: h * 0.25,
                            height: 1,
                            letterSpacing: -h * 0.008,
                            color: DrivalryBrand.paper,
                          ),
                        ),
                      ),
                      SizedBox(height: h * 0.045),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tagline,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w400,
                            fontSize: h * 0.085,
                            height: 1.1,
                            color: DrivalryBrand.paper,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: h * 0.08),
                DrivalryMark(size: h * 0.90),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
