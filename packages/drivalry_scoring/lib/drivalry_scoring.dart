/// Drivalry scoring engine: GPS samples + road segments in, Drive Score, events, XP and
/// roasts out.
///
/// This is a module-for-module port of `packages/scoring` (`@drivalry/scoring`, TypeScript),
/// which remains the specification. `packages/scoring/fixtures/` is the contract: the test
/// suite in `test/fixtures_test.dart` replays every fixture through [scoreTrip] and asserts
/// identical output.
///
/// All quantities are SI (metres, seconds, m/s, m/s²); timestamps are epoch milliseconds.
/// The UI converts to the user's units. See `docs/02-game-design.md` for the rules.
library;

export 'src/constants.dart';
export 'src/geo.dart' show bearing, destination, haversine, headingDelta;
export 'src/roast/roast.dart'
    show buildFeedback, formatDuration, formatSaved, roastEvent;
export 'src/roast/templates.dart';
export 'src/score.dart' show computeXp, scoreTrip, sortBySeverity;
export 'src/synthetic.dart';
export 'src/types.dart';
