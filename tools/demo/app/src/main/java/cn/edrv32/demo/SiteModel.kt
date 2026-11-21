// SiteModel.kt — R5-14/15; deterministic workers, hat actions and visitor script. App clock.
package cn.edrv32.demo

import kotlin.math.sin

data class SiteHatAction(val seconds: Double, val wearing: Boolean)
data class SiteWorker(
    val id: Int, val sprite: Int, val x: Float, val y: Float,
    val height: Float, val wearing: Boolean, val motion: Float = 0f,
    val walking: Boolean = false, val working: Boolean = false,
    val capProgress: Float? = null, val wiping: Boolean = false,
) {
    val width get() = height * .65f
}
data class SiteFrame(val seconds: Double, val workers: List<SiteWorker>)

object SiteModel {
    val initial = listOf(
        SiteWorker(0, 0, 360f, 385f, 490f, true),
        SiteWorker(1, 1, 940f, 360f, 490f, true),
        SiteWorker(2, 2, 1530f, 365f, 490f, true),
        SiteWorker(3, 3, 520f, 865f, 490f, true),
        SiteWorker(4, 4, 1100f, 865f, 490f, false),
        SiteWorker(5, 5, 1680f, 865f, 490f, false),
    )
    private fun blend(t: Double, from: Float, to: Float) =
        from + (to - from) * t.coerceIn(0.0, 1.0).toFloat()

    fun frame(seconds: Double, demo: Boolean = false,
        hats: Map<Int, SiteHatAction> = emptyMap(),
        dragged: Map<Int, FarmPoint> = emptyMap()): SiteFrame {
        val workers = initial.map { original ->
            var worker = original.copy(
                x = original.x + (sin(seconds * .32 + original.id) * 65).toFloat(),
                y = original.y + (sin(seconds * .28 + original.id) * 16).toFloat(),
                wearing = if (demo) !(original.id == 0 && seconds >= 5.5 && seconds < 10.5)
                    else original.wearing,
                walking = true, working = original.id in listOf(2, 3),
            )
            var action: SiteHatAction? = if (demo && original.id == 0) when {
                seconds >= 10 -> SiteHatAction(10.0, true)
                seconds >= 5 -> SiteHatAction(5.0, false)
                else -> null
            } else null
            hats[original.id]?.let { action = it }
            action?.let { a ->
                val t = seconds - a.seconds
                val progress = (t / 1.4).coerceIn(0.0, 1.0).toFloat()
                // Hand reaches the crown, carries the cap to the hip, and returns.
                worker = worker.copy(wearing = if (t < .5) !a.wearing else a.wearing,
                    motion = if (progress < .35f) progress / .35f
                        else (1f - progress) / .65f,
                    capProgress = if (t >= .5 && !a.wearing)
                        ((t - .5) / .9).coerceIn(0.0, 1.0).toFloat() else null,
                    wiping = original.id == 0 && !a.wearing && t >= 1.4)
            }
            dragged[original.id]?.let { worker = worker.copy(x = it.x, y = it.y,
                walking = false, working = false) }
            worker
        }.toMutableList()
        if (demo && seconds >= 14 && seconds < 23) {
            val x = when {
                seconds < 16 -> blend((seconds - 14) / 2, -220f, 110f)
                seconds < 21 -> 110f
                else -> blend((seconds - 21) / 2, 110f, -220f)
            }
            workers += SiteWorker(6, 4, x, 850f, 490f, false,
                walking = seconds < 16 || seconds >= 21)
        }
        return SiteFrame(seconds, workers)
    }

    fun hit(frame: SiteFrame, x: Float, y: Float): SiteWorker? =
        frame.workers.asReversed().firstOrNull {
            kotlin.math.abs(x - it.x) < it.width / 2 && kotlin.math.abs(y - it.y) < it.height / 2
        }
}
