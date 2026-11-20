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
                val directory = if (name.startsWith("site-frame-")) {
                    File(System.getProperty("demo.build"), "site-frames")
                } else if (name.startsWith("frame-")) {
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
                            farm = if (scene.id == "farm") FarmModel.frame(0.0) else null,
                            site = if (scene.id == "helmet") SiteModel.frame(0.0) else null)
                    }
                }
            }
        }
        paparazzi.snapshot("sources") { DemoTheme { SourcesScreen(repository) } }
    }

    @Test fun phoneRemote() {
        val repository = MediaRepository(paparazzi.context)
        paparazzi.snapshot("phone-role-home") {
            DemoTheme {
                androidx.compose.foundation.layout.Column {
                    RoleBar(true)
                    ConnectionBar(false, address = "192.168.43.1")
                    HomeScreen(repository)
                }
            }
        }
        listOf("farm", "helmet", "traffic").forEach { id ->
            val scene = repository.scenes.first { it.id == id }
            paparazzi.snapshot("phone-remote-$id") {
                DemoTheme { RemoteSceneScreen(repository, scene,
                    RemoteState(scene = id, seconds = 2.0), true, true,
                    address = "192.168.43.1") }
            }
        }
        val farm = repository.scenes.first { it.id == "farm" }
        paparazzi.snapshot("phone-disconnected") {
            DemoTheme { RemoteSceneScreen(repository, farm, RemoteState(scene = "farm"),
                true, false, "连接错误：连接已断开", "192.168.43.1") }
        }
        paparazzi.snapshot("tablet-remote-indicator") {
            DemoTheme { RemoteSceneScreen(repository, farm, RemoteState(scene = "farm"),
                false, true) }
        }
    }

    @Test fun liveDemoControls() {
        paparazzi.snapshot("phone-live-demo") {
            DemoTheme {
                androidx.compose.foundation.layout.Column {
                    PhoneHeader(true, address = "192.168.43.1 / 10.0.0.2")
                    LiveDemoBar(LiveBoard(true, 4, 1, 110), true)
                }
            }
        }
        paparazzi.snapshot("phone-live-nes-gamepad") {
            DemoTheme {
                androidx.compose.foundation.layout.Column {
                    PhoneHeader(true, address = "192.168.43.1 / 10.0.0.2")
                    LiveDemoBar(LiveBoard(true, 10, 0, 0), true)
                }
            }
        }
    }

    @Test fun siteSequence() {
        val repository = MediaRepository(paparazzi.context)
        val frames = JSONArray()
        fun render(name: String, seconds: Double, demo: Boolean) {
            val state = SiteModel.frame(seconds, demo)
            paparazzi.snapshot(name) { SiteCanvas(repository, state, Modifier.fillMaxSize()) }
            frames.put(JSONObject().put("file", "$name.png").put("seconds", seconds)
                .put("static", !demo).put("head", state.workers.count {
                    !it.wearing && it.x in 0f..2000f })
                .put("helmet", state.workers.count { it.wearing }))
        }
        for (second in 0..24) render("site-frame-demo-%02d".format(second),
            second.toDouble(), true)
        for (second in 0..19) render("site-frame-static-%02d".format(second),
            second + 40.0, false)
        File(System.getProperty("demo.build"), "site-frames.json").writeText(frames.toString(2))
        val moments = mapOf("all-helmets" to 2, "hat-off" to 8, "hat-on" to 12,
            "visitor-entered" to 18, "visitor-left" to 24)
        moments.forEach { (name, second) ->
            paparazzi.snapshot("site-$name") {
                SiteCanvas(repository, SiteModel.frame(second.toDouble(), true),
                    Modifier.fillMaxSize())
            }
        }
        paparazzi.snapshot("site-reset") {
            SiteCanvas(repository, SiteModel.frame(0.0), Modifier.fillMaxSize())
        }
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

// The photographed phone viewport in dp, including the production settings strip.
class CompactRemoteSnapshots {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig(screenWidth = 907,
        screenHeight = 420, xdpi = 160, ydpi = 160, density = Density.MEDIUM,
        orientation = ScreenOrientation.LANDSCAPE, softButtons = false),
        appCompatEnabled = false, snapshotHandler = ExportSnapshots(), useDeviceResolution = true)

    @Test fun compactRemote() {
        listOf("grid" to 4, "settings" to 4, "nes" to 10).forEach { (name, scene) ->
            paparazzi.snapshot("phone-compact-$name") {
                DemoTheme {
                    androidx.compose.material3.Surface(Modifier.fillMaxSize()) {
                        androidx.compose.foundation.layout.Column {
                            PhoneHeader(true, address = "192.168.43.1 / 10.0.0.2",
                                expanded = name == "settings")
                            LiveDemoBar(LiveBoard(true, scene, 1, 110), true)
                        }
                    }
                }
            }
        }
    }
}
