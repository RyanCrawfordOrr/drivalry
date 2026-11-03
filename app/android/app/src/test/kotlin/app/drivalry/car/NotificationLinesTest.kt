package app.drivalry.car

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationLinesTest {
    private fun line(tripId: String?) =
        CarState.NotificationLine(title = "Drivalry", text = "Recording · Limit 35", subText = null, passengerAction = true, tripId = tripId)

    @Test
    fun aPersistedLineNeedsATripId() {
        assertTrue(NotificationLines.restorable("t1"))
        assertFalse(NotificationLines.restorable(null))
    }

    @Test
    fun onlyTheCurrentTripsLineShows() {
        assertEquals(line("t1"), NotificationLines.forTrip(line("t1"), "t1"))
        assertNull(NotificationLines.forTrip(line("t1"), "t2"))
        assertNull("a line without a trip never describes the next one", NotificationLines.forTrip(line(null), "t2"))
        assertNull(NotificationLines.forTrip(line("t1"), null))
        assertNull(NotificationLines.forTrip(null, "t1"))
    }
}
