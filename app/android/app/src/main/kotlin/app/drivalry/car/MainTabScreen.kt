package app.drivalry.car

import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Tab
import androidx.car.app.model.TabContents
import androidx.car.app.model.TabTemplate
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import app.drivalry.R
import app.drivalry.tracking.TrackingRuntime

/** Icons shared by the car screens. */
internal object CarIcons {
    fun of(carContext: CarContext, res: Int): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(carContext, res)).build()

    fun category(carContext: CarContext, wire: String): CarIcon = of(
        carContext,
        when (wire) {
            "gas" -> R.drawable.ic_stop_gas
            "restroom" -> R.drawable.ic_stop_restroom
            "photo" -> R.drawable.ic_stop_photo
            "lodging" -> R.drawable.ic_stop_lodging
            "charging" -> R.drawable.ic_stop_charging
            else -> R.drawable.ic_stop_food
        },
    )

    val CATEGORIES = listOf("gas", "food", "restroom", "photo", "lodging", "charging")
}

/**
 * The root Android Auto screen (docs/04 §3): four tabs, convoy first because the app's
 * car category is Point of Interest.
 *
 * ```
 * Convoy  ListTemplate: destination row (opens the map), then cars nearest first
 * Stops   ListTemplate: "Propose a stop" (GridTemplate of categories), then stops with a vote toggle
 * Drive   PaneTemplate: status · speed/limit · trip, with Passenger / End trip
 * Talk    GridTemplate: tap-to-talk (20 s auto-release) and the radio switch
 * ```
 *
 * `TabTemplate` cannot hold a `PlaceListMapTemplate`, so the map is one step deeper
 * ([ConvoyMapScreen]). Row titles stay constant while values change, so updates count
 * as refreshes rather than new template steps.
 */
