/// Lifecycle of a trip row in the local database.
enum TripPhase {
  /// Fixes are still arriving (or the app has not yet seen the end event).
  recording('recording'),

  /// Ended; waiting to be matched and scored.
  pendingPassenger('pendingPassenger'),

  /// Scored by the engine.
  scored('scored'),

  /// Finalised but not scored: too short, or a passenger trip.
  unscored('unscored'),

  /// Tentative trip that was never confirmed. Rows in this phase are deleted.
  discarded('discarded');

  const TripPhase(this.wire);
  final String wire;

  static TripPhase fromWire(String wire) =>
      values.firstWhere((p) => p.wire == wire, orElse: () => recording);
}
