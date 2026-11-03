import 'dart:convert';

import 'package:drivalry_scoring/drivalry_scoring.dart' show Weather;
import 'package:http/http.dart' as http;

/// Maps a WMO weather interpretation code (as Open-Meteo reports) to the
/// engine's three buckets. Anything unknown is "clear".
Weather weatherFromWmoCode(int code) {
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return Weather.rain;
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return Weather.snow;
  }
  if (code >= 95) return Weather.rain; // thunderstorms
  return Weather.clear;
}

/// Weather at a place and time. Null means "don't know"; the engine then skips
/// the weather bonus.
abstract class WeatherClient {
  Future<Weather?> weatherAt(double lat, double lon, DateTime whenUtc);
}

/// Open-Meteo, one call per trip, non-commercial free tier (docs/03 §10).
/// Never throws: any failure is a null.
class OpenMeteoClient implements WeatherClient {
  OpenMeteoClient(this._http, {this.timeout = const Duration(seconds: 8)});

  final http.Client _http;
  final Duration timeout;

  @override
  Future<Weather?> weatherAt(double lat, double lon, DateTime whenUtc) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'hourly': 'weather_code',
        'past_days': '2',
        'forecast_days': '1',
        'timezone': 'UTC',
      });
      final res = await _http.get(uri).timeout(timeout);
      if (res.statusCode != 200) return null;
      return pickHour(jsonDecode(res.body) as Map<String, dynamic>, whenUtc);
    } catch (_) {
      return null;
    }
  }

  /// Picks the hourly code closest to [whenUtc] from an Open-Meteo response.
  static Weather? pickHour(Map<String, dynamic> body, DateTime whenUtc) {
    final hourly = body['hourly'] as Map<String, dynamic>?;
    final times = (hourly?['time'] as List?)?.cast<String>();
    final codes = (hourly?['weather_code'] as List?)?.cast<num?>();
    if (times == null || codes == null || times.isEmpty) return null;
    var bestIdx = -1;
    var bestDiff = double.infinity;
    for (var i = 0; i < times.length && i < codes.length; i++) {
      final t = DateTime.tryParse('${times[i]}Z');
      if (t == null || codes[i] == null) continue;
      final diff = (t.difference(whenUtc).inMinutes).abs().toDouble();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIdx = i;
      }
    }
    if (bestIdx < 0 || bestDiff > 90) return null;
    return weatherFromWmoCode(codes[bestIdx]!.toInt());
  }
}

/// For tests and offline builds: always "don't know".
class NoWeather implements WeatherClient {
  const NoWeather();

  @override
  Future<Weather?> weatherAt(double lat, double lon, DateTime whenUtc) async =>
      null;
}
