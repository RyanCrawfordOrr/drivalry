import 'dart:math' as math;

import 'trivia_questions.dart';

/// US state and territory codes for license-plate bingo.
const List<String> plateStates = [
  'AL',
  'AK',
  'AZ',
  'AR',
  'CA',
  'CO',
  'CT',
  'DE',
  'FL',
  'GA',
  'HI',
  'ID',
  'IL',
  'IN',
  'IA',
  'KS',
  'KY',
  'LA',
  'ME',
  'MD',
  'MA',
  'MI',
  'MN',
  'MS',
  'MO',
  'MT',
  'NE',
  'NV',
  'NH',
  'NJ',
  'NM',
  'NY',
  'NC',
  'ND',
  'OH',
  'OK',
  'OR',
  'PA',
  'RI',
  'SC',
  'SD',
  'TN',
  'TX',
  'UT',
  'VT',
  'VA',
  'WA',
  'WV',
  'WI',
  'WY',
  'DC',
];

/// A `game` message as it travels (docs/10 §5): `{game, event, ...}`.
class GameMessage {
  const GameMessage({
    required this.from,
    required this.t,
    required this.payload,
  });
  final String from;
  final int t;
  final Map<String, dynamic> payload;
  String get game => payload['game'] as String? ?? '';
  String get event => payload['event'] as String? ?? '';
}

/// License-plate bingo: everyone marks the states they spot; progress is
/// shared so the convoy sees who is ahead. No winner needs a race.
class PlatesBingo {
  PlatesBingo(this.selfId);
  final String selfId;
  final Map<String, Set<String>> marked = {};

  Set<String> get mine => marked[selfId] ??= {};

  /// Toggles a state locally and returns the payload to broadcast.
  Map<String, Object?> toggle(String code) {
    if (!plateStates.contains(code)) return const {};
    if (!mine.remove(code)) mine.add(code);
    return {'game': 'plates', 'event': 'mark', 'state': mine.toList()..sort()};
  }

  void onMessage(GameMessage m) {
    if (m.game != 'plates' || m.event != 'mark') return;
    final list = (m.payload['state'] as List?)?.cast<String>() ?? const [];
    marked[m.from] = list.where(plateStates.contains).toSet();
  }

  /// Players by count, highest first; ties broken by id for stability.
  List<(String, int)> standings() {
    final rows = [for (final e in marked.entries) (e.key, e.value.length)];
    rows.sort(
      (a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1),
    );
    return rows;
  }
}

/// Roadside trivia: the host (lowest participant id by default) asks a
/// question with a deadline; everyone answers over the bus; scores accumulate.
class Trivia {
  Trivia(this.selfId, {int Function()? now, this.questionMs = 20_000})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String selfId;
  final int Function() _now;
  final int questionMs;

  int? currentIndex;
  int? endsAt;
  final Map<String, int> answers = {};
  final Map<String, int> scores = {};
  final List<int> asked = [];

  /// Who hosts: the lowest id among participants (deterministic, no election).
  static String hostOf(Set<String> participants, String selfId) {
    final all = {...participants, selfId}.toList()..sort();
    return all.first;
  }

  bool isHost(Set<String> participants) =>
      hostOf(participants, selfId) == selfId;

  TriviaQuestion? get current =>
      currentIndex == null ? null : triviaQuestions[currentIndex!];

  bool get open => endsAt != null && _now() < endsAt!;

  /// Host: pick the next unasked question. Returns the payload to send.
  Map<String, Object?> nextQuestion({math.Random? random}) {
    final rnd = random ?? math.Random();
    final remaining = [
      for (var i = 0; i < triviaQuestions.length; i++)
        if (!asked.contains(i)) i,
    ];
    if (remaining.isEmpty) asked.clear();
    final pool = remaining.isEmpty
        ? List.generate(triviaQuestions.length, (i) => i)
        : remaining;
    final index = pool[rnd.nextInt(pool.length)];
    _start(index, _now() + questionMs);
    return {
      'game': 'trivia',
      'event': 'question',
      'index': index,
      'endsAt': endsAt,
    };
  }

  void _start(int index, int ends) {
    currentIndex = index;
    endsAt = ends;
    asked.add(index);
    answers.clear();
  }

  /// Answer the open question. Returns the payload to send, or null when there
  /// is no open question or I already answered.
  Map<String, Object?>? answer(int choice) {
    if (!open || answers.containsKey(selfId)) return null;
    answers[selfId] = choice;
    return {
      'game': 'trivia',
      'event': 'answer',
      'index': currentIndex,
      'choice': choice,
    };
  }

  /// Host: close the question and return the result payload (scores + who
  /// was right). Also applied locally.
  Map<String, Object?> reveal() {
    final q = current;
    if (q == null) return const {};
    final right = <String>[];
    for (final e in answers.entries) {
      if (e.value == q.answer) {
        right.add(e.key);
        scores[e.key] = (scores[e.key] ?? 0) + 1;
      }
    }
    endsAt = null;
    return {
      'game': 'trivia',
      'event': 'reveal',
      'index': currentIndex,
      'answer': q.answer,
      'right': right,
      'scores': Map<String, int>.from(scores),
    };
  }

