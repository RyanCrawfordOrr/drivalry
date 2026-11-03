import 'dart:convert';

import 'package:drivalry/tracking/weather.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show Weather;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('WMO codes map to the three buckets', () {
    expect(weatherFromWmoCode(0), Weather.clear);
    expect(weatherFromWmoCode(3), Weather.clear);
    expect(weatherFromWmoCode(45), Weather.clear); // fog
    expect(weatherFromWmoCode(51), Weather.rain);
    expect(weatherFromWmoCode(63), Weather.rain);
    expect(weatherFromWmoCode(67), Weather.rain);
    expect(weatherFromWmoCode(71), Weather.snow);
    expect(weatherFromWmoCode(77), Weather.snow);
    expect(weatherFromWmoCode(81), Weather.rain);
    expect(weatherFromWmoCode(85), Weather.snow);
    expect(weatherFromWmoCode(86), Weather.snow);
    expect(weatherFromWmoCode(95), Weather.rain);
  });

  test('pickHour chooses the closest hour and gives up when too far', () {
    final body = {
      'hourly': {
        'time': ['2026-11-01T16:00', '2026-11-01T17:00', '2026-11-01T18:00'],
        'weather_code': [0, 61, 71],
      },
    };
    expect(
      OpenMeteoClient.pickHour(body, DateTime.utc(2026, 11, 1, 17, 20)),
      Weather.rain,
    );
    expect(
      OpenMeteoClient.pickHour(body, DateTime.utc(2026, 11, 1, 17, 50)),
      Weather.snow,
    );
    expect(
      OpenMeteoClient.pickHour(body, DateTime.utc(2026, 11, 3, 12)),
      isNull,
    );
    expect(
      OpenMeteoClient.pickHour(const {}, DateTime.utc(2026, 11, 1)),
      isNull,
    );
  });

  test('client never throws', () async {
    final failing = OpenMeteoClient(
      MockClient((_) async => http.Response('nope', 500)),
    );
    expect(await failing.weatherAt(1, 2, DateTime.utc(2026)), isNull);
    final throwing = OpenMeteoClient(
      MockClient((_) async => throw Exception('offline')),
    );
    expect(await throwing.weatherAt(1, 2, DateTime.utc(2026)), isNull);
    final ok = OpenMeteoClient(
      MockClient((req) async {
        expect(req.url.host, 'api.open-meteo.com');
        expect(req.url.queryParameters['hourly'], 'weather_code');
        return http.Response(
          jsonEncode({
            'hourly': {
              'time': ['2026-01-01T00:00'],
              'weather_code': [73],
            },
          }),
          200,
        );
      }),
    );
    expect(
      await ok.weatherAt(1, 2, DateTime.utc(2026, 1, 1, 0, 10)),
      Weather.snow,
    );
    expect(await const NoWeather().weatherAt(0, 0, DateTime.utc(2026)), isNull);
  });
}
