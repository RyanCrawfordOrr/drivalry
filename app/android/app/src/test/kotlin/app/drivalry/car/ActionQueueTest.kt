package app.drivalry.car

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActionQueueTest {
    @Test
    fun roundTripsActionsWithArgs() {
        val list = listOf(
            CarAction("markPassenger", mapOf("tripId" to "t1")),
            CarAction("voteStop", mapOf("convoyId" to "c1", "stopId" to "s1", "vote" to 1)),
            CarAction("endTrip"),
        )
        val back = ActionQueue.decode(ActionQueue.encode(list))
        assertEquals(3, back.size)
        assertEquals("markPassenger", back[0].name)
        assertEquals("t1", back[0].args["tripId"])
        assertEquals(1, back[1].args["vote"])
        assertEquals("s1", back[1].args["stopId"])
        assertTrue(back[2].args.isEmpty())
    }

    @Test
    fun wireShapeMatchesDart() {
        val w = CarAction("voteStop", mapOf("stopId" to "s1", "vote" to 1)).toWire()
        assertEquals("voteStop", w["name"])
        assertEquals(mapOf("stopId" to "s1", "vote" to 1), w["args"])
    }

    @Test
    fun appendCollapsesRepeatsAndCaps() {
        var q = emptyList<CarAction>()
        q = ActionQueue.append(q, CarAction("markPassenger", mapOf("tripId" to "t1")))
        q = ActionQueue.append(q, CarAction("endTrip"))
        q = ActionQueue.append(q, CarAction("markPassenger", mapOf("tripId" to "t1")))
        assertEquals(listOf("endTrip", "markPassenger"), q.map { it.name })

        for (i in 0 until ActionQueue.MAX + 10) {
            q = ActionQueue.append(q, CarAction("voteStop", mapOf("stopId" to "s$i", "vote" to 1)))
        }
        assertEquals(ActionQueue.MAX, q.size)
        assertEquals("s${ActionQueue.MAX + 9}", q.last().args["stopId"])
    }

    @Test
    fun decodeToleratesJunk() {
        assertTrue(ActionQueue.decode(null).isEmpty())
        assertTrue(ActionQueue.decode("").isEmpty())
        assertTrue(ActionQueue.decode("nope").isEmpty())
        val mixed = ActionQueue.decode("""[{"name":"endTrip"},{"args":{}},"x",{"name":"","args":{}}]""")
        assertEquals(1, mixed.size)
        assertNull(CarAction.fromJson(org.json.JSONObject("""{"args":{"a":1}}""")))
    }
}
