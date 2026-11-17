// DemoSnapshots.kt — R5-12/13; real JVM Compose renders, no emulator. Host clock.
package cn.edrv32.demo

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import app.cash.paparazzi.Snapshot
import app.cash.paparazzi.SnapshotHandler
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalInspectionMode
import com.android.resources.Density
import com.android.resources.ScreenOrientation
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Rule
import org.junit.Test

private class ExportSnapshots : SnapshotHandler {
    override fun newFrameHandler(snapshot: Snapshot, frameCount: Int, fps: Int) =
        object : SnapshotHandler.FrameHandler {
            override fun handle(image: BufferedImage) {
                val name = snapshot.name!!
                val directory = if (name.startsWith("frame-")) {
                    File(System.getProperty("demo.build"), "farm-frames")
                } else File(System.getProperty("demo.output")!!)
                directory.mkdirs()
                ImageIO.write(image, "png", File(directory, "$name.png"))
            }
            override fun close() = Unit
        }
    override fun close() = Unit
}

class DemoSnapshots {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig(screenWidth = 1280,
        screenHeight = 720, xdpi = 160, ydpi = 160, density = Density.MEDIUM,
        orientation = ScreenOrientation.LANDSCAPE, softButtons = false),
        appCompatEnabled = false, snapshotHandler = ExportSnapshots(), useDeviceResolution = true)

    @Test fun gallery() {
        val repository = MediaRepository(paparazzi.context)
        paparazzi.snapshot("home") { DemoTheme { HomeScreen(repository) } }
        repository.scenes.forEach { scene ->
            paparazzi.snapshot("scene-${scene.id}") {
                CompositionLocalProvider(LocalInspectionMode provides true) {
                    DemoTheme {
                        SceneScreen(repository, scene, scene.items.first(),
                            farm = if (scene.id == "farm") FarmModel.frame(0.0) else null)
                    }
                }
            }
        }
        paparazzi.snapshot("sources") { DemoTheme { SourcesScreen(repository) } }
    }

    @Test fun farmSequence() {
        val repository = MediaRepository(paparazzi.context)
        val frames = JSONArray()
        fun render(name: String, seconds: Double, demo: Boolean, still: Boolean) {
            val state = FarmModel.frame(seconds, demo)
            paparazzi.snapshot(name) {
                FarmCanvas(repository, state, Modifier.fillMaxSize())
            }
            frames.put(JSONObject().put("file", "$name.png").put("seconds", seconds)
                .put("static", still).put("person", state.person?.visible == true))
        }
        for (second in 0..24) render("frame-demo-%02d".format(second), second.toDouble(),
            demo = true, still = false)
        render("frame-climb", 13.75, demo = true, still = false)
        for (second in 0..19) render("frame-static-%02d".format(second), second + 40.0,
            demo = false, still = true)
        File(System.getProperty("demo.build"), "farm-frames.json").writeText(frames.toString(2))
        val moments = mapOf("static" to 0, "sheep-leaving" to 6, "missing" to 9,
            "sheep-return" to 13, "intruder" to 18, "person-left" to 24)
        moments.forEach { (name, second) ->
            paparazzi.snapshot("farm-$name") {
                FarmCanvas(repository, FarmModel.frame(second.toDouble(), true),
                    Modifier.fillMaxSize())
            }
        }
    }
}
