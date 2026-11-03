package app.drivalry.car

import kotlin.math.roundToInt

/** Number formatting for car templates. Pure; mirrors `lib/widgets/units.dart`. */
object CarFormat {
    private const val MPH = 0.44704
    private const val MILE = 1609.344

    /** "31 mph" / "50 km/h". */
    fun speed(mps: Double, mph: Boolean): String =
        if (mph) "${(mps / MPH).roundToInt()} mph" else "${(mps * 3.6).roundToInt()} km/h"

    /** Just the number, for "Limit 35"-style labels. */
    fun speedNumber(mps: Double, mph: Boolean): Int =
        if (mph) (mps / MPH).roundToInt() else (mps * 3.6).roundToInt()

    /** "0.4 mi" / "12 mi" / "350 m" / "3.2 km". */
    fun distance(metres: Double, mph: Boolean): String {
        if (mph) {
            val mi = metres / MILE
            return when {
                mi < 0.1 -> "${(metres * 3.28084 / 10).roundToInt() * 10} ft"
                mi < 10 -> String.format(java.util.Locale.US, "%.1f mi", mi)
                else -> "${mi.roundToInt()} mi"
            }
        }
        return when {
            metres < 1000 -> "${(metres / 10).roundToInt() * 10} m"
            metres < 10_000 -> String.format(java.util.Locale.US, "%.1f km", metres / 1000)
            else -> "${(metres / 1000).roundToInt()} km"
        }
    }

    /** "12 min" / "1 h 05 min" / "< 1 min". */
    fun eta(seconds: Int): String {
        val m = (seconds / 60.0).roundToInt()
        if (m < 1) return "< 1 min"
        if (m < 60) return "$m min"
        val h = m / 60
        val r = m % 60
        return if (r == 0) "$h h" else "$h h ${r.toString().padStart(2, '0')} min"
    }

    /** "1h 12m" / "9 min" / "45 s" for the trip clock. */
    fun elapsed(seconds: Int): String {
        if (seconds >= 3600) return "${seconds / 3600}h ${(seconds % 3600) / 60}m"
        if (seconds >= 60) return "${seconds / 60} min"
        return "$seconds s"
    }

    /** "just now" / "40 s ago" / "3 min ago" for a member's last position. */
    fun age(atMs: Long?, nowMs: Long): String? {
        if (atMs == null) return null
        val s = ((nowMs - atMs) / 1000).coerceAtLeast(0)
        return when {
            s < 10 -> "just now"
            s < 60 -> "$s s ago"
            else -> "${s / 60} min ago"
        }
    }

    /** Display label for a stop category wire value. */
    fun category(wire: String): String = when (wire) {
        "gas" -> "Gas"
        "food" -> "Food"
        "restroom" -> "Restroom"
        "photo" -> "Photo stop"
        "lodging" -> "Lodging"
        "charging" -> "Charging"
        else -> wire.replaceFirstChar { it.uppercase() }
    }

    /** The Drive pane's one-line status, from the Dart status code. */
    fun status(d: CarSnapshot.Drive, mph: Boolean): String = when (d.status) {
        "idle" -> "Not recording"
        "tentative" -> "Looks like a drive"
        "passenger" -> "Passenger · not scored"
        "over" -> "${speedNumber(d.overMps ?: 0.0, mph)} over"
        "cleanish" -> "${elapsed(d.speedingS)} over so far"
        "noLimit" -> "No limit data here"
        else -> "Clean so far"
    }
}
