/// The text sent to emergency contacts who do not use Drivalry (docs/01 §4.5).
/// A maps link is the only location that ever leaves the phone by SMS.
String crashMessage({
  required String name,
  required double lat,
  required double lon,
}) {
  final link =
      'https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
  return "Drivalry: $name's phone detected a possible crash at $link. "
      'They have not responded.';
}

/// Digits and a leading plus only; everything else people type into a phone
/// field (spaces, dashes, brackets) is dropped.
String normalisePhone(String raw) {
  final kept = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == '+' && kept.isEmpty) {
      kept.write(c);
    } else if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
      kept.write(c);
    }
  }
  return kept.toString();
}

/// An `sms:` URI that opens the composer prefilled for every number.
///
/// iOS separates recipients with commas and takes the body after `&`;
/// Android (and the RFC) use `;` between numbers and `?body=`.
Uri crashSmsUri({
  required List<String> numbers,
  required String body,
  required bool ios,
}) {
  final cleaned = [
    for (final n in numbers)
      if (normalisePhone(n).isNotEmpty) normalisePhone(n),
  ];
  final recipients = cleaned.join(ios ? ',' : ';');
  final encoded = Uri.encodeComponent(body);
  return Uri.parse(
    ios ? 'sms:$recipients&body=$encoded' : 'sms:$recipients?body=$encoded',
  );
}
