// Layout audit: renders a screen at real phone sizes, saves a PNG when
// DRIVALRY_LAYOUT=1 (under test/layout/out/, gitignored) and reports
// geometry problems. Fonts must be loaded first (`loadArtFonts`) and the
// app must use `artTheme()`, otherwise the test font's square glyphs make
// every measurement wrong.
//
//   DRIVALRY_LAYOUT=1 flutter test test/layout
//
// Blocking issues (fail the test): a layout exception such as a RenderFlex
// overflow, two visible text runs whose boxes intersect, text cut short by an
// ellipsis or a fade, text cut off by the screen edge outside a horizontal
// scroller. Text hidden under an opaque surface is ignored. Warnings (printed only): an empty
// band taller than [LayoutAudit.gapWarn] in the top half of the screen.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../art/art_harness.dart' show appDir, renderPng, writePng;

const layoutEnv = 'DRIVALRY_LAYOUT';
bool get layoutShots => Platform.environment[layoutEnv] == '1';

/// A device the audit renders at. Insets are logical pixels.
class PhoneSize {
  const PhoneSize(
    this.name,
    this.width,
    this.height, {
    this.dpr = 2,
    this.top = 24,
    this.bottom = 0,
  });
  final String name;
  final double width;
  final double height;
  final double dpr;
  final double top;
  final double bottom;

  @override
  String toString() => '$name ${width.round()}x${height.round()}';
}

/// A small Android phone with three-button navigation, and an iPhone with
/// a Dynamic Island and a home indicator.
const phoneSizes = [
  PhoneSize('android-small', 360, 780, top: 24, bottom: 48),
  PhoneSize('iphone', 390, 844, top: 47, bottom: 34),
];

class LayoutIssue {
  const LayoutIssue(this.kind, this.detail);
  final String kind;
  final String detail;
  bool get blocking => kind != 'gap';
  @override
  String toString() => '$kind: $detail';
}

class LayoutReport {
  LayoutReport(this.name, this.size, this.issues, this.pngPath);
  final String name;
  final PhoneSize size;
  final List<LayoutIssue> issues;
  final String? pngPath;
  List<LayoutIssue> get blocking => [
    for (final i in issues)
      if (i.blocking) i,
  ];
  String summary() => [
    '[layout] $name @ $size: ${issues.length} issue(s)'
        '${pngPath == null ? '' : ' -> $pngPath'}',
    for (final i in issues) '  - $i',
  ].join('\n');
}

class _Box {
  _Box(this.text, this.rect, this.ro);
  final String text;
  final Rect rect;
  final RenderParagraph ro;
}

abstract final class LayoutAudit {
  static const gapWarn = 72.0;
}

Future<LayoutReport> auditLayout(
  WidgetTester tester, {
  required String name,
  required Widget app,
  required PhoneSize size,
  Duration settle = const Duration(seconds: 2),
  Future<void> Function(WidgetTester tester)? prepare,
}) async {
  final inset = FakeViewPadding(
    top: size.top * size.dpr,
    bottom: size.bottom * size.dpr,
  );
  tester.view.padding = inset;
  tester.view.viewPadding = inset;
  addTearDown(tester.view.reset);

  final png = await renderPng(
    tester,
    app,
    width: (size.width * size.dpr).round(),
    height: (size.height * size.dpr).round(),
    pixelRatio: size.dpr,
    settle: settle,
    prepare: prepare,
  );

  final issues = <LayoutIssue>[];
  final error = tester.takeException();
  if (error != null) {
    issues.add(LayoutIssue('overflow', _firstLine(error.toString())));
  }

  final viewport = Offset.zero & Size(size.width, size.height);
  final boxes = <_Box>[];
  // allRenderObjects maps every element to its nearest render object, so a
  // paragraph shows up once per ancestor element; visit each one once.
  final seen = Set<RenderObject>.identity();
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
    if (!seen.add(ro)) continue;
    if (!_painted(ro)) continue;
    final rect = MatrixUtils.transformRect(
      ro.getTransformTo(null),
      Offset.zero & ro.size,
    );
    if (rect.isEmpty || !rect.overlaps(viewport)) continue;
    final text = ro.text.toPlainText().replaceAll('\n', ' ').trim();
    if (text.isEmpty || _isIconGlyph(text, ro)) continue;
    if (!_visible(tester, ro, rect, viewport)) continue;
    boxes.add(_Box(text, rect, ro));
  }

  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      final a = boxes[i], b = boxes[j];
      final x = a.rect.intersect(b.rect);
      if (x.width > 2 && x.height > 2 && !_related(a.ro, b.ro)) {
        issues.add(
          LayoutIssue(
            'overlap',
            '"${_short(a.text)}" ${_r(a.rect)} x "${_short(b.text)}" '
                '${_r(b.rect)}',
          ),
        );
      }
    }
    final r = boxes[i].rect;
    final p = boxes[i].ro;
    if (p.didExceedMaxLines || p.textSize.width > p.size.width + 1) {
      issues.add(
        LayoutIssue(
          'cut',
          '"${_short(boxes[i].text)}" ${_r(r)} is cut short (ellipsis or fade)',
        ),
      );
    }
    if ((r.left < -1 || r.right > size.width + 1) &&
        !_inHorizontalScroller(boxes[i].ro)) {
      issues.add(
        LayoutIssue(
          'clipped',
          '"${_short(boxes[i].text)}" ${_r(r)} runs past the screen edge',
        ),
      );
    }
  }

  // Empty bands in the top half: nothing drawn with words in them.
  boxes.sort((a, b) => a.rect.top.compareTo(b.rect.top));
  var bottomSoFar = size.top;
  var previous = 'the status bar';
  for (final b in boxes) {
    if (b.rect.top > size.height * 0.6) break;
    final gap = b.rect.top - bottomSoFar;
    if (gap > LayoutAudit.gapWarn) {
      issues.add(
        LayoutIssue(
          'gap',
          '${gap.round()} px empty between $previous and '
              '"${_short(b.text)}" (y ${b.rect.top.round()})',
        ),
      );
    }
    if (b.rect.bottom > bottomSoFar) {
      bottomSoFar = b.rect.bottom;
      previous = '"${_short(b.text)}"';
    }
  }

  String? pngPath;
  if (layoutShots) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    pngPath = '${appDir.path}/test/layout/out/${safe}_${size.name}.png';
    await writePng(pngPath, png);
  }
  final report = LayoutReport(name, size, issues, pngPath);
  stderr.writeln(report.summary());
  return report;
}

