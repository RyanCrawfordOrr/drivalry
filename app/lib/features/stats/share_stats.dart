import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../drive/share_card.dart' show renderWidgetToPng, shareCardSize;

/// Hands a rendered PNG to the OS share sheet. Tests override this to
/// capture the bytes instead of opening a sheet.
typedef ShareImage =
    Future<void> Function({
      required Uint8List png,
      required String fileName,
      required String text,
    });

final shareImageProvider = Provider<ShareImage>((_) => _sharePlus);

Future<void> _sharePlus({
  required Uint8List png,
  required String fileName,
  required String text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(png, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
      subject: 'My Drivalry stats',
    ),
  );
}

/// Renders [card] at the share-card size and shares it. The widget is built
/// outside the live tree, so it must not read providers.
Future<void> shareCardWidget(
  BuildContext context,
  WidgetRef ref, {
  required Widget card,
  required String fileName,
  required String text,
}) async {
  final share = ref.read(shareImageProvider);
  final png = await renderWidgetToPng(
    card,
    view: View.of(context),
    theme: Theme.of(context),
    logicalSize: shareCardSize,
  );
  await share(png: png, fileName: fileName, text: text);
}