  void onMessage(GameMessage m) {
    if (m.game != 'trivia') return;
    switch (m.event) {
      case 'question':
        final i = (m.payload['index'] as num?)?.toInt();
        final ends = (m.payload['endsAt'] as num?)?.toInt();
        if (i == null || i < 0 || i >= triviaQuestions.length) return;
        _start(i, ends ?? _now() + questionMs);
      case 'answer':
        final choice = (m.payload['choice'] as num?)?.toInt();
        if (choice == null ||
            (m.payload['index'] as num?)?.toInt() != currentIndex) {
          return;
        }
        answers.putIfAbsent(m.from, () => choice);
      case 'reveal':
        final s = (m.payload['scores'] as Map?)?.cast<String, dynamic>();
        if (s != null) {
          scores
            ..clear()
            ..addAll({
              for (final e in s.entries) e.key: (e.value as num).toInt(),
            });
        }
        endsAt = null;
    }
  }

  /// Spoken summary after a reveal.
  String spokenResult(
    Map<String, dynamic> reveal,
    String Function(String) nameOf,
  ) {
    final q = triviaQuestions[(reveal['index'] as num).toInt()];
    final right = (reveal['right'] as List?)?.cast<String>() ?? const [];
    final answer = q.choices[(reveal['answer'] as num).toInt()];
    if (right.isEmpty) return 'Nobody got it. The answer was $answer.';
    return '${right.map(nameOf).join(' and ')} got it: $answer.';
  }
}

/// "Spot the…" scavenger list: first claim wins, settled by earliest time then
/// lowest id so every phone agrees.
class Scavenger {
  Scavenger(this.selfId, {List<String>? items})
    : items = items ?? List.of(defaultItems);

  final String selfId;
  final List<String> items;
  final Map<String, (String by, int t)> claims = {};

  static const defaultItems = [
    'Red barn',
    'Water tower',
    'Police car',
    'Out-of-state plate',
    'Motorcycle',
    'Horse',
    'Billboard with a lawyer',
    'Yellow car',
    'Wind turbine',
    'Train',
    'Food truck',
    'Convertible with the top down',
    'Dog in a window',
    'RV',
    'Bridge over water',
    'Someone waving',
  ];

  Map<String, Object?>? claim(String item, int t) {
    if (!items.contains(item) || claims.containsKey(item)) return null;
    claims[item] = (selfId, t);
    return {'game': 'scavenger', 'event': 'claim', 'item': item, 't': t};
  }

  void onMessage(GameMessage m) {
    if (m.game != 'scavenger' || m.event != 'claim') return;
    final item = m.payload['item'] as String?;
    final t = (m.payload['t'] as num?)?.toInt() ?? m.t;
    if (item == null || !items.contains(item)) return;
    final cur = claims[item];
    if (cur == null ||
        t < cur.$2 ||
        (t == cur.$2 && m.from.compareTo(cur.$1) < 0)) {
      claims[item] = (m.from, t);
    }
  }

  Map<String, int> tally() {
    final out = <String, int>{};
    for (final c in claims.values) {
      out[c.$1] = (out[c.$1] ?? 0) + 1;
    }
    return out;
  }
}

/// "Who's smoothest this leg": lower speed variation over the last few
/// minutes ranks higher. Speeds are never shown, only steadiness, so nothing
/// here rewards going fast (docs/01 §5).
class SmoothestLeg {
  SmoothestLeg({this.windowMs = 5 * 60_000});

  final int windowMs;
  final Map<String, List<(int t, double speed)>> _speeds = {};

  void addSpeed(String userId, int t, double speedMps) {
    final list = _speeds.putIfAbsent(userId, () => []);
    list.add((t, speedMps));
    final cutoff = t - windowMs;
    list.removeWhere((e) => e.$1 < cutoff);
  }

  /// Standard deviation of speed (m/s) per car, lowest first. Cars with fewer
  /// than five samples are left out.
  List<(String, double)> ranking() {
    final rows = <(String, double)>[];
    for (final e in _speeds.entries) {
      final v = e.value;
      if (v.length < 5) continue;
      final mean = v.fold<double>(0, (a, b) => a + b.$2) / v.length;
      final variance =
          v.fold<double>(0, (a, b) => a + math.pow(b.$2 - mean, 2)) / v.length;
      rows.add((e.key, math.sqrt(variance)));
    }
    rows.sort(
      (a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
    );
    return rows;
  }

  /// Plain-language label; no numbers that could read as a speed.
  static String label(double stdDevMps) {
    if (stdDevMps < 1.5) return 'Glassy';
    if (stdDevMps < 3) return 'Steady';
    if (stdDevMps < 5) return 'Wavy';
    return 'Choppy';
  }
}
