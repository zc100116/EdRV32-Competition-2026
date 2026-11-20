// SiteCanvas.kt — R5-14/15; shared photographic construction CCTV renderer. App clock.
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
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sin

class SiteArt(repository: MediaRepository) {
    val background = repository.image("site/background.jpg")
    val workers = (0..5).associateWith { id -> listOf(repository.image("site/$id-head.webp"),
        repository.image("site/$id-helmet.webp")) }
    val walking = (0..5).associateWith { id -> (0..1).map { pose ->
        listOf(repository.image("site/$id-head-walk-$pose.webp"),
            repository.image("site/$id-helmet-walk-$pose.webp")) } }
    val walkingWipe = (0..1).map { repository.image("site/wipe-walk-$it.webp") }
    val visitor = repository.image("site/visitor.webp")
    val wipe = repository.image("site/wipe.webp")
    val caps = (0..5).associateWith { repository.image("site/$it-cap.webp") }
}

@Composable
fun SiteCanvas(repository: MediaRepository, frame: SiteFrame, modifier: Modifier = Modifier,
    onTap: () -> Unit = {}, onHat: (Int) -> Unit = {},
    onDrag: (Int, FarmPoint) -> Unit = { _, _ -> }) {
    val art = remember(repository) { repository.siteArt }
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG) }
    val current = rememberUpdatedState(frame)
    val tap = rememberUpdatedState(onTap)
    val hat = rememberUpdatedState(onHat)
    val drag = rememberUpdatedState(onDrag)
    Canvas(modifier.pointerInput(Unit) {
        detectTapGestures { p ->
            val worker = SiteModel.hit(current.value, p.x / size.width * 2000,
                p.y / size.height * 1125)
            if (worker != null && worker.id < 6) hat.value(worker.id) else tap.value()
        }
    }.pointerInput(Unit) {
        var worker: SiteWorker? = null
        var position = FarmPoint(0f, 0f)
        detectDragGestures(onDragStart = { p ->
            worker = SiteModel.hit(current.value, p.x / size.width * 2000,
                p.y / size.height * 1125)?.takeIf { it.id < 6 }
            worker?.let { position = FarmPoint(it.x, it.y) }
        }, onDrag = { change, amount ->
            worker?.let {
                change.consume()
                position = FarmPoint(position.x + amount.x / size.width * 2000,
                    position.y + amount.y / size.height * 1125)
                drag.value(it.id, position)
            }
        }, onDragEnd = { worker = null }, onDragCancel = { worker = null })
    }) {
        scale(size.width / 2000, size.height / 1125, pivot = Offset.Zero) {
            drawImage(art.background, dstSize = IntSize(2000, 1125))
            // The slow lattice shadow and drifting dust stay on the yard surface.
            val crane = (sin(frame.seconds * .06) * 100).toFloat()
            repeat(7) { i ->
                drawLine(Color.Black.copy(alpha = .06f), Offset(1200f + crane + i * 28, 80f),
                    Offset(1750f + crane + i * 28, 1100f), 9f)
            }
            frame.workers.sortedBy { it.y + it.height / 2 }.forEach { worker ->
                val h = worker.height
                val w = worker.width
                drawOval(Brush.radialGradient(listOf(Color.Black.copy(alpha = .28f),
                    Color.Transparent), center = Offset(worker.x, worker.y + h * .46f),
                    radius = w * .55f), Offset(worker.x - w * .55f, worker.y + h * .4f),
                    Size(w * 1.1f, h * .16f))
                val pose = (frame.seconds * 2.5 + worker.id).toInt() % 2
                val sprite = if (worker.id == 6) art.visitor else if (worker.wiping)
                    art.walkingWipe[pose] else if (worker.walking)
                    art.walking.getValue(worker.sprite)[pose][if (worker.wearing) 1 else 0]
                else art.workers.getValue(worker.sprite)[if (worker.wearing) 1 else 0]
                val columns = 24
                val rows = 32
                val vertices = FloatArray((columns + 1) * (rows + 1) * 2)
                for (row in 0..rows) for (column in 0..columns) {
                    val nx = column.toFloat() / columns
                    val ny = row.toFloat() / rows
                    var x = (nx - .5f) * w
                    var y = (ny - .5f) * h
                    val foot = ((ny - .65f) / .35f).coerceIn(0f, 1f)
                    if (worker.walking) {
                        val step = sin(frame.seconds * 5 + nx * 9 + worker.id)
                        x += (step * w * .035 * foot).toFloat()
                        y -= (max(0.0, step) * h * .018 * foot).toFloat()
                    }
                    val arm = ((nx - .57f) / .25f).coerceIn(0f, 1f) *
                        (1 - abs(ny - .48f) / .25f).coerceIn(0f, 1f)
                    y -= worker.motion * arm * h * .27f
                    x -= worker.motion * arm * w * .13f
                    if (worker.working) {
                        y += (sin(frame.seconds * 2.4 + worker.id) * h * .022 * arm).toFloat()
                    }
                    val vertex = (row * (columns + 1) + column) * 2
                    vertices[vertex] = worker.x + x
                    vertices[vertex + 1] = worker.y + y
                }
                drawContext.canvas.nativeCanvas.drawBitmapMesh(sprite.asAndroidBitmap(),
                    columns, rows, vertices, 0, null, 0, paint)
                if (!worker.wiping) worker.capProgress?.let { progress ->
                    drawImage(art.caps.getValue(worker.sprite),
                        dstOffset = IntOffset((worker.x + w * (.02f + .22f * progress) -
                            w * .16f).toInt(),
                            (worker.y - h * .47f + h * .6f * progress).toInt()),
                        dstSize = IntSize((w * .32f).toInt(), (h * .1f).toInt()))
                }
            }
            repeat(35) { i ->
                val x = ((i * 173 + frame.seconds * 18) % 2000).toFloat()
                val y = 100f + (i * 137 % 1000)
                drawOval(Brush.radialGradient(listOf(Color(0xFFDBC7A5).copy(alpha = .06f),
                    Color.Transparent), center = Offset(x, y), radius = 70f),
                    Offset(x - 70, y - 20), Size(140f, 40f))
            }
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                textSize = 27f
                typeface = android.graphics.Typeface.MONOSPACE
                setShadowLayer(3f, 1f, 1f, android.graphics.Color.BLACK)
            }
            val seconds = 14 * 3600 + 30 * 60 + frame.seconds.toInt()
            drawContext.canvas.nativeCanvas.drawText("2026-11-17 %02d:%02d:%02d".format(
                seconds / 3600 % 24, seconds / 60 % 60, seconds % 60), 34f, 48f, text)
            text.textAlign = Paint.Align.RIGHT
            drawContext.canvas.nativeCanvas.drawText("CAM-05 施工区", 1890f, 48f, text)
            drawCircle(Color(0xFFE56259), 8f, Offset(1930f, 37f))
            text.textSize = 20f
            drawContext.canvas.nativeCanvas.drawText("REC", 1980f, 44f, text)
        }
    }
}
