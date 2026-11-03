package app.drivalry.car

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CarFormatTest {
    @Test
    fun speeds() {
        assertEquals("31 mph", CarFormat.speed(13.86, mph = true))
        assertEquals("50 km/h", CarFormat.speed(13.9, mph = false))
        assertEquals(7, CarFormat.speedNumber(3.15, mph = true))
        assertEquals(11, CarFormat.speedNumber(3.15, mph = false))
    }

    @Test
    fun distances() {
        assertEquals("0.4 mi", CarFormat.distance(650.0, mph = true))
        assertEquals("12 mi", CarFormat.distance(19_300.0, mph = true))
        assertEquals("200 ft", CarFormat.distance(61.0, mph = true))
        assertEquals("350 m", CarFormat.distance(348.0, mph = false))
        assertEquals("3.2 km", CarFormat.distance(3200.0, mph = false))
        assertEquals("19 km", CarFormat.distance(19_300.0, mph = false))
    }

    @Test
    fun etasAndElapsed() {
        assertEquals("< 1 min", CarFormat.eta(20))
        assertEquals("12 min", CarFormat.eta(720))
        assertEquals("1 h 05 min", CarFormat.eta(3900))
        assertEquals("2 h", CarFormat.eta(7200))
        assertEquals("45 s", CarFormat.elapsed(45))
        assertEquals("9 min", CarFormat.elapsed(540))
        assertEquals("1h 12m", CarFormat.elapsed(4320))
    }

    @Test
    fun ages() {
        assertNull(CarFormat.age(null, 10_000))
        assertEquals("just now", CarFormat.age(5_000, 10_000))
        assertEquals("40 s ago", CarFormat.age(0, 40_000))
        assertEquals("3 min ago", CarFormat.age(0, 200_000))
    }

    @Test
    fun statusLinesMatchDart() {
        val base = CarSnapshot.Drive.IDLE
        assertEquals("Not recording", CarFormat.status(base, mph = true))
        assertEquals("Looks like a drive", CarFormat.status(base.copy(status = "tentative"), mph = true))
        assertEquals("Passenger · not scored", CarFormat.status(base.copy(status = "passenger"), mph = true))
        assertEquals("7 over", CarFormat.status(base.copy(status = "over", overMps = 3.15), mph = true))
        assertEquals("1 min over so far", CarFormat.status(base.copy(status = "cleanish", speedingS = 95), mph = true))
        assertEquals("No limit data here", CarFormat.status(base.copy(status = "noLimit"), mph = true))
        assertEquals("Clean so far", CarFormat.status(base.copy(status = "clean"), mph = true))
        assertEquals("Gas", CarFormat.category("gas"))
        assertEquals("Photo stop", CarFormat.category("photo"))
    }
}
