// StreetCanvas.kt — live demo L11; shared runtime/JVM street rendering. App clock.
package cn.edrv32.demo

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize

@Composable
fun StreetCanvas(repository: MediaRepository, frame: StreetFrame,
    modifier: Modifier = Modifier) {
    val sprites = remember(repository) { mutableMapOf<Pair<String, Int>, ImageBitmap>() }
    Canvas(modifier) {
        scale(size.width / 2000, size.height / 1125, pivot = Offset.Zero) {
            drawRect(Color(0xFFCBC8BE), size = androidx.compose.ui.geometry.Size(2000f, 1125f))
            drawRect(Color(0xFF55585A), Offset(0f, 270f),
                androidx.compose.ui.geometry.Size(2000f, 570f))
            drawLine(Color(0xFFF4ECD8), Offset(0f, 545f), Offset(2000f, 545f), 6f)
            drawLine(Color(0xFFF4ECD8), Offset(0f, 565f), Offset(2000f, 565f), 6f)
            listOf(267f, 843f).forEach { y ->
                drawLine(Color(0xFFE7E4DA), Offset(0f, y), Offset(2000f, y), 12f)
            }
            repeat(20) { i ->
                drawLine(Color(0xFFB7B4AA), Offset(i * 110f, 0f),
                    Offset(i * 110f, 255f), 2f)
                drawLine(Color(0xFFB7B4AA), Offset(i * 110f, 855f),
                    Offset(i * 110f, 1125f), 2f)
            }
            frame.drawingOrder.forEach { actor ->
                val sprite = sprites.getOrPut(actor.kind to actor.pose) {
                    repository.image("street/${actor.kind}-${actor.pose}.webp")
                }
                withTransform({
                    if (actor.facing < 0) scale(-1f, 1f, pivot = Offset(actor.x, actor.y))
                }) {
                    drawImage(sprite,
                        dstOffset = IntOffset((actor.x - actor.width / 2).toInt(),
                            (actor.y - actor.height / 2).toInt()),
                        dstSize = IntSize(actor.width.toInt(), actor.height.toInt()),
                        filterQuality = FilterQuality.Medium)
                }
            }
        }
    }
}
