import 'package:flutter/foundation.dart';

/// Walking directions back to the car, in the platform's maps app.
Uri walkBackUri({
  required double lat,
  required double lon,
  required TargetPlatform platform,
}) {
  final ll = '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';
  switch (platform) {
    case TargetPlatform.android:
      return Uri.parse('google.navigation:q=$ll&mode=w');
    case TargetPlatform.iOS:
      return Uri.parse('https://maps.apple.com/?daddr=$ll&dirflg=w');
    default:
      return webWalkingUri(lat: lat, lon: lon);
  }
}

/// Works everywhere a browser does.
Uri webWalkingUri({required double lat, required double lon}) =>
    Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}',
      'travelmode': 'walking',
    });
