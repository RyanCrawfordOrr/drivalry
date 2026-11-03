import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../google/places_client.dart' show StopCategory;
import '../sync/outbox.dart';
import 'convoy_api.dart';
import 'convoy_models.dart';

export 'convoy_api.dart';
export 'convoy_models.dart';

/// Thrown by photo uploads the user should hear about.
class ConvoyError implements Exception {
  const ConvoyError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Convoys: membership, destination, stops and votes, expenses, photos
/// (docs/01 §4.6, docs/10 §1–§2). Reads are cached in `RemoteCache`; writes go
/// through the outbox with an optimistic cache update, except joining by code
/// and photo bytes, which need the server right away.
class ConvoyRepo {
  ConvoyRepo({
    required this.apiOf,
    required this.db,
    required this.outbox,
    required this.me,
    this.now = _nowMs,
  });

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  static const _uuid = Uuid();

  final ConvoysApi? Function() apiOf;
  final AppDatabase db;
  final OutboxWorker outbox;
  final String? Function() me;
  final int Function() now;

  static const cacheKey = 'convoys:mine';
  static String membersKey(String id) => 'convoy:$id:members';
  static String stopsKey(String id) => 'convoy:$id:stops';
  static String expensesKey(String id) => 'convoy:$id:expenses';
  static String photosKey(String id) => 'convoy:$id:photos';

  /// Photos per convoy (docs/03 §10) and bytes per photo.
  static const maxPhotos = 50;
  static const maxPhotoBytes = 200 * 1024;

  // Outbox kinds and payloads (idempotent server side).
  static const kindCreate =
      'convoy_create'; // {id, name, user_id, destination?}
  static const kindUpdate = 'convoy_update'; // {convoy_id, user_id, fields}
  static const kindStatus = 'convoy_status'; // {convoy_id, user_id, status, at}
  static const kindLeave = 'convoy_leave'; // {convoy_id, user_id}
  static const kindStopPropose =
      'stop_propose'; // {id, convoy_id, user_id, ...}
  static const kindStopVote = 'stop_vote'; // {stop_id, user_id, vote}
  static const kindStopStatus = 'stop_status'; // {stop_id, user_id, status}
  static const kindExpenseAdd = 'expense_add'; // {id, convoy_id, user_id, ...}
  static const kindExpenseDelete = 'expense_delete'; // {id, user_id}
  static const kindPhotoAdd = 'photo_add'; // {id, convoy_id, user_id, ...}
  static const kindPhotoDelete = 'photo_delete'; // {id, user_id, storage_path}

  static String inviteLink(String code) => 'drivalry://join/convoy/$code';

  ConvoysApi _online() {
    final api = apiOf();
    if (api == null) throw const OutboxRetryLater('not signed in');
    return api;
  }

  DateTime _nowUtc() => DateTime.fromMillisecondsSinceEpoch(now(), isUtc: true);

  // ---------------------------------------------------------------- reads --

  Future<List<Convoy>?> cached() async =>
      _decodeConvoys(await db.cacheGet(cacheKey));

  Stream<List<Convoy>?> watchCached() =>
      db.watchCache(cacheKey).map(_decodeConvoys);

