import 'dart:ui' as ui;

import 'package:drivalry/app/brand/drivalry_mark.dart';
import 'package:drivalry/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x < y ? x : y) + 0.05);
}

void main() {
  test('brand colors and key text roles retain sufficient contrast', () {
    expect(DrivalryBrand.ink, const Color(0xFF392837));
    expect(DrivalryBrand.paper, const Color(0xFFF9ECDD));
    expect(DrivalryBrand.coral, const Color(0xFFF08566));
    for (final theme in [DrivalryTheme.light(), DrivalryTheme.dark()]) {
      final c = theme.colorScheme;
      expect(contrast(c.onSurface, c.surface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(c.onSurfaceVariant, c.surfaceContainerLow),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      expect(
        contrast(c.onPrimaryContainer, c.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('mark keeps its cream, coral and open counter', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: const DrivalryMark(
              size: 200,
              background: DrivalryBrand.backgroundGradient,
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        Color at(int x, int y) {
          final offset = (y * image.width + x) * 4;
          return Color.fromARGB(
            data.getUint8(offset + 3),
            data.getUint8(offset),
            data.getUint8(offset + 1),
            data.getUint8(offset + 2),
          );
        }

        return [
          at(10, 10),
          at(130, 60),
          at(100, 119),
          at(100, 100),
          at(140, 119),
        ];
      } finally {
        image.dispose();
      }
    });
    expect(pixels, [
      DrivalryBrand.ink,
      DrivalryBrand.paper,
      DrivalryBrand.coral,
      DrivalryBrand.ink,
      DrivalryBrand.ink,
    ]);
  });
}
