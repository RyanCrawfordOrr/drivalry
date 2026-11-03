package app.drivalry.car

import org.json.JSONArray
import org.json.JSONObject

/** One car action waiting for (or on its way to) Dart: `{name, args}`. */
data class CarAction(val name: String, val args: Map<String, Any?> = emptyMap()) {
    fun toJson(): JSONObject = JSONObject().put("name", name).put("args", JSONObject(args))

    /** The shape the Dart side decodes (`CarAction.fromWire`). */
    fun toWire(): Map<String, Any?> = mapOf("name" to name, "args" to args)

    companion object {
        fun fromJson(o: JSONObject): CarAction? {
            val name = o.optString("name", "")
            if (name.isEmpty()) return null
            val args = HashMap<String, Any?>()
            o.optJSONObject("args")?.let { a ->
                for (k in a.keys()) args[k] = if (a.isNull(k)) null else a.opt(k)
            }
            return CarAction(name, args)
        }
    }
}

/**
 * Actions taken while no Flutter isolate was listening (notification tap with the
 * app dead, a car-screen tap before the app came up). Persisted as a JSON array
 * and handed to Dart on its next `drainActions`. Pure so it is unit-testable; the
 * storage lives in [CarState].
 */
object ActionQueue {
    /** Enough for a drive's worth of taps; older entries are dropped first. */
    const val MAX = 32

    fun encode(actions: List<CarAction>): String {
        val arr = JSONArray()
        for (a in actions.takeLast(MAX)) arr.put(a.toJson())
        return arr.toString()
    }

    fun decode(json: String?): List<CarAction> {
        if (json.isNullOrBlank()) return emptyList()
        val arr = try {
            JSONArray(json)
        } catch (_: Exception) {
            return emptyList()
        }
        val out = ArrayList<CarAction>(arr.length())
        for (i in 0 until arr.length()) arr.optJSONObject(i)?.let(CarAction::fromJson)?.let(out::add)
        return out
    }

    /** Appends, collapsing a repeat of the same action+args so taps do not pile up. */
    fun append(existing: List<CarAction>, action: CarAction): List<CarAction> {
        val kept = existing.filterNot { it == action }
        return (kept + action).takeLast(MAX)
    }
}
