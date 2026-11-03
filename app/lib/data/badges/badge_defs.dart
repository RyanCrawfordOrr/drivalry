/// A badge definition, as seeded in `supabase/migrations/0001_init.sql`.
class BadgeDef {
  const BadgeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
  });

  factory BadgeDef.fromJson(Map<String, dynamic> j) => BadgeDef(
    id: j['id'] as String,
    name: j['name'] as String? ?? j['id'] as String,
    description: j['description'] as String? ?? '',
    category: j['category'] as String? ?? 'safety',
  );

  final String id;
  final String name;
  final String description;

  /// safety | exploration | social | season | shame
  final String category;

  bool get isShame => category == 'shame';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
  };
}

/// Built-in copy of the seed so the screen works before the first cloud read
/// and in offline builds. Keep in step with `0001_init.sql`.
const List<BadgeDef> fallbackBadgeDefs = [
  BadgeDef(
    id: 'first_trip',
    name: 'First Trip',
    description: 'Your first scored drive.',
    category: 'safety',
  ),
  BadgeDef(
    id: 'clean_5',
    name: 'Five Clean',
    description: 'Five scored trips in a row at 80 or better, none reckless.',
    category: 'safety',
  ),
  BadgeDef(
    id: 'clean_20',
    name: 'Twenty Clean',
    description: 'Twenty clean trips in a row.',
    category: 'safety',
  ),
  BadgeDef(
    id: 'phone_free_10',
    name: 'Hands Off',
    description: 'Ten trips in a row without touching the phone.',
    category: 'safety',
  ),
  BadgeDef(
    id: 'perfect_100',
    name: 'Flawless',
    description: 'A trip scored 100.',
    category: 'safety',
  ),
  BadgeDef(
    id: 'night_owl',
    name: 'Night Owl',
    description: 'Ten night trips scored 85 or better.',
    category: 'safety',
  ),
  BadgeDef(
    id: 'rain_or_shine',
    name: 'Rain or Shine',
    description: 'Five rainy trips scored 85 or better.',
    category: 'safety',
  ),
  BadgeDef(
    id: 'three_states',
    name: 'Border Hopper',
    description: 'Drove in three states or provinces.',
    category: 'exploration',
  ),
  BadgeDef(
    id: 'ten_states',
    name: 'Road Scholar',
    description: 'Drove in ten states or provinces.',
    category: 'exploration',
  ),
  BadgeDef(
    id: 'high_altitude',
    name: 'Thin Air',
    description: 'A trip above 2,500 m.',
    category: 'exploration',
  ),
  BadgeDef(
    id: 'first_friend',
    name: 'Plus One',
    description: 'Added a friend.',
    category: 'social',
  ),
  BadgeDef(
    id: 'league_week',
    name: 'Regular',
    description: 'Finished a league week.',
    category: 'social',
  ),
  BadgeDef(
    id: 'promoted',
    name: 'Moving Up',
    description: 'Promoted at a Sunday rollover.',
    category: 'social',
  ),
  BadgeDef(
    id: 'convoy_first',
    name: 'Wagon Train',
    description: 'Finished a convoy.',
    category: 'social',
  ),
  BadgeDef(
    id: 'snitch',
    name: 'Snitch',
    description: 'A speed-limit fix you flagged was confirmed.',
    category: 'social',
  ),
  BadgeDef(
    id: 'sunday_driver',
    name: 'Sunday Driver',
    description: 'Lost a duel. Seven days.',
    category: 'shame',
  ),
  BadgeDef(
    id: 'lead_foot',
    name: 'Lead Foot',
    description: 'Lost a duel. Seven days.',
    category: 'shame',
  ),
  BadgeDef(
    id: 'butterfingers',
    name: 'Butterfingers',
    description: 'Lost a duel. Seven days.',
    category: 'shame',
  ),
  BadgeDef(
    id: 'wall_of_shame',
    name: 'Wall of Shame',
    description: 'A reckless trip, posted to your groups.',
    category: 'shame',
  ),
  BadgeDef(
    id: 'season_1',
    name: 'Season One',
    description: 'Drove through the first season.',
    category: 'season',
  ),
  // Group challenges (migration 0007).
  BadgeDef(
    id: 'challenge_clean_trips',
    name: 'Clean Sweep',
    description: 'Your league hit its clean-trips challenge.',
    category: 'social',
  ),
  BadgeDef(
    id: 'challenge_phone_free',
    name: 'Hands Off, Together',
    description: 'Your league hit its phone-free challenge.',
    category: 'social',
  ),
  BadgeDef(
    id: 'challenge_score_avg',
    name: 'Class Act',
    description: 'Your league averaged its target Drive Score.',
    category: 'social',
  ),
  BadgeDef(
    id: 'challenge_everyone_drives',
    name: 'Full House',
    description: 'Everyone in your league showed up for the challenge.',
    category: 'social',
  ),
];

BadgeDef? badgeDefById(List<BadgeDef> defs, String id) {
  for (final d in defs) {
    if (d.id == id) return d;
  }
  return null;
}
