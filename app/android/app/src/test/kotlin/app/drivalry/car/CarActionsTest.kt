package app.drivalry.car

import org.junit.Assert.assertEquals
import org.junit.Test

/** The routing rule behind `CarActions.dispatch`; the callback contract is in its KDoc. */
class CarActionsTest {
    @Test
    fun everythingGoesToDartWhenAttached() {
        for (name in listOf(CarActions.END_TRIP, CarActions.MARK_PASSENGER, CarActions.PROPOSE_STOP, CarActions.TALK_START)) {
            assertEquals(CarActions.Outcome.SENT, CarActions.route(CarAction(name), dartAttached = true))
        }
    }

    @Test
    fun endingTheTripIsNativeWithoutDart() {
        assertEquals(CarActions.Outcome.NATIVE, CarActions.route(CarAction(CarActions.END_TRIP), dartAttached = false))
    }

    @Test
    fun otherActionsQueueWithoutDart() {
        for (name in listOf(CarActions.MARK_PASSENGER, CarActions.PROPOSE_STOP, CarActions.VOTE_STOP, CarActions.CRASH_OK)) {
            assertEquals(CarActions.Outcome.QUEUED, CarActions.route(CarAction(name), dartAttached = false))
        }
    }
}
