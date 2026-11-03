import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/env.dart';
import '../../tracking/providers.dart';
import 'google_quota.dart';
import 'routes_client.dart' show LatLon;

/// Stop categories a convoy can propose (docs/01 §4.6), mapped to Places
/// types.
enum StopCategory {
  gas('gas', 'Gas', ['gas_station']),
  food('food', 'Food', ['restaurant', 'fast_food_restaurant', 'cafe']),
  restroom('restroom', 'Restroom', ['rest_stop', 'gas_station']),
  photo('photo', 'Photo stop', ['tourist_attraction', 'scenic_spot', 'park']),
  lodging('lodging', 'Lodging', ['lodging', 'hotel', 'motel']),
  charging('charging', 'Charging', ['electric_vehicle_charging_station']);

  const StopCategory(this.wire, this.label, this.placeTypes);
  final String wire;
  final String label;
  final List<String> placeTypes;

  static StopCategory fromWire(String w) =>
      values.firstWhere((c) => c.wire == w, orElse: () => StopCategory.food);
}

/// One candidate stop.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.name,
    required this.location,
    this.address,
    this.rating,
    this.openNow,
  });

  final String placeId;
  final String name;
  final LatLon location;
  final String? address;
  final double? rating;
  final bool? openNow;
}

/// Google Places API (New) `searchNearby`, requesting only Essentials-tier
/// fields (id, displayName, location, formattedAddress) plus `rating` and
/// `currentOpeningHours.openNow`, which are Pro-tier: at most 150 calls a day
/// project-wide (hard cap in Cloud Console) and a per-device soft cap in
/// [GoogleQuota]. Past the cap the caller falls back to manual pins.
class PlacesClient {
  PlacesClient(this._http, this._quota, {String? apiKey})
    : _apiKey = apiKey ?? Env.googleMapsApiKey;

  final http.Client _http;
  final GoogleQuota _quota;
  final String _apiKey;

  static final Uri _nearby = Uri.parse(
    'https://places.googleapis.com/v1/places:searchNearby',
  );

  bool get configured => _apiKey.isNotEmpty;

  /// Places of [category] within [radiusM] of [center]. Returns null when the
  /// API is unavailable (no key, cap spent, network), so the UI can offer a
  /// manual pin instead; an empty list means "searched, nothing there".
  Future<List<PlaceSuggestion>?> nearby(
    LatLon center,
    StopCategory category, {
    double radiusM = 5000,
    int maxResults = 10,
  }) async {
    if (!configured) return null;
    if (!await _quota.tryConsume(GoogleQuota.places)) return null;
    try {
      final res = await _http
          .post(
            _nearby,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask':
                  'places.id,places.displayName,places.location,places.formattedAddress,places.rating,places.currentOpeningHours.openNow',
            },
            body: jsonEncode({
              'includedTypes': category.placeTypes,
              'maxResultCount': maxResults.clamp(1, 20),
              'rankPreference': 'DISTANCE',
              'locationRestriction': {
                'circle': {
                  'center': center.toJson(),
                  'radius': radiusM.clamp(1, 50000),
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 429) {
        await _quota.exhaust(GoogleQuota.places);
        return null;
      }
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final places = body['places'] as List? ?? const [];
      return [
        for (final p in places.cast<Map<String, dynamic>>())
          PlaceSuggestion(
            placeId: p['id'] as String,
            name:
                (p['displayName'] as Map<String, dynamic>?)?['text']
                    as String? ??
                'Unnamed',
            location: LatLon(
              ((p['location'] as Map<String, dynamic>)['latitude'] as num)
                  .toDouble(),
              ((p['location'] as Map<String, dynamic>)['longitude'] as num)
                  .toDouble(),
            ),
            address: p['formattedAddress'] as String?,
            rating: (p['rating'] as num?)?.toDouble(),
            openNow:
                (p['currentOpeningHours'] as Map<String, dynamic>?)?['openNow']
                    as bool?,
          ),
      ];
    } catch (_) {
      return null;
    }
  }
}

final placesClientProvider = Provider<PlacesClient>(
  (ref) => PlacesClient(
    ref.watch(httpClientProvider),
    ref.watch(googleQuotaProvider),
  ),
);
