/// Roast and praise templates. Mirrors `packages/scoring/src/roast/templates.ts`.
///
/// Rules (see docs/02-game-design.md §9):
///  - Target the drive, not the driver.
///  - Always include the number. Specificity is the joke.
///  - Hard floor: nothing about crashes, death, injury, alcohol, other people getting hurt,
///    or anything that reads as a dare. `test/roast_test.dart` enforces a banned-word list.
///
/// Slots: {over} {limit} {speed} {duration} {road} {saved} {count} {peak} {distance}
///        {phoneSeconds} {unit} {events} {idleMinutes} {cruiseMinutes}
///
/// The strings and their order must match the TypeScript library exactly: a template is
/// chosen by `hash(seed) % list.length`, so order is part of the contract
/// (`fixtures/vectors-templates.json`).
library;

import '../types.dart';

enum TemplateKey {
  speedingMinor('speeding.minor'),
  speedingModerate('speeding.moderate'),
  speedingMajor('speeding.major'),
  speedingReckless('speeding.reckless'),
  harshBrakeModerate('harsh_brake.moderate'),
  harshBrakeSevere('harsh_brake.severe'),
  harshAccelModerate('harsh_accel.moderate'),
  harshAccelSevere('harsh_accel.severe'),
  hardCornerModerate('hard_corner.moderate'),
  hardCornerSevere('hard_corner.severe'),
  phoneHandlingMinor('phone_handling.minor'),
  phoneHandlingModerate('phone_handling.moderate'),
  phoneHandlingMajor('phone_handling.major'),
  idling('idling'),
  highSpeedCruise('high_speed_cruise'),
  praisePerfect('praise.perfect'),
  praiseCleanLong('praise.clean_long'),
  praiseGood('praise.good'),
  praisePhoneFree('praise.phone_free'),
  praiseSmooth('praise.smooth'),
  praiseLimitRespect('praise.limit_respect'),
  unscoredTooShort('unscored.too_short'),
  unscoredPassenger('unscored.passenger');

  const TemplateKey(this.key);

  /// The TypeScript key string; part of the hash seed.
  final String key;

  static TemplateKey fromKey(String key) => values.firstWhere(
    (v) => v.key == key,
    orElse: () => throw ArgumentError.value(key, 'key'),
  );
}

typedef TemplateLibrary = Map<TemplateKey, Map<Intensity, List<String>>>;

