// Renders every piece of brand and store art from the one painter in
// `lib/app/brand/drivalry_mark.dart` and from real screens with seeded data.
//
//   DRIVALRY_ART=1 flutter test test/art
//   DRIVALRY_ART=1 DRIVALRY_ART_ONLY=icons,01-drive flutter test test/art
//
// Without DRIVALRY_ART the suite skips, so CI never rewrites the PNGs.
// Outputs: app/android/.../mipmap-*, app/ios/Runner/Assets.xcassets,
// store/ (Play and App Store listing graphics), docs/assets/.
import 'dart:convert';
import 'dart:io';

import 'package:drivalry/app/brand/drivalry_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sqlite_support.dart';
import '../support/widget_support.dart';
import 'art_harness.dart';
import 'brand_graphics.dart';
import 'scenes/scenes.dart';

void main() {
  if (!artEnabled) {
    test(
      'store art renderer',
      () {},
      skip: 'set $artEnv=1 to render the icons and store graphics',
    );
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadArtFonts);
  final only = artOnly;
  bool wanted(String id) => only.isEmpty || only.contains(id);

  group('icons', () {
    testWidgets(
      'Android launcher: legacy, adaptive layers, monochrome',
      (tester) async {
        const densities = {
          'mdpi': 1.0,
          'hdpi': 1.5,
          'xhdpi': 2.0,
          'xxhdpi': 3.0,
          'xxxhdpi': 4.0,
        };
        for (final MapEntry(key: name, value: d) in densities.entries) {
          final dir = 'android/app/src/main/res/mipmap-$name';
          final layer = (108 * d).round();
          final legacy = (48 * d).round();

          // Adaptive foreground: artwork inside the 66 dp safe zone of 108 dp.
          await writePng(
            appPath('$dir/ic_launcher_foreground.png'),
            await renderPng(
              tester,
              DrivalryMark(size: layer.toDouble(), contentScale: 0.74),
              width: layer,
              height: layer,
              alpha: true,
            ),
          );
          await writePng(
            appPath('$dir/ic_launcher_monochrome.png'),
            await renderPng(
              tester,
              DrivalryMark(
                size: layer.toDouble(),
                style: MarkStyle.monochrome,
                contentScale: 0.74,
              ),
              width: layer,
              height: layer,
              alpha: true,
            ),
          );
          await writePng(
            appPath('$dir/ic_launcher_background.png'),
            await renderPng(
              tester,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: DrivalryBrand.backgroundGradient,
                ),
              ),
              width: layer,
              height: layer,
            ),
          );

          // Legacy launcher icons (Android 7 and older): 48 dp with the shape
          // baked in and a 2 dp transparent margin.
          for (final (file, radius) in [
            ('ic_launcher.png', 0.2),
            ('ic_launcher_round.png', 0.5),
          ]) {
            await writePng(
              appPath('$dir/$file'),
              await renderPng(
                tester,
                Center(
                  child: DrivalryMark(
                    size: legacy - 4 * d,
                    background: DrivalryBrand.backgroundGradient,
                    backgroundRadiusFraction: radius,
                    contentScale: 0.9,
                  ),
                ),
                width: legacy,
                height: legacy,
                alpha: true,
              ),
            );
          }
        }
      },
      skip: !wanted('icons'),
    );

    testWidgets('Play Store icon 512', (tester) async {
      await writePng(
        repoPath('store/play/icon-512.png'),
        await renderPng(
          tester,
          const DrivalryMark(
            size: 512,
            background: DrivalryBrand.backgroundGradient,
          ),
          width: 512,
          height: 512,
        ),
      );
    }, skip: !wanted('icons'));

    testWidgets('iOS AppIcon set and App Store icon 1024', (tester) async {
      final setDir = appPath('ios/Runner/Assets.xcassets/AppIcon.appiconset');
      final contents =
          jsonDecode(File('$setDir/Contents.json').readAsStringSync())
              as Map<String, dynamic>;
      final done = <String>{};
      for (final img in contents['images'] as List) {
        final m = img as Map<String, dynamic>;
        final file = m['filename'] as String;
        if (!done.add(file)) continue;
        final pt = double.parse((m['size'] as String).split('x').first);
        final scale = int.parse((m['scale'] as String).replaceAll('x', ''));
        final px = (pt * scale).round();
        final bytes = await renderPng(
          tester,
          DrivalryMark(
            size: px.toDouble(),
            background: DrivalryBrand.backgroundGradient,
          ),
          width: px,
          height: px,
        );
        await writePng('$setDir/$file', bytes);
        if (px == 1024) {
          await writePng(repoPath('store/appstore/icon-1024.png'), bytes);
        }
      }
    }, skip: !wanted('icons'));

    testWidgets('iOS launch images', (tester) async {
      final dir = appPath('ios/Runner/Assets.xcassets/LaunchImage.imageset');
      for (final (file, scale) in [
        ('LaunchImage.png', 1),
        ('LaunchImage@2x.png', 2),
        ('LaunchImage@3x.png', 3),
      ]) {
        final px = 120 * scale;
        await writePng(
          '$dir/$file',
          await renderPng(
            tester,
            DrivalryMark(size: px.toDouble(), contentScale: 1),
            width: px,
            height: px,
            alpha: true,
          ),
        );
      }
    }, skip: !wanted('icons'));
  });

  group('brand graphics', () {
    testWidgets(
      'Play feature graphic, social preview, README banner',
      (tester) async {
        for (final (path, w, h) in [
          ('store/play/feature-graphic-1024x500.png', 1024, 500),
          ('store/social-preview-1280x640.png', 1280, 640),
          ('docs/assets/banner-1600x480.png', 1600, 480),
        ]) {
          await writePng(
            repoPath(path),
            await renderPng(
              tester,
              BrandBanner(width: w / 2, height: h / 2),
              width: w,
              height: h,
              pixelRatio: 2,
            ),
          );
        }
      },
      skip: !wanted('brand'),
    );
  });

  group('screenshots', () {
    final sqliteSkip = skipWithoutSqlite();
    for (final factory in sceneFactories) {
      final id = factory().id;
      for (final spec in shotSpecs) {
        testWidgets(
          '$id at ${spec.width}x${spec.height}',
          (tester) async {
            final scene = factory();
            try {
              final widget = await scene.build();
              final png = await renderPng(
                tester,
                StoreFrame(
                  headline: scene.headline,
                  subline: scene.subline,
                  scene: widget,
                  logicalHeight: spec.logicalHeight,
                ),
                width: spec.width,
                height: spec.height,
                pixelRatio: spec.pixelRatio,
                settle: scene.settle,
                prepare: scene.prepare,
              );
              await writePng(repoPath('${spec.folder}/$id.png'), png);
            } finally {
              await unmountAndSettle(tester);
              await scene.dispose();
            }
          },
          skip: sqliteSkip != null || !wanted(id),
        );
      }
    }
  });
}
