package app.drivalry.car

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.Template

/**
 * "Propose a stop": one tap per category. The phone picks the place (its current
 * position; the Places search is a phone-screen feature) and tells the convoy.
 */
class ProposeStopScreen(carContext: CarContext, private val convoyId: String) : Screen(carContext) {
    private var sending = false

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        for (wire in CarIcons.CATEGORIES) {
            // A loading grid item may not carry an image (the host throws), so swap them.
            val item = GridItem.Builder()
                .setTitle(CarFormat.category(wire))
                .setText("Near here")
                .setOnClickListener { propose(wire) }
            if (sending) item.setLoading(true) else item.setImage(CarIcons.category(carContext, wire), GridItem.IMAGE_TYPE_ICON)
            list.addItem(item.build())
        }
        return GridTemplate.Builder()
            .setTitle("Propose a stop")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }

    private fun propose(category: String) {
        if (sending) return
        sending = true
        invalidate()
        val outcome = CarActions.dispatch(
            carContext,
            CarAction(CarActions.PROPOSE_STOP, mapOf("convoyId" to convoyId, "category" to category)),
        ) { ok ->
            sending = false
            toast(if (ok) "Proposed ${CarFormat.category(category)} near here" else "Couldn't propose. Check your phone.")
            if (lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) screenManager.pop()
        }
        // A queued action never reaches the callback above, so this is the only pop for it.
        if (outcome == CarActions.Outcome.QUEUED) {
            sending = false
            toast("Open Drivalry on your phone to finish that")
            screenManager.pop()
        }
    }

    private fun toast(text: String) {
        try {
            CarToast.makeText(carContext, text, CarToast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            // Host gone.
        }
    }
}