  List<Convoy>? _decodeConvoys(String? json) {
    if (json == null) return null;
    try {
      return [
        for (final c in jsonDecode(json) as List)
          Convoy.fromJson((c as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<List<Convoy>> fetch() async {
    final api = apiOf();
    final uid = me();
    if (api == null || uid == null) return const [];
    final convoys = await api.myConvoys(uid);
    await _store(convoys);
    return convoys;
  }

  Future<void> _store(List<Convoy> convoys) => db.cachePut(
    cacheKey,
    jsonEncode([for (final c in convoys) c.toJson()]),
    now(),
  );

  Future<Convoy?> cachedConvoy(String id) async {
    final list = await cached();
    if (list == null) return null;
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _updateCached(String id, Convoy Function(Convoy) change) async {
    final current = await cached();
    if (current == null) return;
    await _store([
      for (final c in current)
        if (c.id == id) change(c) else c,
    ]);
  }

  Future<List<T>?> _cachedList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final json = await db.cacheGet(key);
    if (json == null) return null;
    try {
      return [
        for (final m in jsonDecode(json) as List)
          fromJson((m as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  Stream<List<T>?> _watchList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) => db.watchCache(key).map((json) {
    if (json == null) return null;
    try {
      return [
        for (final m in jsonDecode(json) as List)
          fromJson((m as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  });

  Future<void> _putList(String key, List<Map<String, dynamic>> rows) =>
      db.cachePut(key, jsonEncode(rows), now());

  Future<List<ConvoyMember>?> cachedMembers(String id) =>
      _cachedList(membersKey(id), ConvoyMember.fromRow);

  /// Display names by user id from the cached member list, for spoken output
  /// and labels. Empty when nothing is cached; callers fall back to
  /// "Someone" rather than reading a UUID aloud.
  Future<Map<String, String>> memberNames(String id) async {
    try {
      final members = await cachedMembers(id) ?? const <ConvoyMember>[];
      return {for (final m in members) m.userId: m.name};
    } catch (_) {
      return const {};
    }
  }

  Stream<List<ConvoyMember>?> watchMembers(String id) =>
      _watchList(membersKey(id), ConvoyMember.fromRow);

  Future<List<ConvoyMember>> fetchMembers(String id) async {
    final api = apiOf();
    if (api == null) return await cachedMembers(id) ?? const [];
    final members = await api.members(id);
    await _putList(membersKey(id), [for (final m in members) m.toJson()]);
    return members;
  }

  /// Cache first, network when the cache is empty.
  Future<List<ConvoyMember>> members(String id) async =>
      await cachedMembers(id) ?? await fetchMembers(id);

  Future<List<ConvoyStop>?> cachedStops(String id) =>
      _cachedList(stopsKey(id), ConvoyStop.fromRow);
  Stream<List<ConvoyStop>?> watchStops(String id) =>
      _watchList(stopsKey(id), ConvoyStop.fromRow);

  Future<List<ConvoyStop>> fetchStops(String id) async {
    final api = apiOf();
    if (api == null) return await cachedStops(id) ?? const [];
    final stops = await api.stops(id);
    await _putList(stopsKey(id), [for (final s in stops) s.toJson()]);
    return stops;
  }

  Future<List<ConvoyExpense>?> cachedExpenses(String id) =>
      _cachedList(expensesKey(id), ConvoyExpense.fromRow);
  Stream<List<ConvoyExpense>?> watchExpenses(String id) =>
      _watchList(expensesKey(id), ConvoyExpense.fromRow);

  Future<List<ConvoyExpense>> fetchExpenses(String id) async {
    final api = apiOf();
    if (api == null) return await cachedExpenses(id) ?? const [];
    final rows = await api.expenses(id);
    await _putList(expensesKey(id), [for (final e in rows) e.toJson()]);
    return rows;
  }

  Future<List<ConvoyPhoto>?> cachedPhotos(String id) =>
      _cachedList(photosKey(id), ConvoyPhoto.fromRow);
  Stream<List<ConvoyPhoto>?> watchPhotos(String id) =>
      _watchList(photosKey(id), ConvoyPhoto.fromRow);

  Future<List<ConvoyPhoto>> fetchPhotos(String id) async {
    final api = apiOf();
    if (api == null) return await cachedPhotos(id) ?? const [];
    final rows = await api.photos(id);
    await _putList(photosKey(id), [for (final p in rows) p.toJson()]);
    return rows;
  }

  /// A signed URL, cached for an hour under `convoy:<id>:url:<path>`.
  Future<String?> photoUrl(String convoyId, String storagePath) async {
    final key = 'convoy:$convoyId:url:$storagePath';
    final cached = await db.cacheGet(key);
    if (cached != null) {
      try {
        final m = jsonDecode(cached) as Map<String, dynamic>;
        final exp = (m['exp'] as num).toInt();
        if (exp > now()) return m['url'] as String;
      } catch (_) {}
    }
    final api = apiOf();
    if (api == null) return null;
    try {
      final url = await api.signedPhotoUrl(storagePath);
      await db.cachePut(
        key,
        jsonEncode({'url': url, 'exp': now() + 55 * 60 * 1000}),
        now(),
      );
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<List<ConvoyTripSummary>> tripSummaries(
    List<String> userIds,
    DateTime from,
    DateTime to,
  ) async {
    final api = apiOf();
    if (api == null) return const [];
    try {
      return await api.tripSummariesBetween(userIds, from, to);
    } catch (_) {
      return const [];
    }
  }

  // --------------------------------------------------------------- writes --

  /// Creates a convoy locally (I am the leader) and queues the cloud write.
  /// The invite code appears after the next [fetch]. Returns the new id.
  Future<String> create(String name, {Destination? destination}) async {
    final uid = me();
    final trimmed = name.trim();
    if (uid == null || trimmed.isEmpty) {
      throw ArgumentError('sign in and give the convoy a name');
    }
    final id = _uuid.v4();
    await outbox.enqueue(kindCreate, {
      'id': id,
      'name': trimmed,
      'user_id': uid,
      'destination': destination?.toJson(),
    }, id: 'convoy_create:$id');
    final current = await cached() ?? const <Convoy>[];
    await _store([
      Convoy(
        id: id,
        name: trimmed,
        createdBy: uid,
        status: ConvoyStatus.planning,
        destination: destination,
        inviteCode: '',
        createdAt: _nowUtc(),
      ),
      ...current,
    ]);
    await _putList(membersKey(id), [
      ConvoyMember(
        userId: uid,
        handle: '',
        displayName: 'You',
        role: 'leader',
        joinedAt: _nowUtc(),
      ).toJson(),
    ]);
    return id;
  }

  /// Joins through the `join_convoy` RPC and refreshes the list. Throws
  /// [ConvoyJoinException].
  Future<String> join(String code) async {
    final api = apiOf();
    if (api == null || me() == null) {
      throw const ConvoyJoinException(ConvoyJoinError.notSignedIn);
    }
    final id = await api.joinByCode(code.trim().toLowerCase());
    try {
      await fetch();
    } catch (_) {
      // Joined; the list refreshes on the next screen open.
    }
    return id;
  }

  Future<void> setDestination(String convoyId, Destination? destination) async {
    final uid = me();
    if (uid == null) return;
    await _updateCached(
      convoyId,
      (c) => c.copyWith(
        destination: destination,
        clearDestination: destination == null,
      ),
    );
    await outbox.enqueue(kindUpdate, {
      'convoy_id': convoyId,
      'user_id': uid,
      'fields': {'destination': destination?.toJson()},
    }, id: 'convoy_update:$convoyId:destination');
  }

  Future<void> rename(String convoyId, String name) async {
    final uid = me();
    final trimmed = name.trim();
    if (uid == null || trimmed.isEmpty) return;
    await _updateCached(convoyId, (c) => c.copyWith(name: trimmed));
    await outbox.enqueue(kindUpdate, {
      'convoy_id': convoyId,
      'user_id': uid,
      'fields': {'name': trimmed},
    }, id: 'convoy_update:$convoyId:name');
  }

  /// Leader only (RLS enforces it too): planning → active → ended.
  Future<void> setStatus(String convoyId, ConvoyStatus status) async {
    final uid = me();
    if (uid == null) return;
    final at = _nowUtc();
    await _updateCached(
      convoyId,
      (c) => c.copyWith(
        status: status,
        startedAt: status == ConvoyStatus.active ? at : null,
        endedAt: status == ConvoyStatus.ended ? at : null,
      ),
    );
    await outbox.enqueue(kindStatus, {
      'convoy_id': convoyId,
      'user_id': uid,
      'status': status.wire,
      'at': at.toIso8601String(),
    }, id: 'convoy_status:$convoyId:${status.wire}');
  }

  Future<void> leave(String convoyId) async {
    final uid = me();
    if (uid == null) return;
    final current = await cached();
    if (current != null) {
      await _store([
        for (final c in current)
          if (c.id != convoyId) c,
      ]);
    }
    await db.cacheDeletePrefix('convoy:$convoyId:');
    await outbox.enqueue(kindLeave, {
      'convoy_id': convoyId,
      'user_id': uid,
    }, id: 'convoy_leave:$convoyId:$uid');
  }

  /// Proposes a stop; returns its id.
  Future<String> proposeStop(
    String convoyId, {
    required StopCategory category,
    required String name,
    required double lat,
    required double lon,
    String? placeId,
  }) async {
    final uid = me();
    if (uid == null) throw ArgumentError('sign in first');
    final id = _uuid.v4();
    final stop = ConvoyStop(
      id: id,
      convoyId: convoyId,
      proposedBy: uid,
      category: category,
      name: name.trim().isEmpty ? category.label : name.trim(),
      lat: lat,
      lon: lon,
      placeId: placeId,
      status: StopStatus.proposed,
      createdAt: _nowUtc(),
      votes: {uid: 1},
    );
    final current = await cachedStops(convoyId) ?? const <ConvoyStop>[];
    await _putList(stopsKey(convoyId), [
      for (final s in current) s.toJson(),
      stop.toJson(),
    ]);
    await outbox.enqueue(kindStopPropose, {
      'id': id,
      'convoy_id': convoyId,
      'user_id': uid,
      'category': category.wire,
      'name': stop.name,
      'lat': lat,
      'lon': lon,
      'place_id': placeId,
    }, id: 'stop_propose:$id');
    await outbox.enqueue(kindStopVote, {
      'stop_id': id,
      'user_id': uid,
      'vote': 1,
    }, id: 'stop_vote:$id:$uid');
    return id;
  }

  /// +1 / -1, or 0 to withdraw my vote.
  Future<void> vote(String convoyId, String stopId, int vote) async {
    final uid = me();
    if (uid == null) return;
    final v = vote.clamp(-1, 1);
    final current = await cachedStops(convoyId);
    if (current != null) {
      await _putList(stopsKey(convoyId), [
        for (final s in current)
          if (s.id == stopId)
            s
                .copyWith(
                  votes: v == 0
                      ? ({...s.votes}..remove(uid))
                      : {...s.votes, uid: v},
                )
                .toJson()
          else
            s.toJson(),
      ]);
    }
    await outbox.enqueue(kindStopVote, {
      'stop_id': stopId,
      'user_id': uid,
      'vote': v,
    }, id: 'stop_vote:$stopId:$uid');
  }

  Future<void> setStopStatus(
    String convoyId,
    String stopId,
    StopStatus status,
  ) async {
    final uid = me();
    if (uid == null) return;
    final current = await cachedStops(convoyId);
    if (current != null) {
      await _putList(stopsKey(convoyId), [
        for (final s in current)
          if (s.id == stopId)
            s.copyWith(status: status).toJson()
          else
            s.toJson(),
      ]);
    }
    await outbox.enqueue(kindStopStatus, {
      'stop_id': stopId,
      'convoy_id': convoyId,
      'user_id': uid,
      'status': status.wire,
    }, id: 'stop_status:$stopId');
  }

  Future<String> addExpense(
    String convoyId, {
    required int amountCents,
    required String category,
    String currency = 'USD',
    String? note,
    String? payerId,
  }) async {
    final uid = me();
    if (uid == null) throw ArgumentError('sign in first');
    if (amountCents <= 0) throw ArgumentError('amount must be positive');
    final id = _uuid.v4();
    final e = ConvoyExpense(
      id: id,
      convoyId: convoyId,
      payerId: payerId ?? uid,
      amountCents: amountCents,
      currency: currency,
      category: ConvoyExpense.categories.contains(category)
          ? category
          : 'other',
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      createdAt: _nowUtc(),
    );
    final current = await cachedExpenses(convoyId) ?? const <ConvoyExpense>[];
    await _putList(expensesKey(convoyId), [
      for (final x in current) x.toJson(),
      e.toJson(),
    ]);
    await outbox.enqueue(kindExpenseAdd, {
      ...e.toJson(),
      'user_id': uid,
    }, id: 'expense_add:$id');
    return id;
  }

  Future<void> deleteExpense(String convoyId, String id) async {
    final uid = me();
    if (uid == null) return;
    final current = await cachedExpenses(convoyId);
    if (current != null) {
      await _putList(expensesKey(convoyId), [
        for (final x in current)
          if (x.id != id) x.toJson(),
      ]);
    }
    await outbox.enqueue(kindExpenseDelete, {
      'id': id,
      'user_id': uid,
    }, id: 'expense_delete:$id');
  }

  /// Uploads the bytes now (needs the network) and queues the row.
  Future<String> addPhoto(
    String convoyId,
    Uint8List jpeg, {
    String? stopId,
    DateTime? takenAt,
  }) async {
    final uid = me();
    final api = apiOf();
    if (uid == null || api == null) {
      throw const ConvoyError('Sign in and get online to add photos.');
    }
    if (jpeg.length > maxPhotoBytes) {
      throw ConvoyError(
        'That photo is ${(jpeg.length / 1024).round()} KB; the limit is 200 KB.',
      );
    }
    final current = await cachedPhotos(convoyId) ?? const <ConvoyPhoto>[];
    if (current.length >= maxPhotos) {
      throw const ConvoyError('This album is full (50 photos).');
    }
    final id = _uuid.v4();
    final path = '$convoyId/$id.jpg';
    await api.uploadPhoto(path, jpeg);
    final photo = ConvoyPhoto(
      id: id,
      convoyId: convoyId,
      userId: uid,
      stopId: stopId,
      storagePath: path,
      takenAt: takenAt?.toUtc() ?? _nowUtc(),
    );
    await _putList(photosKey(convoyId), [
      for (final p in current) p.toJson(),
      photo.toJson(),
    ]);
    await outbox.enqueue(kindPhotoAdd, {
      ...photo.toJson(),
    }, id: 'photo_add:$id');
    return id;
  }

  Future<void> deletePhoto(String convoyId, ConvoyPhoto photo) async {
    final uid = me();
    if (uid == null || photo.userId != uid) return;
    final current = await cachedPhotos(convoyId);
    if (current != null) {
      await _putList(photosKey(convoyId), [
        for (final p in current)
          if (p.id != photo.id) p.toJson(),
      ]);
    }
    await outbox.enqueue(kindPhotoDelete, {
      'id': photo.id,
      'user_id': uid,
      'storage_path': photo.storagePath,
    }, id: 'photo_delete:${photo.id}');
  }

  // ----------------------------------------------------- outbox handlers --

  void _mine(Map<String, dynamic> p) {
    if (p['user_id'] != me()) throw const OutboxSkip('another account');
  }

  Future<void> handleCreate(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.createConvoy(
      id: p['id'] as String,
      name: p['name'] as String,
      userId: p['user_id'] as String,
      destination: Destination.fromJson(p['destination']),
    );
  }

  Future<void> handleUpdate(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    final fields = (p['fields'] as Map).cast<String, Object?>();
    await api.updateConvoy(p['convoy_id'] as String, fields);
  }

  Future<void> handleStatus(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.setStatus(
      p['convoy_id'] as String,
      ConvoyStatus.fromWire(p['status'] as String?),
      DateTime.tryParse(p['at'] as String? ?? '') ?? DateTime.now().toUtc(),
    );
  }

  Future<void> handleLeave(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.leave(
      convoyId: p['convoy_id'] as String,
      userId: p['user_id'] as String,
    );
  }

  Future<void> handleStopPropose(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.proposeStop({
      'id': p['id'],
      'convoy_id': p['convoy_id'],
      'proposed_by': p['user_id'],
      'category': p['category'],
      'name': p['name'],
      'lat': p['lat'],
      'lon': p['lon'],
      'place_id': p['place_id'],
    });
  }

  Future<void> handleStopVote(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    if ((p['vote'] as num).toInt() == 0) {
      await api.removeVote(
        stopId: p['stop_id'] as String,
        userId: p['user_id'] as String,
      );
      return;
    }
    await api.vote(
      stopId: p['stop_id'] as String,
      userId: p['user_id'] as String,
      vote: (p['vote'] as num).toInt(),
    );
  }

  Future<void> handleStopStatus(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.setStopStatus(
      p['stop_id'] as String,
      StopStatus.fromWire(p['status'] as String?),
    );
  }

  Future<void> handleExpenseAdd(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.addExpense({
      'id': p['id'],
      'convoy_id': p['convoy_id'],
      'payer_id': p['payer_id'],
      'amount_cents': p['amount_cents'],
      'currency': p['currency'],
      'category': p['category'],
      'note': p['note'],
      'created_at': p['created_at'],
    });
  }

  Future<void> handleExpenseDelete(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.deleteExpense(p['id'] as String);
  }

  Future<void> handlePhotoAdd(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.addPhoto({
      'id': p['id'],
      'convoy_id': p['convoy_id'],
      'user_id': p['user_id'],
      'stop_id': p['stop_id'],
      'storage_path': p['storage_path'],
      'taken_at': p['taken_at'],
    });
  }

  Future<void> handlePhotoDelete(Map<String, dynamic> p) async {
    final api = _online();
    _mine(p);
    await api.deletePhoto(p['id'] as String, p['storage_path'] as String);
  }

  void registerHandlers(OutboxWorker worker) {
    worker.register(kindCreate, handleCreate);
    worker.register(kindUpdate, handleUpdate);
    worker.register(kindStatus, handleStatus);
    worker.register(kindLeave, handleLeave);
    worker.register(kindStopPropose, handleStopPropose);
    worker.register(kindStopVote, handleStopVote);
    worker.register(kindStopStatus, handleStopStatus);
    worker.register(kindExpenseAdd, handleExpenseAdd);
    worker.register(kindExpenseDelete, handleExpenseDelete);
    worker.register(kindPhotoAdd, handlePhotoAdd);
    worker.register(kindPhotoDelete, handlePhotoDelete);
  }
}
