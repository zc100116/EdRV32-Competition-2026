// SiteModelTest.kt — R5-14/15; counts, script, tapping and drag replay. Host clock.
package cn.edrv32.demo

import org.junit.Assert.*
import org.junit.Test

class SiteModelTest {
    @Test fun resetAndScript() {
        val reset = SiteModel.frame(0.0)
        assertEquals(6, reset.workers.size)
        assertEquals(4, reset.workers.count { it.wearing })
        for (second in 0..4) {
            assertEquals(6, SiteModel.frame(second.toDouble(), true).workers.count { it.wearing })
            assertTrue(SiteModel.frame(second.toDouble(), true).workers.all { it.walking })
        }
        assertEquals(1, SiteModel.frame(8.0, true).workers.count { !it.wearing })
        assertEquals(0, SiteModel.frame(12.0, true).workers.count { !it.wearing })
        assertEquals(7, SiteModel.frame(18.0, true).workers.size)
        assertEquals(1, SiteModel.frame(18.0, true).workers.count { !it.wearing })
        assertEquals(6, SiteModel.frame(24.0, true).workers.size)
    }

    @Test fun hatActionAndDrag() {
        val actions = mapOf(0 to SiteHatAction(3.0, false), 4 to SiteHatAction(3.0, true))
        val start = SiteModel.frame(3.0, hats = actions)
        assertTrue(start.workers[0].wearing)
        assertFalse(start.workers[4].wearing)
        val end = SiteModel.frame(5.0, hats = actions, dragged = mapOf(2 to FarmPoint(700f, 700f)))
        assertFalse(end.workers[0].wearing)
        assertTrue(end.workers[4].wearing)
        assertEquals(700f, end.workers[2].x)
        assertEquals(2, SiteModel.hit(end, 700f, 700f)!!.id)
        assertNull(SiteModel.hit(end, 1950f, 50f))
        assertEquals(end, SiteModel.frame(5.0, hats = actions,
            dragged = mapOf(2 to FarmPoint(700f, 700f))))
    }
}
