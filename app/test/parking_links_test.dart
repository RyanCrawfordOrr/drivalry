import 'package:drivalry/features/drive/parking/parking_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('walk-back links per platform', () {
    final android = walkBackUri(
      lat: 38.8977,
      lon: -77.0365,
      platform: TargetPlatform.android,
    );
    expect(
      android.toString(),
      'google.navigation:q=38.897700,-77.036500&mode=w',
    );

    final ios = walkBackUri(
      lat: 38.8977,
      lon: -77.0365,
      platform: TargetPlatform.iOS,
    );
    expect(ios.host, 'maps.apple.com');
    expect(ios.queryParameters['daddr'], '38.897700,-77.036500');
    expect(ios.queryParameters['dirflg'], 'w');

    final web = walkBackUri(lat: 1, lon: 2, platform: TargetPlatform.windows);
    expect(web.host, 'www.google.com');
    expect(web.queryParameters['travelmode'], 'walking');
    expect(web.queryParameters['destination'], '1.000000,2.000000');
  });
}
