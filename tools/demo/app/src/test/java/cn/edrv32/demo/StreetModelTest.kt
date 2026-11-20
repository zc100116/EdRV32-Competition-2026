// StreetModelTest.kt — L11; repeatable routes, changing counts and 70% visibility.
package cn.edrv32.demo

import org.junit.Assert.*
import org.junit.Test

class StreetModelTest {
    @Test fun loopRoutesAndChangingCounts() {
        val frames = (0..39).map { StreetModel.frame(it.toDouble()) }
        assertEquals(StreetModel.frame(7.0), StreetModel.frame(47.0))
        assertEquals(setOf(0, 1, 2, 3, 5, 7, 9, 11, 16, 58),
            frames.flatMap { it.actors }.map { it.category }.toSet())
        for (category in listOf(0, 1, 2, 3, 5, 7, 16)) {
            val counts = frames.map { f -> f.actors.count {
                it.category == category && it.exposed >= .7f } }
            assertTrue("class $category changes count", counts.toSet().size > 1)
        }
        assertTrue(frames.flatMap { it.actors }.any { it.facing < 0 })
        assertTrue(frames.flatMap { it.actors }.any { it.exposed < .7f })
        assertNotEquals(frames[3].actors.first().x, frames[4].actors.first().x)
    }
}
