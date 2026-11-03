/// Shared plumbing for the store-art renderer (`render_art_test.dart`).
///
/// Everything here runs inside `flutter test`, which is the one headless
/// renderer the toolchain already ships: it draws with the same engine as the
/// phone, so the icons and screenshots match the app pixel for pixel. Real
/// fonts are loaded from the Flutter SDK's cache (Roboto, Material Icons)
/// because the test binding's default font is a placeholder.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drivalry/app/brand/drivalry_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_support.dart';

/// `DRIVALRY_ART=1 flutter test test/art` renders; without it the suite skips.
const artEnv = 'DRIVALRY_ART';

/// Comma-separated scene ids to render, for quick iteration. Empty = all.
const artOnlyEnv = 'DRIVALRY_ART_ONLY';

bool get artEnabled => Platform.environment[artEnv] == '1';

Set<String> get artOnly => {
  for (final s in (Platform.environment[artOnlyEnv] ?? '').split(','))
    if (s.trim().isNotEmpty) s.trim(),
};

/// `flutter test` runs with `app/` as the working directory.
final Directory appDir = Directory.current;
final Directory repoDir = appDir.parent;

String appPath(String rel) => '${appDir.path}${Platform.pathSeparator}$rel';
String repoPath(String rel) => '${repoDir.path}${Platform.pathSeparator}$rel';

Directory get flutterRoot {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && Directory(env).existsSync()) return Directory(env);
  // .../flutter/bin/cache/dart-sdk/bin/dart.exe
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 4; i++) {
    dir = dir.parent;
  }
  return dir;
}

Future<void> loadArtFonts() async {
  final fonts = Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  );
  stderr.writeln(
    '[art] fonts from ${fonts.path} '
    '(FLUTTER_ROOT=${Platform.environment['FLUTTER_ROOT']})',
  );
  if (!fonts.existsSync()) {
    throw StateError('Material fonts not found at ${fonts.path}');
  }
  Future<ByteData> bytes(String name) async {
    final data = await File('${fonts.path}/$name').readAsBytes();
    return data.buffer.asByteData();
  }

  final roboto = FontLoader('Roboto');
  for (final f in [
    'roboto-light.ttf',
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    roboto.addFont(bytes(f));
  }
  await roboto.load();

  final condensed = FontLoader('RobotoCondensed')
    ..addFont(bytes('robotocondensed-regular.ttf'))
    ..addFont(bytes('robotocondensed-bold.ttf'));
  await condensed.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('materialicons-regular.otf'));
  await icons.load();
}

/// Renders [widget] at exactly [width] x [height] pixels and returns PNG bytes.
///
/// The logical canvas is `width / pixelRatio` wide, so a frame designed at
/// 360 logical pixels renders a 1080 px image with `pixelRatio: 3`. With
/// [alpha] false the PNG has no alpha channel (the stores reject icons that
/// carry one).
Future<Uint8List> renderPng(
  WidgetTester tester,
  Widget widget, {
  required int width,
  required int height,
  double pixelRatio = 1,
  bool alpha = false,
  Duration settle = const Duration(milliseconds: 600),
  Future<void> Function(WidgetTester tester)? prepare,
}) async {
  stderr.writeln('[art] render ${width}x$height @$pixelRatio');
  final key = GlobalKey();
  tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
  tester.view.devicePixelRatio = pixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: SizedBox(
        width: width / pixelRatio,
        height: height / pixelRatio,
        child: widget,
      ),
    ),
  );
  await pumpFor(tester, settle);
  if (prepare != null) {
    await prepare(tester);
    await pumpFor(tester, const Duration(milliseconds: 400));
  }

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      png = encodePng(
        raw!.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
        image.width,
        image.height,
        alpha: alpha,
      );
    } finally {
      image.dispose();
    }
  });
  stderr.writeln('[art] encoded ${png.length} bytes');
  return png;
}

/// Synchronous on purpose: `testWidgets` bodies run in a fake-async zone where
/// an awaited real file write never completes, which hangs the renderer.
Future<void> writePng(String path, Uint8List bytes) async {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes, flush: true);
}

// ---------------------------------------------------------------------------
// PNG encoder. dart:ui only emits RGBA PNGs; Apple and Google refuse store
// icons with an alpha channel, so opaque outputs are re-encoded as RGB here.

Uint8List encodePng(
  Uint8List rgba,
  int width,
  int height, {
  bool alpha = true,
}) {
  final bpp = alpha ? 4 : 3;
  final stride = 1 + width * bpp;
  final raw = Uint8List(stride * height);
  var o = 0;
  var i = 0;
  for (var y = 0; y < height; y++) {
    raw[o++] = 0; // filter: none
    for (var x = 0; x < width; x++) {
      raw[o++] = rgba[i];
      raw[o++] = rgba[i + 1];
      raw[o++] = rgba[i + 2];
      if (alpha) raw[o++] = rgba[i + 3];
      i += 4;
    }
  }
  final idat = ZLibEncoder(level: 9).convert(raw);

  final out = BytesBuilder(copy: false);
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, alpha ? 6 : 2) // colour type
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(idat));
  _chunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out.add(typeBytes);
  out.add(data);
  final crc = _crc32(_crc32(0xFFFFFFFF, typeBytes), data) ^ 0xFFFFFFFF;
  final crcBytes = ByteData(4)..setUint32(0, crc);
  out.add(crcBytes.buffer.asUint8List());
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(int crc, Uint8List data) {
  var c = crc;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c;
}

