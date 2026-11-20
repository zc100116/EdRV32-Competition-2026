// FarmModelTest.kt — R5-12; script timing, deterministic replay and held outside animal.
package cn.edrv32.demo

import org.junit.Assert.*
import org.junit.Test

class FarmModelTest {
    @Test fun timedEventsAndReplay() {
        assertEquals(FarmModel.frame(18.0, true), FarmModel.frame(18.0, true))
        assertTrue(FarmModel.frame(4.0, true).animals.all { it.visible })
        assertFalse(FarmModel.frame(9.0, true).animals[3].visible)
        assertTrue(FarmModel.frame(13.0, true).animals[3].visible)
        assertTrue(FarmModel.frame(18.0, true).person!!.visible)
        assertNull(FarmModel.frame(24.0, true).person)
    }
    @Test fun everyAnimalMovesIncludingChickens() {
        val first = FarmModel.frame(0.0, true)
        val later = FarmModel.frame(3.0, true)
        first.animals.zip(later.animals).forEach { (a, b) ->
            assertTrue("animal ${a.id} must roam", a.x != b.x && a.y != b.y)
        }
    }
    @Test fun draggedAnimalWaitsUntilMovedBackOrReset() {
        val outside = mapOf(3 to FarmPoint(2300f, 300f))
        assertFalse(FarmModel.frame(10.0, dragged = outside).animals[3].visible)
        assertFalse(FarmModel.frame(1000.0, dragged = outside).animals[3].visible)
        assertTrue(FarmModel.frame(1000.0,
            dragged = mapOf(3 to FarmPoint(1400f, 300f))).animals[3].visible)
        assertTrue(FarmModel.frame(0.0).animals.all { it.visible })
    }
}
