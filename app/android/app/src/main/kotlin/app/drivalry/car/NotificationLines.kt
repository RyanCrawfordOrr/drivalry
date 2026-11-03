package app.drivalry.car

/**
 * Which notification lines may describe the recorder's current trip.
 *
 * Dart's `ongoingNotification` line names the trip it is about. The foreground service shows
 * it only for that very trip, and a line restored from disk must name one: a tentative-phase
 * line ("Looks like a drive") has no trip id, and if the process died before Dart cleared
 * it, it would otherwise describe whatever trip comes next.
 */
object NotificationLines {
    /** A persisted line is worth restoring only when it names its trip. */
    fun restorable(tripId: String?): Boolean = tripId != null

    /** The line the notification for [currentTripId] may show: one about that trip, or none. */
    fun forTrip(line: CarState.NotificationLine?, currentTripId: String?): CarState.NotificationLine? =
        line?.takeIf { it.tripId != null && it.tripId == currentTripId }
}
