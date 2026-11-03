package app.drivalry.tracking

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicInteger

/**
 * Durable event spool (docs/08-tracking-channel.md §5).
 *
 * `<filesDir>/tracking/spool.jsonl` holds one JSON object per line, the exact maps that
 * also go out on the live EventChannel. At 8 MB the file is rotated to `spool.1.jsonl`
 * and an older `spool.1.jsonl` is dropped. [drain] returns the lines of both files in
 * order and truncates them.
 *
 * All file access runs on one single-thread executor, so appends from the main thread,
 * receivers and the sensor thread never interleave and `drain` sees a consistent state.
 *
 * Serialisation is done by hand rather than with `JSONObject.toString()` because
 * Android's org.json prints `51.0` as `51`, which would come back from the spool as an
 * `int` and break the "spool and live stream carry the same maps" promise. Parsing uses
 * org.json; it yields Double for anything with a decimal point or exponent and
 * Integer/Long otherwise, which is exactly what the StandardMessageCodec needs.
 */
class Spool(private val dir: File) {
    private val executor = Executors.newSingleThreadExecutor(
        ThreadFactory { runnable -> Thread(runnable, "drivalry-spool").apply { isDaemon = true } },
    )
    private val current = File(dir, "spool.jsonl")
    private val rotated = File(dir, "spool.1.jsonl")

    /**
     * Lines waiting in both files. Written only on the executor thread, read from any
     * thread by [count], so `getState` never waits behind a file append. -1 until the
     * first count has run.
     */
    private val lineCount = AtomicInteger(-1)

    init {
        // Count once in the background so the first [count] has a real answer.
        executor.execute { ensureCounted() }
    }

    /** Appends one event. Never blocks the caller. */
    fun append(event: Map<String, Any?>) {
        val line = JsonLines.encode(event)
        executor.execute {
            try {
                ensureCounted()
                dir.mkdirs()
                OutputStreamWriter(FileOutputStream(current, true), Charsets.UTF_8).use { writer ->
                    writer.write(line)
                    writer.write("\n")
                }
                lineCount.incrementAndGet()
                if (current.length() >= ROTATE_BYTES) rotate()
            } catch (e: Exception) {
                Log.w(TAG, "spool append failed", e)
            }
        }
    }

    /**
     * Number of spooled events as of the last completed append. Non-blocking: it is read
     * on the main thread for every `getState`, which must not queue behind file I/O.
     */
    fun count(): Int = lineCount.get().coerceAtLeast(0)

    /** Parses and removes every spooled event, oldest first. Blocks until done. */
    fun drain(): List<Map<String, Any?>> = executor.submit<List<Map<String, Any?>>> {
        val out = ArrayList<Map<String, Any?>>()
        for (file in listOf(rotated, current)) {
            if (!file.exists()) continue
            try {
                file.forEachLine(Charsets.UTF_8) { line ->
                    if (line.isBlank()) return@forEachLine
                    try {
                        out.add(JsonLines.decodeObject(line))
                    } catch (e: Exception) {
                        Log.w(TAG, "dropping unreadable spool line", e)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "spool read failed for ${file.name}", e)
            }
            file.delete()
        }
        lineCount.set(0)
        out
    }.get()

    private fun rotate() {
        if (rotated.exists()) rotated.delete()
        if (!current.renameTo(rotated)) {
            // Could not rotate (unlikely); keep the current file rather than lose data.
            Log.w(TAG, "spool rotation failed")
        }
        lineCount.set(countLines())
    }

    /** Executor thread only. */
    private fun ensureCounted() {
        if (lineCount.get() < 0) lineCount.set(countLines())
    }

    private fun countLines(): Int {
        var n = 0
        for (file in listOf(rotated, current)) {
            if (!file.exists()) continue
            try {
                file.forEachLine(Charsets.UTF_8) { if (it.isNotBlank()) n++ }
            } catch (_: Exception) {
            }
        }
        return n
    }

    private companion object {
        const val TAG = "Drivalry.Spool"
        const val ROTATE_BYTES = 8L * 1024 * 1024
    }
}

/** Type-preserving JSON Lines codec shared by the spool. */
internal object JsonLines {
    fun encode(value: Any?): String = StringBuilder().also { write(it, value) }.toString()

    private fun write(sb: StringBuilder, value: Any?) {
        when (value) {
            null -> sb.append("null")
            is Boolean -> sb.append(value)
            is Int, is Long, is Short, is Byte -> sb.append(value.toString())
            is Float -> writeDouble(sb, value.toDouble())
            is Double -> writeDouble(sb, value)
            is Number -> writeDouble(sb, value.toDouble())
            is String -> sb.append(JSONObject.quote(value))
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, v) in value) {
                    if (!first) sb.append(',')
                    first = false
                    sb.append(JSONObject.quote(k.toString())).append(':')
                    write(sb, v)
                }
                sb.append('}')
            }
            is Iterable<*> -> {
                sb.append('[')
                var first = true
                for (v in value) {
                    if (!first) sb.append(',')
                    first = false
                    write(sb, v)
                }
                sb.append(']')
            }
            is Array<*> -> write(sb, value.asList())
            else -> sb.append(JSONObject.quote(value.toString()))
        }
    }

    /** Always keeps a decimal point / exponent so the value parses back as a Double. */
    private fun writeDouble(sb: StringBuilder, d: Double) {
        if (d.isNaN() || d.isInfinite()) {
            sb.append("null")
            return
        }
        sb.append(java.lang.Double.toString(d)) // e.g. "51.0", "1.0E-5", "-0.0"
    }

    @Suppress("UNCHECKED_CAST")
    fun decodeObject(line: String): Map<String, Any?> {
        val parsed = JSONTokener(line).nextValue()
        if (parsed !is JSONObject) throw IllegalArgumentException("not an object")
        return toKotlin(parsed) as Map<String, Any?>
    }

    @Suppress("UNCHECKED_CAST")
    private fun toKotlin(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> LinkedHashMap<String, Any?>(value.length()).also { map ->
            val keys = value.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                map[k] = toKotlin(value.opt(k))
            }
        }
        is JSONArray -> ArrayList<Any?>(value.length()).also { list ->
            for (i in 0 until value.length()) list.add(toKotlin(value.opt(i)))
        }
        else -> value // Boolean, Integer, Long, Double, String
    }
}