class MainTabScreen(carContext: CarContext) : Screen(carContext), CarState.Listener {
    private var activeTab = TAB_CONVOY
    private val main = Handler(Looper.getMainLooper())
    private var talkingSince = 0L
    private val releaseTalk = Runnable { stopTalking(auto = true) }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                CarState.init(carContext)
                CarState.addListener(this@MainTabScreen)
                invalidate()
            }

            override fun onStop(owner: LifecycleOwner) {
                CarState.removeListener(this@MainTabScreen)
                if (talkingSince != 0L) stopTalking(auto = false)
            }
        })
    }

    override fun onCarStateChanged() {
        invalidate()
    }

    override fun onGetTemplate(): Template {
        val s = CarState.snapshot
        val builder = TabTemplate.Builder(
            object : TabTemplate.TabCallback {
                override fun onTabSelected(tabContentId: String) {
                    activeTab = tabContentId
                    invalidate()
                }
            },
        )
            .setHeaderAction(Action.APP_ICON)
            .addTab(tab(TAB_CONVOY, "Convoy", R.drawable.ic_car_convoy))
            .addTab(tab(TAB_STOPS, "Stops", R.drawable.ic_car_stops))
            .addTab(tab(TAB_DRIVE, "Drive", R.drawable.ic_car_drive))
            .addTab(tab(TAB_TALK, "Talk", R.drawable.ic_car_talk))
            .setActiveTabContentId(activeTab)
        val content: Template = when (activeTab) {
            TAB_STOPS -> stopsTemplate(s)
            TAB_DRIVE -> driveTemplate(s)
            TAB_TALK -> talkTemplate(s)
            else -> convoyTemplate(s)
        }
        return builder.setTabContents(TabContents.Builder(content).build()).build()
    }

    private fun tab(id: String, title: String, icon: Int): Tab =
        Tab.Builder().setTitle(title).setIcon(CarIcons.of(carContext, icon)).setContentId(id).build()

    // --- Convoy -----------------------------------------------------------------------------------

    private fun convoyTemplate(s: CarSnapshot): Template {
        val c = s.convoy
        if (c == null) {
            return message(
                if (phoneAsleep(s)) "Open Drivalry on your phone to see your convoy." else "No convoy right now. Start or join one on your phone.",
                R.drawable.ic_car_convoy,
            )
        }
        val limit = listLimit()
        val list = ItemList.Builder()
        var used = 0

        val dest = c.destination
        val destRow = Row.Builder()
            .setTitle(dest?.name ?: c.name)
            .setImage(CarIcons.of(carContext, R.drawable.ic_car_map))
            .setBrowsable(true)
            .setOnClickListener { screenManager.push(ConvoyMapScreen(carContext)) }
        val destText = buildString {
            if (!c.active) append("Planning · ") else append("Convoy · ")
            append("${c.members.size} ${if (c.members.size == 1) "car" else "cars"}")
            if (c.regroup != null) append(" · Regroup pin set")
            if (phoneAsleep(s)) append(" · phone app asleep")
            append(" · Map")
        }
        destRow.addText(destText)
        list.addItem(destRow.build())
        used++

        val now = System.currentTimeMillis()
        val members = c.members
        val room = (limit - used).coerceAtLeast(0)
        val shown = if (members.size > room) members.take((room - 1).coerceAtLeast(0)) else members
        for (m in shown) {
            list.addItem(memberRow(m, s.mph, now))
            used++
        }
        if (shown.size < members.size) {
            list.addItem(
                Row.Builder()
                    .setTitle("+${members.size - shown.size} more")
                    .addText("On the map")
                    .setBrowsable(true)
                    .setOnClickListener { screenManager.push(ConvoyMapScreen(carContext)) }
                    .build(),
            )
        }
        return ListTemplate.Builder().setSingleList(list.build()).build()
    }

    private fun memberRow(m: CarSnapshot.Member, mph: Boolean, now: Long): Row {
        val title = buildString {
            append(m.name)
            if (m.isMe) append(" (you)")
            if (m.isLeader) append(" · leader")
        }
        val parts = ArrayList<String>()
        when (m.lost) {
            "behind" -> parts.add("Fell behind")
            "silent" -> parts.add("Gone quiet")
        }
        if (m.talking) parts.add("Talking")
        if (!m.isMe) m.distanceM?.let { parts.add(CarFormat.distance(it, mph)) }
        m.etaS?.let { parts.add("ETA ${CarFormat.eta(it)}") }
        m.speedMps?.let { parts.add(CarFormat.speed(it, mph)) }
        if (!m.hasPosition) parts.add("No position yet") else CarFormat.age(m.atMs, now)?.let { if (it != "just now") parts.add(it) }
        val row = Row.Builder().setTitle(title)
        if (parts.isNotEmpty()) row.addText(parts.joinToString(" · "))
        return row.build()
    }

    // --- Stops ------------------------------------------------------------------------------------

    private fun stopsTemplate(s: CarSnapshot): Template {
        val c = s.convoy ?: return message(
            if (phoneAsleep(s)) "Open Drivalry on your phone to see stops." else "Stops belong to a convoy. Start one on your phone.",
            R.drawable.ic_car_stops,
        )
        val limit = listLimit()
        val list = ItemList.Builder()
        list.addItem(
            Row.Builder()
                .setTitle("Propose a stop")
                .addText("Gas, food, restroom, photo, lodging, charging · near here")
                .setImage(CarIcons.of(carContext, R.drawable.ic_car_stops))
                .setBrowsable(true)
                .setOnClickListener { screenManager.push(ProposeStopScreen(carContext, c.id)) }
                .build(),
        )
        for (st in c.stops.take((limit - 1).coerceAtLeast(1))) {
            val text = buildString {
                append(CarFormat.category(st.category))
                st.distanceM?.let { append(" · ").append(CarFormat.distance(it, s.mph)) }
                append(" · ▲${st.up} ▼${st.down}")
                if (st.accepted) append(" · Accepted")
            }
            val row = Row.Builder()
                .setTitle(st.name)
                .addText(text)
                .setImage(CarIcons.category(carContext, st.category))
            // The toggle is "I'm in": my upvote on this stop.
            row.setToggle(
                Toggle.Builder { checked ->
                    dispatch(
                        CarAction(
                            CarActions.VOTE_STOP,
                            mapOf("convoyId" to c.id, "stopId" to st.id, "vote" to if (checked) 1 else 0),
                        ),
                    )
                }.setChecked(st.myVote > 0).build(),
            )
            list.addItem(row.build())
        }
        if (c.stops.isEmpty()) list.setNoItemsMessage("No stops proposed yet")
        return ListTemplate.Builder().setSingleList(list.build()).build()
    }

    // --- Drive ------------------------------------------------------------------------------------

    private fun driveTemplate(s: CarSnapshot): Template {
        val d = s.drive
        val asleep = phoneAsleep(s)
        val nativePhase = nativePhase()
        val pane = Pane.Builder()

        if (s.crash.countingDown) {
            pane.addRow(Row.Builder().setTitle("Possible crash").addText("Are you OK? ${s.crash.secondsLeft} s before contacts are told").build())
            pane.addAction(Action.Builder().setTitle("I'm OK").setOnClickListener { dispatch(CarAction(CarActions.CRASH_OK)) }.build())
            pane.addAction(Action.Builder().setTitle("Send help").setOnClickListener { dispatch(CarAction(CarActions.CRASH_HELP)) }.build())
            return PaneTemplate.Builder(pane.build()).build()
        }

        val status = when {
            asleep && nativePhase == "active" -> "Recording · open Drivalry on your phone for the live limit"
            asleep && nativePhase == "tentative" -> "Looks like a drive · phone app asleep"
            asleep -> "Not recording · phone app asleep"
            else -> CarFormat.status(d, s.mph)
        }
        pane.addRow(Row.Builder().setTitle("Status").addText(status).build())

        val speedText = if (asleep || d.idle) {
            if (d.idle && !asleep) "Trips start on their own when you drive" else "—"
        } else {
            buildString {
                d.speedMps?.let { append(CarFormat.speed(it, s.mph)) }
                d.posted?.let {
                    if (isNotEmpty()) append(" · ")
                    append("Limit $it")
                }
                d.road?.let {
                    if (isNotEmpty()) append(" · ")
                    append(it)
                }
                if (isEmpty()) append("Waiting for GPS")
            }
        }
        pane.addRow(Row.Builder().setTitle("Speed").addText(speedText).build())

        val tripText = if (d.recording && !asleep) {
            buildString {
                d.elapsedS?.let { append(CarFormat.elapsed(it)) }
                if (isNotEmpty()) append(" · ")
                append(CarFormat.distance(d.distanceM, s.mph))
                if (d.speedingS > 0 && d.status != "cleanish") append(" · ${CarFormat.elapsed(d.speedingS)} over")
            }
        } else if (!asleep && d.phase == "tentative") {
            "Confirming it's a drive"
        } else {
            "—"
        }
        pane.addRow(Row.Builder().setTitle("Trip").addText(tripText).build())

        val recording = if (asleep) nativePhase == "active" else d.recording
        if (recording) {
            if (!d.passenger) {
                pane.addAction(
                    Action.Builder().setTitle("Passenger").setOnClickListener {
                        dispatch(CarAction(CarActions.MARK_PASSENGER, mapOf("tripId" to (d.tripId ?: nativeTripId()))))
                    }.build(),
                )
            }
            pane.addAction(
                Action.Builder().setTitle("End trip").setOnClickListener {
                    dispatch(CarAction(CarActions.END_TRIP))
                }.build(),
            )
        }
        return PaneTemplate.Builder(pane.build()).build()
    }

    // --- Talk -------------------------------------------------------------------------------------

    private fun talkTemplate(s: CarSnapshot): Template {
        val t = s.talk
        val c = s.convoy
        if (phoneAsleep(s) || !CarState.dartAttached) {
            return message("Open Drivalry on your phone to talk to the convoy.", R.drawable.ic_car_talk)
        }
        if (!t.available || c == null) {
            val why = when (t.reason) {
                "convoyNotActive" -> "The convoy hasn't started yet."
                "signedOut" -> "Sign in on your phone first."
                else -> "Start or join a convoy on your phone to talk."
            }
            return message(why, R.drawable.ic_car_talk)
        }
        val talking = talkingSince != 0L
        val list = ItemList.Builder()
        val talkItem = GridItem.Builder()
            .setImage(CarIcons.of(carContext, R.drawable.ic_car_talk), GridItem.IMAGE_TYPE_ICON)
            .setTitle(if (talking) "Talking…" else "Talk")
            .setText(
                when {
                    talking -> "Tap to stop · 20 s max"
                    t.reason == "noPermission" -> "Allow the microphone on your phone"
                    t.reason == "error" -> "Radio error · tap to retry"
                    !t.on -> "Tap to turn the radio on and talk"
                    t.talking.isNotEmpty() -> "${t.talking.joinToString(", ")} talking"
                    else -> "Tap to talk · 20 s max"
                },
            )
            .setOnClickListener { if (talking) stopTalking(auto = false) else startTalking(c.id) }
        list.addItem(talkItem.build())

        val radioItem = GridItem.Builder()
            .setImage(CarIcons.of(carContext, R.drawable.ic_car_convoy), GridItem.IMAGE_TYPE_ICON)
            .setTitle(if (t.on) "Radio on" else "Radio off")
            .setText(if (t.on) "${t.peers} connected · tap to turn off" else "Tap to turn on")
            .setOnClickListener {
                dispatch(CarAction(if (t.on) CarActions.RADIO_OFF else CarActions.RADIO_ON, mapOf("convoyId" to c.id)))
            }
        list.addItem(radioItem.build())
        return GridTemplate.Builder().setSingleList(list.build()).build()
    }

    private fun startTalking(convoyId: String) {
        talkingSince = System.currentTimeMillis()
        invalidate()
        val outcome = dispatch(CarAction(CarActions.TALK_START, mapOf("convoyId" to convoyId))) { ok ->
            if (!ok) {
                talkingSince = 0L
                invalidate()
            }
        }
        if (outcome == CarActions.Outcome.QUEUED) {
            // No Dart, no radio: the callback does not fire for a queued action.
            talkingSince = 0L
            invalidate()
            return
        }
        main.removeCallbacks(releaseTalk)
        main.postDelayed(releaseTalk, TALK_MAX_MS)
    }

    private fun stopTalking(auto: Boolean) {
        main.removeCallbacks(releaseTalk)
        if (talkingSince == 0L) return
        talkingSince = 0L
        val convoyId = CarState.snapshot.convoy?.id
        dispatch(CarAction(CarActions.TALK_STOP, if (convoyId == null) emptyMap() else mapOf("convoyId" to convoyId)))
        if (auto) toast("Released after 20 s")
        invalidate()
    }

    // --- Shared -----------------------------------------------------------------------------------

    /**
     * One message per tap: Dart's answer (or the native result) arrives through the callback,
     * a queued action only through the return value (see [CarActions.dispatch]).
     */
    private fun dispatch(action: CarAction, onResult: ((Boolean) -> Unit)? = null): CarActions.Outcome {
        val outcome = CarActions.dispatch(carContext, action) { ok ->
            if (!ok && action.name != CarActions.TALK_STOP) toast("Couldn't do that. Check your phone.")
            onResult?.invoke(ok)
        }
        if (outcome == CarActions.Outcome.QUEUED) toast("Open Drivalry on your phone to finish that")
        return outcome
    }

    private fun toast(text: String) {
        try {
            CarToast.makeText(carContext, text, CarToast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            // Host gone; nothing to show.
        }
    }

    private fun message(text: String, icon: Int): Template =
        MessageTemplate.Builder(text).setIcon(CarIcons.of(carContext, icon)).build()

    /** Dart has not spoken for a minute and is not attached: numbers would be stale. */
    private fun phoneAsleep(s: CarSnapshot): Boolean =
        !CarState.dartAttached && s.isStale(System.currentTimeMillis())

    private fun nativePhase(): String = try {
        TrackingRuntime.get(carContext).state()["phase"] as? String ?: "idle"
    } catch (_: Exception) {
        "idle"
    }

    private fun nativeTripId(): String? = try {
        TrackingRuntime.get(carContext).state()["tripId"] as? String
    } catch (_: Exception) {
        null
    }

    private fun listLimit(): Int = try {
        if (carContext.carAppApiLevel >= 2) {
            carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
        } else {
            DEFAULT_LIST_LIMIT
        }
    } catch (_: Exception) {
        DEFAULT_LIST_LIMIT
    }

    companion object {
        const val TAB_CONVOY = "convoy"
        const val TAB_STOPS = "stops"
        const val TAB_DRIVE = "drive"
        const val TAB_TALK = "talk"
        const val TALK_MAX_MS = 20_000L
        const val DEFAULT_LIST_LIMIT = 6
    }
}
