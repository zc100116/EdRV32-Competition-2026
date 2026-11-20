// StreetModel.kt — live demo L11; deterministic 40-second street loop. App clock.
package cn.edrv32.demo

import kotlin.math.max
import kotlin.math.min

data class StreetActor(
    val id: Int, val kind: String, val category: Int, val x: Float, val y: Float,
    val width: Float, val height: Float, val facing: Float, val pose: Int,
) {
    val exposed: Float get() = max(0f, min(2000f, x + width / 2) - max(0f, x - width / 2)) /
        width * max(0f, min(1125f, y + height / 2) - max(0f, y - height / 2)) / height
}
data class StreetFrame(val seconds: Double, val actors: List<StreetActor>) {
    val drawingOrder get() = actors.sortedBy {
        it.y + it.height / 2
    }
}

object StreetModel {
    private data class Route(val kind: String, val category: Int, val start: Double,
        val duration: Double, val y: Float, val width: Float, val height: Float,
        val facing: Float = 1f, val stationaryX: Float? = null)
    private val routes = listOf(
        Route("car", 2, 0.0, 18.0, 385f, 600f, 240f),
        Route("car", 2, 8.0, 20.0, 385f, 600f, 240f),
        Route("car", 2, 30.0, 18.0, 385f, 600f, 240f),
        Route("bus", 5, 20.0, 20.0, 385f, 800f, 310f),
        Route("truck", 7, 0.0, 20.0, 660f, 650f, 300f, -1f),
        Route("bicycle", 1, 0.0, 20.0, 190f, 380f, 380f),
        Route("bicycle", 1, 22.0, 18.0, 190f, 380f, 380f, -1f),
        Route("person", 0, 0.0, 38.0, 970f, 172f, 260f),
        Route("person", 0, 24.0, 39.0, 970f, 172f, 260f),
        Route("dog", 16, 8.0, 40.0, 1000f, 290f, 150f),
        Route("light", 9, 0.0, 40.0, 165f, 160f, 330f, stationaryX = 1880f),
        Route("stop", 11, 0.0, 40.0, 150f, 190f, 300f, stationaryX = 110f),
    )
    fun frame(seconds: Double): StreetFrame {
        val time = seconds % 40.0
        val actors = routes.mapIndexedNotNull { id, route ->
            val elapsed = (time - route.start + 40.0) % 40.0
            if (elapsed >= route.duration) null else {
                // One-second edges leave a clear margin for the full visible traversal.
                val entry = route.width + 100f
                val span = 1800f - route.width
                val distance = when {
                    elapsed < 1 -> elapsed.toFloat() * entry
                    elapsed > route.duration - 1 -> entry + span +
                        (elapsed - route.duration + 1).toFloat() * entry
                    else -> entry + ((elapsed - 1) / (route.duration - 2)).toFloat() * span
                }
                val x = route.stationaryX ?: if (route.facing > 0) -route.width / 2 + distance
                    else 2000 + route.width / 2 - distance
                StreetActor(id, route.kind, route.category, x, route.y, route.width,
                    route.height, route.facing,
                    if (route.stationaryX != null) 0 else (seconds * 3).toInt() % 2)
            }
        }
        return StreetFrame(time, actors)
    }
}
