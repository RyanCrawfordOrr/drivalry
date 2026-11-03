package app.drivalry.car

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors `app/test/car/car_snapshot_test.dart`: the two sides must agree on the JSON. */
class CarSnapshotTest {
    private val full = """
        {"v":1,"at":1762200000000,"me":"me","units":"kmh",
         "drive":{"phase":"active","tripId":"t1","startedAt":1762199400000,"elapsedS":600,
                  "distanceM":8046.7,"speedMps":18.8,"limitMps":15.65,"posted":35,"limitUnit":"mph",
                  "road":"Elm St","overMps":3.15,"speedingS":12,"passenger":false,"status":"over"},
         "convoy":{"id":"c1","name":"Lake run","status":"active","leaderId":"leader",
                   "destination":{"name":"Lake","lat":37.2,"lon":-122.0},"regroup":null,
                   "members":[
                     {"id":"leader","name":"LEADER","initials":"L","isMe":false,"isLeader":true,
                      "lat":37.05,"lon":-122.0,"speedMps":null,"etaS":900,"distanceM":5559.75,
                      "lost":null,"talking":false,"atMs":1762199998000},
                     {"id":"me","name":"ME","initials":"M","isMe":true,"isLeader":false,
                      "lat":null,"lon":null,"speedMps":null,"etaS":null,"distanceM":null,
                      "lost":"behind","talking":true,"atMs":null}],
                   "stops":[{"id":"s1","name":"Diner","category":"food","status":"proposed",
                             "lat":37.05,"lon":-122.0,"up":1,"down":0,"myVote":1,"distanceM":5559.75}]},
         "talk":{"available":true,"on":true,"holding":true,"talking":["NEAR"],"peers":1,"reason":null},
         "crash":{"countingDown":false,"secondsLeft":0,"unresolved":false}}
    """.trimIndent()

    @Test
    fun parsesEveryField() {
        val s = CarSnapshot.parse(full)!!
        assertEquals(1, s.version)
        assertEquals(1762200000000L, s.at)
        assertEquals("me", s.me)
        assertFalse(s.mph)
        assertEquals("active", s.drive.phase)
        assertTrue(s.drive.recording)
        assertEquals(35, s.drive.posted)
        assertEquals("Elm St", s.drive.road)
        assertEquals(3.15, s.drive.overMps!!, 1e-9)
        assertEquals(12, s.drive.speedingS)
        assertEquals("over", s.drive.status)

        val c = s.convoy!!
        assertTrue(c.active)
        assertEquals("Lake", c.destination!!.name)
        assertNull(c.regroup)
        assertEquals(2, c.members.size)
        val leader = c.members[0]
        assertTrue(leader.isLeader)
        assertTrue(leader.hasPosition)
        assertEquals(900, leader.etaS)
        assertNull(leader.speedMps)
        assertNull(leader.lost)
        val me = c.members[1]
        assertTrue(me.isMe)
        assertFalse(me.hasPosition)
        assertEquals("behind", me.lost)
        assertTrue(me.talking)
        assertNull(me.atMs)
        val stop = c.stops.single()
        assertEquals("Diner", stop.name)
        assertEquals(1, stop.myVote)
        assertFalse(stop.accepted)

        assertTrue(s.talk.available)
        assertTrue(s.talk.holding)
        assertEquals(listOf("NEAR"), s.talk.talking)
        assertNull(s.talk.reason)
        assertFalse(s.crash.countingDown)
    }

    @Test
    fun jsonNullsStayNull() {
        val s = CarSnapshot.parse("""{"v":1,"me":null,"drive":{"phase":"idle","tripId":null,"posted":null,"road":null}}""")!!
        assertNull(s.me)
        assertNull(s.drive.tripId)
        assertNull(s.drive.posted)
        assertNull(s.drive.road)
        assertTrue(s.drive.idle)
    }

    @Test
    fun minimalAndMalformedPayloads() {
        val minimal = CarSnapshot.parse("""{"v":1}""")!!
        assertEquals("idle", minimal.drive.phase)
        assertNull(minimal.convoy)
        assertFalse(minimal.talk.available)
        assertEquals(0L, minimal.at)
        assertNull(CarSnapshot.parse("not json"))
        assertNull(CarSnapshot.parse(""))
        assertNull(CarSnapshot.parse(null))
        assertNotNull(CarSnapshot.parse("""{"drive":"oops","convoy":[]}"""))
    }

    @Test
    fun staleness() {
        val s = CarSnapshot.parse("""{"v":1,"at":1000000}""")!!
        assertFalse(s.isStale(nowMs = 1000000 + 30_000))
        assertTrue(s.isStale(nowMs = 1000000 + 61_000))
        assertTrue(CarSnapshot.EMPTY.isStale(nowMs = 5))
    }
}
