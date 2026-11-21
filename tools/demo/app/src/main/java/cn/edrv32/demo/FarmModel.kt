// FarmModel.kt — R5-11/12; deterministic pasture state and operation timing. App clock.
package cn.edrv32.demo

import kotlin.math.sin

data class FarmAnimal(
    val id: Int, val kind: String, val category: Int,
    val x: Float, val y: Float, val height: Float, val aspect: Float,
    val pose: Int = 3, val facing: Float = 1f,
) {
    val width get() = height * aspect
    val visible get() = x + width / 2 > 0 && x - width / 2 < 2000 &&
        y + height / 2 > 0 && y - height / 2 < 1125
}
data class FarmPoint(val x: Float, val y: Float)
data class FarmFrame(val seconds: Double, val animals: List<FarmAnimal>, val person: FarmAnimal?)

object FarmModel {
    val initial = listOf(
        FarmAnimal(0, "cow", 19, 360f, 390f, 330f, 1.572917f),
        FarmAnimal(1, "cow2", 19, 400f, 790f, 380f, 1.555901f),
        FarmAnimal(2, "horse", 17, 950f, 260f, 300f, 1.121723f),
        FarmAnimal(3, "sheep", 18, 1410f, 300f, 230f, 1.383529f),
        FarmAnimal(4, "sheep", 18, 1130f, 610f, 250f, 1.383529f),
        FarmAnimal(5, "sheep", 18, 1000f, 880f, 250f, 1.383529f),
        FarmAnimal(6, "chicken", 14, 1670f, 570f, 290f, 1.240741f),
        FarmAnimal(7, "chicken", 14, 1400f, 890f, 295f, 1.240741f),
        FarmAnimal(8, "chicken", 14, 1800f, 885f, 300f, 1.240741f),
    )
    private fun interpolate(t: Double, from: Float, to: Float): Float =
        from + (to - from) * t.coerceIn(0.0, 1.0).toFloat()

    fun frame(seconds: Double, demo: Boolean = false,
        intrusion: Double? = null, dragged: Map<Int, FarmPoint> = emptyMap()): FarmFrame {
        val animals = initial.map { animal ->
            val phase = (seconds + animal.id * 1.3) % 9
            val pose = when {
                phase < 3 -> (seconds * 3).toInt() % 2
                phase < 6 -> 2
                else -> 3
            }
            var a = animal.copy(
                x = animal.x + (sin(seconds * .38 + animal.id) *
                    if (animal.category == 14) 24 else 18).toFloat(),
                y = animal.y + (sin(seconds * .24 + animal.id) *
                    if (animal.category == 14) 8 else 6).toFloat(),
                pose = if (animal.category == 14) 2 else pose,
            )
            if (demo && animal.id == 3) {
                val x = when {
                    seconds < 5 -> a.x
                    seconds < 7 -> interpolate((seconds - 5) / 2, animal.x, 2300f)
                    seconds < 11 -> 2300f
                    seconds < 13 -> interpolate((seconds - 11) / 2, 2300f, animal.x)
                    else -> a.x
                }
                a = a.copy(x = x, pose = if (seconds in 5.0..13.0) {
                    (seconds * 4).toInt() % 2
                } else pose, facing = if (seconds in 11.0..13.0) -1f else 1f)
            }
            dragged[animal.id]?.let { a = a.copy(x = it.x, y = it.y, pose = 3) }
            a
        }
        val personTime = if (demo) seconds - 13 else intrusion?.let { seconds - it }
        val person = personTime?.takeIf { it >= 0 && it < 11 }?.let { t ->
            val x = when {
                t < 1 -> interpolate(t, -160f, 150f)
                t < 3 -> interpolate((t - 1) / 2, 150f, 770f)
                t < 8 -> 770f
                else -> interpolate((t - 8) / 3, 770f, 2300f)
            }
            FarmAnimal(9, "person", 0, x, 850f, 420f, .551724f,
                if (t < 1) 2 else if (t < 3 || t >= 8) (seconds * 4).toInt() % 2 else 3)
        }
        return FarmFrame(seconds, animals, person)
    }
}
