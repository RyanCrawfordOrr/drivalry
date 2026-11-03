import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../config/env.dart';
import '../../../data/db/database.dart';
import '../../../tracking/providers.dart';

/// ICE servers for the mesh (docs/10 §7). Public STUN always; Metered TURN
/// when the build carries the Metered values, cached for 12 hours in
/// `Settings`. Any failure falls back to STUN only, so direct connections
/// keep working and relayed ones fail honestly.
class IceServersProvider {
  IceServersProvider(
    this._db,
    this._http, {
    String? meteredDomain,
    String? meteredApiKey,
    int Function()? now,
    this.cacheTtl = const Duration(hours: 12),
  }) : _domain = meteredDomain ?? Env.meteredDomain,
       _apiKey = meteredApiKey ?? Env.meteredApiKey,
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final http.Client _http;
  final String _domain;
  final String _apiKey;
  final int Function() _now;
  final Duration cacheTtl;

  static const stunOnly = <Map<String, Object?>>[
    {'urls': 'stun:stun.l.google.com:19302'},
  ];
  static const cacheKey = 'ice_servers_json';
  static const cacheAtKey = 'ice_servers_at';

  bool get hasTurn => _domain.isNotEmpty && _apiKey.isNotEmpty;

  /// The list to hand to `createPeerConnection`, plus whether it includes a
  /// TURN relay.
  Future<({List<Map<String, Object?>> servers, bool relay})> servers() async {
    if (!hasTurn) return (servers: stunOnly, relay: false);
    final cached = await _cached();
    if (cached != null) return (servers: cached, relay: true);
    try {
      final uri = Uri.https(_domain, '/api/v1/turn/credentials', {
        'apiKey': _apiKey,
      });
      final res = await _http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw StateError('metered ${res.statusCode}');
      final list = jsonDecode(res.body);
      if (list is! List || list.isEmpty) throw StateError('empty ice list');
      final servers = [
        ...stunOnly,
        for (final s in list)
          if (s is Map) Map<String, Object?>.from(s),
      ];
      await _db.setSetting(cacheKey, jsonEncode(servers));
      await _db.setSetting(cacheAtKey, '${_now()}');
      return (servers: servers, relay: true);
    } catch (e) {
      debugPrint('ICE credentials unavailable, STUN only: $e');
      return (servers: stunOnly, relay: false);
    }
  }

  Future<List<Map<String, Object?>>?> _cached() async {
    final at = int.tryParse(await _db.getSetting(cacheAtKey) ?? '');
    if (at == null || _now() - at > cacheTtl.inMilliseconds) return null;
    final raw = await _db.getSetting(cacheKey);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return null;
      return [
        for (final s in list)
          if (s is Map) Map<String, Object?>.from(s),
      ];
    } catch (_) {
      return null;
    }
  }
}

final iceServersProvider = Provider<IceServersProvider>(
  (ref) => IceServersProvider(
    ref.watch(databaseProvider),
    ref.watch(httpClientProvider),
  ),
);