// ---------------------------------------------------------------------------
// Store frames: a dark canvas with a headline and a phone showing a scene.

/// Logical width every frame is designed at; the pixel ratio supplies the
/// output resolution.
const frameLogicalWidth = 360.0;

/// Logical size of the phone screen a scene renders into. The phone mock-up
/// scales it down, so text stays crisp at any output size.
const sceneSize = Size(390, 844);

/// Status bar height the scene's MediaQuery reports, and the band the mock-up
/// paints its clock into.
const sceneStatusBar = 47.0;

/// Pixel sizes of the store screenshots.
class ShotSpec {
  const ShotSpec(this.folder, this.width, this.height);
  final String folder;
  final int width;
  final int height;

  double get pixelRatio => width / frameLogicalWidth;
  double get logicalHeight => height / pixelRatio;
}

const shotSpecs = [
  // Google Play: 9:16, at least 1080 px for featured placement.
  ShotSpec('store/play/phone', 1080, 1920),
  // App Store 6.9-inch (iPhone 16 Pro Max class), required.
  ShotSpec('store/appstore/iphone-6.9', 1320, 2868),
  // App Store 6.5-inch (iPhone 11 Pro Max / XS Max class), optional.
  ShotSpec('store/appstore/iphone-6.5', 1284, 2778),
];

/// Wraps a scene in the fake-device MediaQuery the phone mock-up expects.
Widget sceneViewport(Widget scene) {
  return MediaQuery(
    data: MediaQueryData(
      size: sceneSize,
      devicePixelRatio: 3,
      padding: const EdgeInsets.only(top: sceneStatusBar, bottom: 34),
      viewPadding: const EdgeInsets.only(top: sceneStatusBar, bottom: 34),
      platformBrightness: Brightness.dark,
      textScaler: TextScaler.noScaling,
    ),
    child: SizedBox(
      width: sceneSize.width,
      height: sceneSize.height,
      child: scene,
    ),
  );
}

class StoreFrame extends StatelessWidget {
  const StoreFrame({
    super.key,
    required this.headline,
    required this.subline,
    required this.scene,
    required this.logicalHeight,
    this.accent = DrivalryBrand.orange,
  });

  final String headline;
  final String subline;
  final Widget scene;
  final double logicalHeight;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tall = logicalHeight > 700;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: frameLogicalWidth,
        height: logicalHeight,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A2235), Color(0xFF0E1320)],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: -120,
                top: -140,
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: 0.35),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -150,
                bottom: -60,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        DrivalryBrand.teal.withValues(alpha: 0.18),
                        DrivalryBrand.teal.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, tall ? 56 : 40, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w900,
                            fontSize: 30,
                            height: 1.05,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subline,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w400,
                            fontSize: 15,
                            height: 1.3,
                            color: Color(0xFFB9C1D1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: tall ? 28 : 20),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: PhoneMock(scene: scene),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A phone body around a scaled scene, with a painted status bar.
class PhoneMock extends StatelessWidget {
  const PhoneMock({super.key, required this.scene, this.width = 302});

  final Widget scene;
  final double width;

  @override
  Widget build(BuildContext context) {
    const bezel = 9.0;
    final screenWidth = width - bezel * 2;
    final scale = screenWidth / sceneSize.width;
    final screenHeight = sceneSize.height * scale;
    return Container(
      width: width,
      height: screenHeight + bezel * 2,
      decoration: BoxDecoration(
        color: const Color(0xFF07090E),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      padding: const EdgeInsets.all(bezel),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          width: screenWidth,
          height: screenHeight,
          child: Stack(
            children: [
              FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                child: sceneViewport(scene),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: sceneStatusBar * scale,
                child: IgnorePointer(child: _StatusBar(scale: scale)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w600,
      fontSize: 15 * scale,
      color: Colors.white,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(28 * scale, 14 * scale, 24 * scale, 0),
      child: Row(
        children: [
          Text('9:41', style: style),
          const Spacer(),
          Icon(
            Icons.signal_cellular_alt,
            size: 16 * scale,
            color: Colors.white,
          ),
          SizedBox(width: 5 * scale),
          Icon(Icons.wifi, size: 16 * scale, color: Colors.white),
          SizedBox(width: 5 * scale),
          Icon(Icons.battery_full, size: 16 * scale, color: Colors.white),
        ],
      ),
    );
  }
}
