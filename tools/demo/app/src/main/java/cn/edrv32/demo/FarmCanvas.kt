// FarmCanvas.kt — R5-12; shared native runtime/JVM surveillance compositing. App clock.
package cn.edrv32.demo

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import kotlin.math.abs
import kotlin.math.sin

@Composable
fun FarmCanvas(repository: MediaRepository, frame: FarmFrame, modifier: Modifier = Modifier,
    onTap: () -> Unit = {}, onDrag: (Int, FarmPoint) -> Unit = { _, _ -> }) {
    val background = remember { repository.image("farm/background.jpg") }
    val tree = remember { repository.image("farm/tree.webp") }
    val sprites = remember {
        mutableMapOf<Pair<String, Int>, androidx.compose.ui.graphics.ImageBitmap>()
    }
    val photoPaint = remember { Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG) }
    val current = rememberUpdatedState(frame)
    val drag = rememberUpdatedState(onDrag)
    val tap = rememberUpdatedState(onTap)
    Canvas(modifier.pointerInput(Unit) {
        detectTapGestures { tap.value() }
    }.pointerInput(Unit) {
        var animal: FarmAnimal? = null
        var position = FarmPoint(0f, 0f)
        detectDragGestures(onDragStart = { point ->
            val x = point.x / size.width * 2000
            val y = point.y / size.height * 1125
            animal = current.value.animals.asReversed().firstOrNull { a ->
                // An animal waiting outside can be retrieved from its corresponding edge.
                val hitX = a.x.coerceIn(0f, 2000f)
                val hitY = a.y.coerceIn(0f, 1125f)
                abs(x - hitX) < a.width / 2 && abs(y - hitY) < a.height / 2
            }
            animal?.let { position = FarmPoint(it.x, it.y) }
        }, onDrag = { change, amount ->
            animal?.let { a ->
                change.consume()
                position = FarmPoint(position.x + amount.x / size.width * 2000,
                    position.y + amount.y / size.height * 1125)
                drag.value(a.id, position)
            }
        }, onDragEnd = {
            animal?.let { a ->
                val x = when {
                    position.x - a.width / 2 < 0 -> -a.width / 2 - 1
                    position.x + a.width / 2 > 2000 -> 2001 + a.width / 2
                    else -> position.x
                }
                val y = when {
                    position.y - a.height / 2 < 0 -> -a.height / 2 - 1
                    position.y + a.height / 2 > 1125 -> 1126 + a.height / 2
                    else -> position.y
                }
                drag.value(a.id, FarmPoint(x, y))
            }
            animal = null
        }, onDragCancel = { animal = null })
    }) {
        scale(size.width / 2000, size.height / 1125, pivot = Offset.Zero) {
            drawImage(background, dstSize = IntSize(2000, 1125))
            drawImage(tree, dstOffset = IntOffset(1700 + (sin(frame.seconds) * 2).toInt(), 0),
                dstSize = IntSize(300, 160))
            // Low-contrast grass blades sway independently of the stationary fence.
            repeat(160) { i ->
                val x = 100f + (i * 173 % 1800)
                val y = 170f + (i * 113 % 870)
                val sway = sin(frame.seconds * 1.2 + i).toFloat() * 3
                drawLine(Color(0x5593AF68), Offset(x, y), Offset(x + sway, y - 8), 1.5f)
            }
            val cloudX = ((frame.seconds * 27) % 3200 - 700).toFloat()
            drawOval(Brush.radialGradient(listOf(Color.Black.copy(alpha = .09f),
                Color.Transparent), center = Offset(cloudX, 430f), radius = 700f),
                topLeft = Offset(cloudX - 700, 60f), size = Size(1400f, 760f))
            (frame.animals + listOfNotNull(frame.person)).sortedBy { it.y + it.height / 2 }
                .forEach { a ->
                    val w = a.width
                    val h = a.height
                    drawOval(Brush.radialGradient(listOf(Color.Black.copy(alpha = .3f),
                        Color.Transparent), center = Offset(a.x, a.y + h * .44f), radius = w * .5f),
                        topLeft = Offset(a.x - w * .45f, a.y + h * .4f),
                        size = Size(w * .9f, h * .12f))
                    withTransform({
                        if (a.facing < 0) scale(-1f, 1f, pivot = Offset(a.x, a.y))
                    }) {
                        val pose = if (a.kind == "person") a.pose else
                            if (a.kind == "sheep") 2 else 3
                        val sprite = sprites.getOrPut(a.kind to pose) {
                            repository.image("farm/${a.kind}-$pose.webp")
                        }
                        if (a.kind == "person") {
                            drawImage(sprite,
                                dstOffset = IntOffset((a.x - w / 2).toInt(),
                                    (a.y - h / 2).toInt()),
                                dstSize = IntSize(w.toInt(), h.toInt()),
                                filterQuality = FilterQuality.Medium)
                        } else {
                            // A continuous photo mesh keeps the character intact: real legs
                            // stride, tails sway and heads nod without cut-and-paste seams.
                            val columns = 24
                            val rows = 24
                            val vertices = FloatArray((columns + 1) * (rows + 1) * 2)
                            for (row in 0..rows) for (column in 0..columns) {
                                val nx = column.toFloat() / columns
                                val ny = row.toFloat() / rows
                                var x = (nx - .5f) * w
                                var y = (ny - .5f) * h
                                val foot = ((ny - .7f) / .3f).coerceIn(0f, 1f)
                                if (a.pose == 0 || a.pose == 1) {
                                    val step = sin(frame.seconds * 7 + nx * 10 + a.id)
                                    x += (step * w * .018 * foot).toFloat()
                                    y -= (kotlin.math.max(0.0, step) * h * .012 * foot).toFloat()
                                }
                                val tail = (1 - nx / .14f).coerceIn(0f, 1f) *
                                    (1 - kotlin.math.abs(ny - .5f) / .3f).coerceIn(0f, 1f)
                                x += (sin(frame.seconds * 1.8 + a.id) * w * .02 * tail).toFloat()
                                val head = ((nx - .63f) / .37f).coerceIn(0f, 1f) *
                                    if (a.kind == "sheep") ((ny - .3f) / .7f).coerceIn(0f, 1f)
                                    else ((.55f - ny) / .55f).coerceIn(0f, 1f)
                                y += (sin(frame.seconds * 1.1 + a.id) * h * .009 * head).toFloat()
                                val vertex = (row * (columns + 1) + column) * 2
                                vertices[vertex] = a.x + x
                                vertices[vertex + 1] = a.y + y
                            }
                            drawContext.canvas.nativeCanvas.drawBitmapMesh(
                                sprite.asAndroidBitmap(), columns, rows, vertices, 0,
                                null, 0, photoPaint)
                        }
                    }
                }
            drawRect(Brush.radialGradient(listOf(Color.Transparent, Color.Transparent,
                Color.Black.copy(alpha = .26f)), center = Offset(1000f, 560f), radius = 1200f),
                size = Size(2000f, 1125f))
            repeat(260) { i ->
                val step = (frame.seconds * 12).toInt()
                drawCircle(Color.White.copy(alpha = .07f), .7f,
                    Offset(((i * 127 + step * 13) % 2000).toFloat(),
                        ((i * 79 + step * 7) % 1125).toFloat()))
            }
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                textSize = 27f
                typeface = android.graphics.Typeface.MONOSPACE
                setShadowLayer(3f, 1f, 1f, android.graphics.Color.BLACK)
            }
            val seconds = 14 * 3600 + 30 * 60 + frame.seconds.toInt()
            val clock = "2026-11-17 %02d:%02d:%02d".format(
                seconds / 3600 % 24, seconds / 60 % 60, seconds % 60)
            drawContext.canvas.nativeCanvas.drawText(clock, 34f, 48f, paint)
            paint.textAlign = Paint.Align.RIGHT
            drawContext.canvas.nativeCanvas.drawText("CAM-02 东牧场", 1890f, 48f, paint)
            drawCircle(Color(0xFFE56259), 8f, Offset(1930f, 37f))
            paint.textSize = 20f
            drawContext.canvas.nativeCanvas.drawText("REC", 1980f, 44f, paint)
        }
    }
}
