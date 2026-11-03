package app.drivalry.car

import android.Manifest
import android.content.pm.PackageManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarLocation
import androidx.car.app.model.ItemList
import androidx.car.app.model.Metadata
import androidx.car.app.model.Place
import androidx.car.app.model.PlaceListMapTemplate
import androidx.car.app.model.PlaceMarker
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Members, the regroup pin, accepted stops and the destination as places on the
 * host-drawn map (`PlaceListMapTemplate`, the POI category's template). One step below
 * the Convoy tab because a `TabTemplate` cannot contain it.
 */
class ConvoyMapScreen(carContext: CarContext) : Screen(carContext), CarState.Listener {
    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                CarState.addListener(this@ConvoyMapScreen)
                invalidate()
            }

            override fun onStop(owner: LifecycleOwner) {
                CarState.removeListener(this@ConvoyMapScreen)
            }
        })
    }

    override fun onCarStateChanged() {
        invalidate()
    }

    override fun onGetTemplate(): Template {
        val s = CarState.snapshot
        val c = s.convoy
        val builder = PlaceListMapTemplate.Builder()
            .setTitle(c?.name ?: "Convoy")
            .setHeaderAction(Action.BACK)
            // The host throws without the location permission; the phone app asks for it.
            .setCurrentLocationEnabled(
                ContextCompat.checkSelfPermission(carContext, Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED,
            )
        if (c == null) {
            return builder.setItemList(ItemList.Builder().setNoItemsMessage("No convoy right now").build()).build()
        }
        val now = System.currentTimeMillis()
        val limit = placeLimit()
        val list = ItemList.Builder()
        var count = 0

        fun add(row: Row) {
            if (count < limit) {
                list.addItem(row)
                count++
            }
        }

        c.regroup?.let { r ->
            add(
                placeRow(
                    title = r.name.ifEmpty { "Regroup here" },
                    text = "Leader's regroup point",
                    lat = r.lat,
                    lon = r.lon,
                    label = "R",
                    color = CarColor.RED,
                ),
            )
        }
        for (m in c.members) {
            if (!m.hasPosition) continue
            val parts = ArrayList<String>()
            if (m.isLeader) parts.add("Leader")
            when (m.lost) {
                "behind" -> parts.add("Fell behind")
                "silent" -> parts.add("Gone quiet")
            }
            if (!m.isMe) m.distanceM?.let { parts.add(CarFormat.distance(it, s.mph)) }
            m.etaS?.let { parts.add("ETA ${CarFormat.eta(it)}") }
            CarFormat.age(m.atMs, now)?.let { if (it != "just now") parts.add(it) }
            add(
                placeRow(
                    title = if (m.isMe) "${m.name} (you)" else m.name,
                    text = parts.joinToString(" · ").ifEmpty { "On the way" },
                    lat = m.lat!!,
                    lon = m.lon!!,
                    label = m.initials.take(3).ifEmpty { "?" },
                    color = when {
                        m.isMe -> CarColor.BLUE
                        m.lost != null -> CarColor.YELLOW
                        else -> CarColor.GREEN
                    },
                ),
            )
        }
        for (st in c.stops.filter { it.accepted }) {
            add(
                placeRow(
                    title = st.name,
                    text = "Stop · ${CarFormat.category(st.category)}" +
                        (st.distanceM?.let { " · ${CarFormat.distance(it, s.mph)}" } ?: ""),
                    lat = st.lat,
                    lon = st.lon,
                    label = "S",
                    color = CarColor.DEFAULT,
                ),
            )
        }
        c.destination?.let { d ->
            add(placeRow(title = d.name, text = "Destination", lat = d.lat, lon = d.lon, label = "D", color = CarColor.DEFAULT))
        }
        if (count == 0) list.setNoItemsMessage("No positions yet")

        val me = c.members.firstOrNull { it.isMe && it.hasPosition }
        if (me != null) builder.setAnchor(Place.Builder(CarLocation.create(me.lat!!, me.lon!!)).build())
        return builder.setItemList(list.build()).build()
    }

    private fun placeRow(title: String, text: String, lat: Double, lon: Double, label: String, color: CarColor): Row =
        Row.Builder()
            .setTitle(title)
            .addText(text)
            .setMetadata(
                Metadata.Builder()
                    .setPlace(
                        Place.Builder(CarLocation.create(lat, lon))
                            .setMarker(PlaceMarker.Builder().setLabel(label).setColor(color).build())
                            .build(),
                    )
                    .build(),
            )
            .build()

    private fun placeLimit(): Int = try {
        if (carContext.carAppApiLevel >= 2) {
            carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_PLACE_LIST)
        } else {
            MainTabScreen.DEFAULT_LIST_LIMIT
        }
    } catch (_: Exception) {
        MainTabScreen.DEFAULT_LIST_LIMIT
    }
}
