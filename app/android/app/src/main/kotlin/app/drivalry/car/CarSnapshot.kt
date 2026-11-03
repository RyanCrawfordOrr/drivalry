package app.drivalry.car

import org.json.JSONArray
import org.json.JSONObject

/**
 * The Kotlin view of the snapshot JSON that Dart pushes over `app.drivalry/car`
 * (docs/04 §3.3; the Dart source of truth is `lib/car/car_snapshot.dart`).
 *
 * Parsing is lenient: every field has a default so an older or newer phone build
 * still renders something, and a payload that is not even an object yields null.
 */
data class CarSnapshot(
    val version: Int,
    /** Epoch ms when Dart built it; 0 when missing. */
    val at: Long,
    val me: String?,
    /** `mph` or `kmh`. */
    val units: String,
    val drive: Drive,
    val convoy: Convoy?,
    val talk: Talk,
    val crash: Crash,
) {
    val mph: Boolean get() = units != "kmh"

    /** Older than this and the car screen says so instead of showing stale numbers. */
    fun isStale(nowMs: Long, maxAgeMs: Long = STALE_AFTER_MS): Boolean = at <= 0L || nowMs - at > maxAgeMs

    data class Drive(
        val phase: String,
        val tripId: String?,
        val startedAt: Long?,
        val elapsedS: Int?,
        val distanceM: Double,
        val speedMps: Double?,
        val limitMps: Double?,
        val posted: Int?,
        val limitUnit: String,
        val road: String?,
        val overMps: Double?,
        val speedingS: Int,
        val passenger: Boolean,
        /** idle | tentative | passenger | over | cleanish | noLimit | clean */
        val status: String,
    ) {
        val recording: Boolean get() = phase == "active"
        val idle: Boolean get() = phase == "idle"

        companion object {
            val IDLE = Drive(
                phase = "idle", tripId = null, startedAt = null, elapsedS = null, distanceM = 0.0,
                speedMps = null, limitMps = null, posted = null, limitUnit = "mph", road = null,
                overMps = null, speedingS = 0, passenger = false, status = "idle",
            )
        }
    }

    data class Place(val name: String, val lat: Double, val lon: Double)

    data class Member(
        val id: String,
        val name: String,
        val initials: String,
        val isMe: Boolean,
        val isLeader: Boolean,
        val lat: Double?,
        val lon: Double?,
        val speedMps: Double?,
        val etaS: Int?,
        val distanceM: Double?,
        /** behind | silent | null */
        val lost: String?,
        val talking: Boolean,
        val atMs: Long?,
    ) {
        val hasPosition: Boolean get() = lat != null && lon != null
    }

    data class Stop(
        val id: String,
        val name: String,
        val category: String,
        /** proposed | accepted */
        val status: String,
        val lat: Double,
        val lon: Double,
        val up: Int,
        val down: Int,
        val myVote: Int,
        val distanceM: Double?,
    ) {
        val accepted: Boolean get() = status == "accepted"
    }

    data class Convoy(
        val id: String,
        val name: String,
        /** planning | active */
        val status: String,
        val leaderId: String?,
        val destination: Place?,
        val regroup: Place?,
        val members: List<Member>,
        val stops: List<Stop>,
    ) {
        val active: Boolean get() = status == "active"
    }

    data class Talk(
        val available: Boolean,
        val on: Boolean,
        val holding: Boolean,
        val talking: List<String>,
        val peers: Int,
        val reason: String?,
    ) {
        companion object {
            val NONE = Talk(available = false, on = false, holding = false, talking = emptyList(), peers = 0, reason = null)
        }
    }

    data class Crash(val countingDown: Boolean, val secondsLeft: Int, val unresolved: Boolean) {
        companion object {
            val NONE = Crash(countingDown = false, secondsLeft = 0, unresolved = false)
        }
    }

    companion object {
        const val STALE_AFTER_MS = 60_000L

        /** Nothing known yet: what the car shows before the phone has said anything. */
        val EMPTY = CarSnapshot(
            version = 0, at = 0L, me = null, units = "mph",
            drive = Drive.IDLE, convoy = null, talk = Talk.NONE, crash = Crash.NONE,
        )

        fun parse(json: String?): CarSnapshot? {
            if (json.isNullOrBlank()) return null
            val o = try {
                JSONObject(json)
            } catch (_: Exception) {
                return null
            }
            return CarSnapshot(
                version = o.optInt("v", 0),
                at = o.optLong("at", 0L),
                me = o.optStringOrNull("me"),
                units = o.optString("units", "mph"),
                drive = o.optJSONObject("drive")?.let(::parseDrive) ?: Drive.IDLE,
                convoy = o.optJSONObject("convoy")?.let(::parseConvoy),
                talk = o.optJSONObject("talk")?.let(::parseTalk) ?: Talk.NONE,
                crash = o.optJSONObject("crash")?.let(::parseCrash) ?: Crash.NONE,
            )
        }

        private fun parseDrive(o: JSONObject) = Drive(
            phase = o.optString("phase", "idle"),
            tripId = o.optStringOrNull("tripId"),
            startedAt = o.optLongOrNull("startedAt"),
            elapsedS = o.optIntOrNull("elapsedS"),
            distanceM = o.optDouble("distanceM", 0.0).orZero(),
            speedMps = o.optDoubleOrNull("speedMps"),
            limitMps = o.optDoubleOrNull("limitMps"),
            posted = o.optIntOrNull("posted"),
            limitUnit = o.optString("limitUnit", "mph"),
            road = o.optStringOrNull("road"),
            overMps = o.optDoubleOrNull("overMps"),
            speedingS = o.optInt("speedingS", 0),
            passenger = o.optBoolean("passenger", false),
            status = o.optString("status", "idle"),
        )

        private fun parsePlace(o: JSONObject?): Place? {
            if (o == null) return null
            val lat = o.optDoubleOrNull("lat") ?: return null
            val lon = o.optDoubleOrNull("lon") ?: return null
            return Place(o.optString("name", ""), lat, lon)
        }

        private fun parseConvoy(o: JSONObject) = Convoy(
            id = o.optString("id", ""),
            name = o.optString("name", ""),
            status = o.optString("status", "planning"),
            leaderId = o.optStringOrNull("leaderId"),
            destination = parsePlace(o.optJSONObject("destination")),
            regroup = parsePlace(o.optJSONObject("regroup")),
            members = o.optJSONArray("members").objects().map(::parseMember),
            stops = o.optJSONArray("stops").objects().map(::parseStop),
        )

        private fun parseMember(o: JSONObject) = Member(
            id = o.optString("id", ""),
            name = o.optString("name", ""),
            initials = o.optString("initials", ""),
            isMe = o.optBoolean("isMe", false),
            isLeader = o.optBoolean("isLeader", false),
            lat = o.optDoubleOrNull("lat"),
            lon = o.optDoubleOrNull("lon"),
            speedMps = o.optDoubleOrNull("speedMps"),
            etaS = o.optIntOrNull("etaS"),
            distanceM = o.optDoubleOrNull("distanceM"),
            lost = o.optStringOrNull("lost"),
            talking = o.optBoolean("talking", false),
            atMs = o.optLongOrNull("atMs"),
        )

        private fun parseStop(o: JSONObject) = Stop(
            id = o.optString("id", ""),
            name = o.optString("name", ""),
            category = o.optString("category", "food"),
            status = o.optString("status", "proposed"),
            lat = o.optDouble("lat", 0.0).orZero(),
            lon = o.optDouble("lon", 0.0).orZero(),
            up = o.optInt("up", 0),
            down = o.optInt("down", 0),
            myVote = o.optInt("myVote", 0),
            distanceM = o.optDoubleOrNull("distanceM"),
        )

        private fun parseTalk(o: JSONObject) = Talk(
            available = o.optBoolean("available", false),
            on = o.optBoolean("on", false),
            holding = o.optBoolean("holding", false),
            talking = o.optJSONArray("talking").strings(),
            peers = o.optInt("peers", 0),
            reason = o.optStringOrNull("reason"),
        )

        private fun parseCrash(o: JSONObject) = Crash(
            countingDown = o.optBoolean("countingDown", false),
            secondsLeft = o.optInt("secondsLeft", 0),
            unresolved = o.optBoolean("unresolved", false),
        )

        // org.json returns the string "null" for JSON null with optString; these keep nulls null.
        private fun JSONObject.optStringOrNull(key: String): String? =
            if (isNull(key)) null else optString(key, "").takeIf { it.isNotEmpty() }

        private fun JSONObject.optDoubleOrNull(key: String): Double? =
            if (isNull(key)) null else optDouble(key).takeIf { !it.isNaN() }

        private fun JSONObject.optIntOrNull(key: String): Int? =
            if (isNull(key)) null else optDoubleOrNull(key)?.toInt()

        private fun JSONObject.optLongOrNull(key: String): Long? =
            if (isNull(key)) null else optDoubleOrNull(key)?.toLong()

        private fun Double.orZero(): Double = if (isNaN()) 0.0 else this

        private fun JSONArray?.objects(): List<JSONObject> {
            if (this == null) return emptyList()
            val out = ArrayList<JSONObject>(length())
            for (i in 0 until length()) optJSONObject(i)?.let(out::add)
            return out
        }

        private fun JSONArray?.strings(): List<String> {
            if (this == null) return emptyList()
            val out = ArrayList<String>(length())
            for (i in 0 until length()) if (!isNull(i)) out.add(optString(i))
            return out
        }
    }
}