const TemplateLibrary templates = {
  TemplateKey.speedingMinor: {
    Intensity.gentle: [
      'You were about {over} {unit} over on {road} for {duration}. That saved roughly {saved}.',
      'A little quick on {road}: {over} over for {duration}.',
    ],
    Intensity.sassy: [
      '{over} over on {road} for {duration}. You saved {saved}. Big spender.',
      '{road}, {over} over, {duration}. The limit was right there on a sign and everything.',
    ],
    Intensity.savage: [
      '{over} over on {road} for {duration} to save {saved}. Bold strategy for someone with a league to lose.',
      "{road}: {over} over, {duration}, {saved} saved. Your friends can see this. They're not impressed, they're just looking.",
    ],
  },
  TemplateKey.speedingModerate: {
    Intensity.gentle: [
      '{over} {unit} over on {road} for {duration}. That is ticket territory and it saved about {saved}.',
      'Watch {road}: {speed} in a {limit} for {duration}.',
    ],
    Intensity.sassy: [
      '{speed} in a {limit} on {road} for {duration}. Saved {saved}. Hope the {saved} were incredible.',
      '{over} over for {duration} on {road}. The limit is a ceiling, not a suggestion with a tip jar.',
    ],
    Intensity.savage: [
      '{speed} in a {limit} on {road} for {duration}. That bought you {saved}, which you then spent reading this.',
      '{road}, {duration}, {over} over. A radar gun would have had a great day. Your Drive Score did not.',
      'Hey Dale Earnhardt, {road} is a {limit}.',
    ],
  },
  TemplateKey.speedingMajor: {
    Intensity.gentle: [
      '{speed} in a {limit} on {road} for {duration}. This is the kind of speeding that gets expensive.',
      '{over} {unit} over on {road}. Please ease off there.',
    ],
    Intensity.sassy: [
      '{speed} in a {limit}. On {road}. For {duration}. You saved {saved} and lost the moral high ground.',
      '{over} over on {road}. The sign said {limit}. You read it as a dare.',
    ],
    Intensity.savage: [
      "{speed} in a {limit} on {road} for {duration}. That's not a commute, that's a qualifying lap, and it saved {saved}.",
      '{over} over for {duration}. Somewhere a traffic officer felt a disturbance and did not know why.',
      '{road} is a {limit}. You did {speed}. The league has been notified. The league is disappointed.',
    ],
  },
  TemplateKey.speedingReckless: {
    Intensity.gentle: [
      'Reckless: {speed} on {road}. This trip earns no XP and resets your streak.',
      'Reckless speed on {road} ({speed}). No points for this one.',
    ],
    Intensity.sassy: [
      '{speed} on {road}. Reckless. Zero XP, streak gone, and yes, it is on the Wall of Shame.',
      'Reckless: {speed} in a {limit}. Your streak has left the building.',
    ],
    Intensity.savage: [
      '{speed} on {road}. RECKLESS. Zero XP, streak reset, Wall of Shame. Hope the {saved} you saved were worth your entire week.',
      '{speed} in a {limit} for {duration}. That is not a Drive Score, that is a plea deal.',
    ],
  },
  TemplateKey.harshBrakeModerate: {
    Intensity.gentle: [
      'A hard stop on {road} ({peak} m/s²). Leave a little more room.',
    ],
    Intensity.sassy: [
      'Hard brake on {road}, {peak} m/s². Did the road end early or did you just notice it?',
    ],
    Intensity.savage: [
      '{peak} m/s² of brake on {road}. Everything in the cupholders is now in the footwell.',
    ],
  },
  TemplateKey.harshBrakeSevere: {
    Intensity.gentle: [
      'A very hard stop on {road} ({peak} m/s²). Following distance is the fix.',
    ],
    Intensity.sassy: [
      '{peak} m/s² of braking on {road}. The ABS wants to talk to you.',
    ],
    Intensity.savage: [
      '{peak} m/s² on {road}. Your brake pads just filed a complaint with HR.',
      'Slammed it on {road} at {peak} m/s². Whack-a-mole, but the mole is the pedal.',
    ],
  },
  TemplateKey.harshAccelModerate: {
    Intensity.gentle: [
      'Quick off the line on {road} ({peak} m/s²). Smoother starts save fuel.',
    ],
    Intensity.sassy: [
      '{peak} m/s² launch on {road}. The light turned green, not gold.',
    ],
    Intensity.savage: [
      '{peak} m/s² off the line on {road}. The only thing you beat to the next light was your MPG.',
    ],
  },
  TemplateKey.harshAccelSevere: {
    Intensity.gentle: ['Hard acceleration on {road} ({peak} m/s²).'],
    Intensity.sassy: [
      '{peak} m/s² on {road}. Drag strip energy, grocery run destination.',
    ],
    Intensity.savage: [
      '{peak} m/s² on {road}. Fast and Furious, if the furious part is your fuel bill.',
    ],
  },
  TemplateKey.hardCornerModerate: {
    Intensity.gentle: [
      'Took a corner quickly on {road} ({peak} m/s² lateral).',
    ],
    Intensity.sassy: [
      '{peak} m/s² through a corner on {road}. Your passengers are now in the door pocket.',
    ],
    Intensity.savage: [
      '{peak} m/s² of cornering on {road}. The tires squealed. So did everyone in the back.',
    ],
  },
  TemplateKey.hardCornerSevere: {
    Intensity.gentle: [
      'A very fast corner on {road} ({peak} m/s² lateral). Brake before the turn, not in it.',
    ],
    Intensity.sassy: [
      '{peak} m/s² lateral on {road}. This is a sedan, not a go-kart.',
    ],
    Intensity.savage: [
      '{peak} m/s² around a bend on {road}. Initial D called. They said tone it down.',
    ],
  },
  TemplateKey.phoneHandlingMinor: {
    Intensity.gentle: [
      'Your phone was unlocked briefly at {speed} {unit}. Put it in the mount and leave it.',
    ],
    Intensity.sassy: [
      'Phone unlocked at {speed} {unit}. Whatever it was, it could wait {phoneSeconds}.',
    ],
    Intensity.savage: [
      'Touched the phone at {speed} {unit}. {phoneSeconds} of not looking at the road, for a notification.',
    ],
  },
  TemplateKey.phoneHandlingModerate: {
    Intensity.gentle: [
      '{phoneSeconds} on the phone while moving at up to {speed} {unit}.',
    ],
    Intensity.sassy: [
      '{phoneSeconds} of phone time at {speed} {unit}. Thumbs on glass, eyes on vibes.',
    ],
    Intensity.savage: [
      '{phoneSeconds} on the phone at {speed} {unit}. Your friends can see this. All of them. In the feed.',
    ],
  },
  TemplateKey.phoneHandlingMajor: {
    Intensity.gentle: [
      'Extended phone use at {speed} {unit} ({phoneSeconds}). This is the biggest hit to your score.',
    ],
    Intensity.sassy: [
      '{phoneSeconds} of phone at {speed} {unit}. Whatever you typed had better have been a masterpiece.',
    ],
    Intensity.savage: [
      "{phoneSeconds} on the phone at {speed} {unit}. That's a whole TikTok at highway speed. Butterfingers badge incoming.",
      '{phoneSeconds} of scrolling at {speed} {unit}. The road also had content. You missed it.',
    ],
  },
  TemplateKey.idling: {
    Intensity.gentle: [
      'About {idleMinutes} of idling mid-trip. Switch off if you are waiting.',
    ],
    Intensity.sassy: [
      '{idleMinutes} idling. Burning fuel to go nowhere is a strategy, just not a good one.',
    ],
    Intensity.savage: [
      '{idleMinutes} of idling. You paid for gas to sit still. Bold.',
    ],
  },
  TemplateKey.highSpeedCruise: {
    Intensity.gentle: [
      '{cruiseMinutes} above 75 {unit}. Fuel use climbs fast up there.',
    ],
    Intensity.sassy: [
      '{cruiseMinutes} above 75 {unit}. Your MPG filed for divorce.',
    ],
    Intensity.savage: [
      '{cruiseMinutes} above 75 {unit}. Aerodynamics would like a word, and so would your wallet.',
    ],
  },
  TemplateKey.praisePerfect: {
    Intensity.gentle: ['Perfect trip. {distance} with zero events.'],
    Intensity.sassy: [
      '{distance}, zero events. Who are you and what did you do with your usual driving?',
    ],
    Intensity.savage: [
      '{distance}, zero events. Butter smooth. Insufferable about it, probably, but earned.',
    ],
  },
  TemplateKey.praiseCleanLong: {
    Intensity.gentle: ['{distance} with nothing to flag. Great drive.'],
    Intensity.sassy: [
      '{distance} and nothing to roast. Annoying, honestly. Well done.',
    ],
    Intensity.savage: [
      '{distance} and I have nothing. Nothing. Enjoy it, it will not last.',
    ],
  },
  TemplateKey.praiseGood: {
    Intensity.gentle: ['Solid trip: {score}/100 over {distance}.'],
    Intensity.sassy: [
      '{score}/100 over {distance}. Respectable. Not perfect, but respectable.',
    ],
    Intensity.savage: [
      '{score}/100. Good, not great. The gap between you and great is the stuff below.',
    ],
  },
  TemplateKey.praisePhoneFree: {
    Intensity.gentle: ['Zero phone time over {distance}.'],
    Intensity.sassy: [
      'Zero phone time over {distance}. The notifications survived without you.',
    ],
    Intensity.savage: [
      'Zero phone time. The group chat lived. You lived. Everyone lived.',
    ],
  },
  TemplateKey.praiseSmooth: {
    Intensity.gentle: ['Smooth inputs the whole way.'],
    Intensity.sassy: ['Smooth the whole way. Did someone else drive?'],
    Intensity.savage: [
      'Smooth the whole way. Suspiciously smooth. Chauffeur energy.',
    ],
  },
  TemplateKey.praiseLimitRespect: {
    Intensity.gentle: ['Under the limit for the entire trip.'],
    Intensity.sassy: ['Never over the limit. Imagine that. Signs, read.'],
    Intensity.savage: [
      'Not a single second over the limit. Grandma Mode engaged and, somehow, winning.',
    ],
  },
  TemplateKey.unscoredTooShort: {
    Intensity.gentle: ['Too short to judge ({distance}). Logged, not scored.'],
    Intensity.sassy: [
      '{distance}. Too short to score. Barely a trip, honestly.',
    ],
    Intensity.savage: [
      '{distance}. That is not a trip, that is a parking manoeuvre with ambition. Not scored.',
    ],
  },
  TemplateKey.unscoredPassenger: {
    Intensity.gentle: ['Logged as a passenger trip. Not scored.'],
    Intensity.sassy: ['Passenger trip. No XP, no roasts. Enjoy the ride.'],
    Intensity.savage: [
      "Passenger. The driver's score is their problem. Yours is the aux cord.",
    ],
  },
};
