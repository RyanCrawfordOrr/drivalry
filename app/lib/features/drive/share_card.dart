import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drivalry_scoring/drivalry_scoring.dart'
    show Attention, Efficiency, Smoothness, SpeedUnits, Speeding;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../data/db/database.dart';
import '../../data/models/trip_score_view.dart';
import '../../data/repos/leagues_repo.dart';
import '../../widgets/units.dart';
import 'widgets/score_ring.dart';

/// Logical size of the shared image (4:5, the common social crop).
const Size shareCardSize = Size(1080, 1350);

/// The shareable trip card (docs/01 §4.9): score, components, the roast or
/// praise line, distance and duration. Deliberately no map, no route and no
/// place names, so sharing it never leaks where anyone went.
class ShareTripCard extends StatelessWidget {
  const ShareTripCard({
    super.key,
    required this.trip,
    required this.score,
    required this.units,
    this.handle,
    this.tier,
  });

  final Trip trip;
  final TripScoreView score;
  final SpeedUnits units;
  final String? handle;
  final LeagueTier? tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = score.reckless
        ? theme.colorScheme.error
        : DrivalryTheme.scoreColor(score.score);
    final date = DateFormat.yMMMEd().format(
      DateTime.fromMillisecondsSinceEpoch(trip.startedAt),
    );
    final duration = formatElapsed(
      Duration(seconds: score.summary.movingTimeS.round()),
    );
    final headline = score.roastText;
    final textOn = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Material(
      child: Container(
        width: shareCardSize.width,
        height: shareCardSize.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              Color.alphaBlend(
                color.withValues(alpha: 0.18),
                theme.colorScheme.surface,
              ),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(72, 72, 72, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DRIVE SCORE',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 34,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w800,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        date,
                        maxLines: 1,
                        style: TextStyle(fontSize: 30, color: muted),
                      ),
                    ],
                  ),
                ),
                if (score.reckless)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: color, width: 4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'RECKLESS',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            Center(
              child: ScoreRing(
                score: score.score,
                size: 400,
                stroke: 36,
                reckless: score.reckless,
                label: '+${score.xp} XP',
              ),
            ),
            const SizedBox(height: 40),
            if (headline != null)
              Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 38,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: textOn,
                ),
              ),
            const Spacer(),
            _Bars(score: score, color: color),
            const SizedBox(height: 36),
            Row(
              children: [
                _Stat(
                  label: 'DISTANCE',
                  value: formatDistance(score.summary.distanceM, units),
                ),
                const SizedBox(width: 48),
                _Stat(label: 'DRIVING', value: duration),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'drivalry',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: DrivalryTheme.seed,
                      ),
                    ),
                    if (handle != null)
                      Text(
                        '@$handle${tier != null ? ' · ${tier!.label}' : ''}',
                        style: TextStyle(fontSize: 28, color: muted),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.score, required this.color});
  final TripScoreView score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = score.penalties;
    final rows = <(String, double, double)>[
      ('Speed', p.speed, Speeding.cap),
      ('Smoothness', p.smoothness, Smoothness.cap),
      ('Attention', p.attention, Attention.cap),
      ('Efficiency', p.efficiency, Efficiency.cap),
    ];
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (label, penalty, cap) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 30,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LinearProgressIndicator(
                      value: (1 - penalty / cap).clamp(0, 1).toDouble(),
                      minHeight: 24,
                      color: color,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    penalty == 0 ? 'clean' : '−${penalty.toStringAsFixed(1)}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 28,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 24,
            letterSpacing: 3,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Renders [widget] at [logicalSize] in a detached render tree and returns
/// PNG bytes. Nothing is added to the live widget tree, so the card never
/// flashes on screen.
Future<Uint8List> renderWidgetToPng(
  Widget widget, {
  required ui.FlutterView view,
  required ThemeData theme,
  Size logicalSize = shareCardSize,
  double pixelRatio = 1.0,
}) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(logicalSize),
      physicalConstraints: BoxConstraints.tight(logicalSize * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
    child: RenderPositionedBox(alignment: Alignment.center, child: boundary),
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  final buildOwner = BuildOwner(focusManager: FocusManager());
  renderView.prepareInitialFrame();

  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(
      textDirection: ui.TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: logicalSize, devicePixelRatio: pixelRatio),
        child: Theme(
          data: theme,
          child: SizedBox.fromSize(size: logicalSize, child: widget),
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);

  buildOwner.buildScope(root);
  buildOwner.finalizeTree();
  pipelineOwner
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG encoding failed');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Best-effort handle lookup for the card footer; never blocks a share.
Future<String?> lookupHandle(SupabaseClient? client, String? userId) async {
  if (client == null || userId == null) return null;
  try {
    final row = await client
        .from('profiles')
        .select('handle')
        .eq('id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 2));
    return row?['handle'] as String?;
  } catch (_) {
    return null;
  }
}

/// Renders the card, writes it to a temp file and opens the share sheet.
Future<void> shareTripCard(
  BuildContext context, {
  required Trip trip,
  required TripScoreView score,
  required SpeedUnits units,
  String? handle,
  LeagueTier? tier,
}) async {
  final theme = Theme.of(context);
  final view = View.of(context);
  final png = await renderWidgetToPng(
    ShareTripCard(
      trip: trip,
      score: score,
      units: units,
      handle: handle,
      tier: tier,
    ),
    view: view,
    theme: theme,
  );
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, 'drivalry-trip-${trip.id}.png'));
  await file.writeAsBytes(png, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: score.reckless
          ? 'Drive Score ${score.score}. Reckless. I know.'
          : 'Drive Score ${score.score} on Drivalry.',
      subject: 'My Drive Score',
    ),
  );
}
