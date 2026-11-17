// MediaRepository.kt — R5-13; bundled local media and per-item attribution. App clock.
package cn.edrv32.demo

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import org.json.JSONObject

data class DemoMedia(
    val id: String, val name: String, val path: String, val type: String,
    val poster: String, val author: String, val source: String, val license: String,
    val licenseUrl: String,
)
data class DemoScene(
    val id: String, val name: String, val app: String, val thumbnail: String,
    val items: List<DemoMedia>,
)
class MediaRepository(val context: Context) {
    val scenes: List<DemoScene>
    init {
        val root = JSONObject(context.assets.open("catalog.json").bufferedReader().readText())
        val array = root.getJSONArray("scenes")
        scenes = (0 until array.length()).map { index ->
            val scene = array.getJSONObject(index)
            val items = scene.getJSONArray("items")
            DemoScene(scene.getString("id"), scene.getString("name"), scene.getString("app"),
                scene.getString("thumbnail"), (0 until items.length()).map { i ->
                    val m = items.getJSONObject(i)
                    DemoMedia(m.getString("id"), m.getString("name"), m.getString("path"),
                        m.getString("type"), m.getString("poster"), m.getString("author"),
                        m.getString("source"), m.getString("license"), m.getString("license_url"))
                })
        }
    }
    fun image(path: String): ImageBitmap = context.assets.open(path).use {
        BitmapFactory.decodeStream(it).asImageBitmap()
    }
}