bool _painted(RenderObject ro) {
  RenderObject child = ro;
  var node = ro.parent;
  while (node != null) {
    if (node is RenderOffstage && node.offstage) return false;
    if (node is RenderOpacity && node.opacity == 0) return false;
    if (node is RenderAnimatedOpacity && node.opacity.value == 0) return false;
    if (node is RenderIndexedStack) {
      final shown = node.index;
      if (shown == null) return false;
      var i = 0;
      var c = node.firstChild;
      while (c != null && !identical(c, child)) {
        c = node.childAfter(c);
        i++;
      }
      if (i != shown) return false;
    }
    child = node;
    node = node.parent;
  }
  return true;
}

/// Whether the paragraph is what a person sees at [rect]: a hit test at a
/// point inside it has to reach the paragraph. Text under an opaque surface
/// (a sheet's barrier, a pinned app bar it has scrolled beneath) is not on
/// screen and must not count for overlaps or clipping.
bool _visible(
  WidgetTester tester,
  RenderParagraph ro,
  Rect rect,
  Rect viewport,
) {
  final shown = rect.intersect(viewport);
  if (shown.isEmpty) return false;
  final result = HitTestResult();
  tester.binding.hitTestInView(result, shown.center, tester.view.viewId);
  for (final entry in result.path) {
    if (identical(entry.target, ro)) return true;
  }
  // A pointer-ignoring ancestor keeps the paragraph out of the path while it
  // is still drawn; trust those.
  for (RenderObject? n = ro.parent; n != null; n = n.parent) {
    if (n is RenderIgnorePointer && n.ignoring) return true;
    if (n is RenderAbsorbPointer && n.absorbing) return true;
  }
  return false;
}

bool _related(RenderObject a, RenderObject b) {
  for (RenderObject? n = a.parent; n != null; n = n.parent) {
    if (identical(n, b)) return true;
  }
  for (RenderObject? n = b.parent; n != null; n = n.parent) {
    if (identical(n, a)) return true;
  }
  return false;
}

bool _inHorizontalScroller(RenderObject ro) {
  for (RenderObject? n = ro.parent; n != null; n = n.parent) {
    if (n is! RenderAbstractViewport) continue;
    // RenderViewportBase and SingleChildScrollView's private viewport both
    // expose `axisDirection`; the latter has no public type to test for.
    try {
      final dir = (n as dynamic).axisDirection as AxisDirection;
      if (axisDirectionToAxis(dir) == Axis.horizontal) return true;
    } on NoSuchMethodError {
      continue;
    }
  }
  return false;
}

/// Icons render as one private-use glyph; badges sit on them on purpose.
bool _isIconGlyph(String s, RenderParagraph ro) =>
    ro.text.style?.fontFamily == 'MaterialIcons' ||
    (s.runes.length == 1 && s.runes.first >= 0xE000);

String _firstLine(String s) => s.split('\n').first.trim();
String _short(String s) => s.length <= 40 ? s : '${s.substring(0, 37)}...';
String _r(Rect r) =>
    '[${r.left.round()},${r.top.round()} ${r.width.round()}x'
    '${math.max(0, r.height.round())}]';
