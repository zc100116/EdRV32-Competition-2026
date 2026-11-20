// LiveDemo.kt — live-demo L1/L3; independent PC relay and phone controls.
// Blocking TCP stays on the transport thread; UI state belongs to the main looper.
package cn.edrv32.demo

import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.*
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.Alignment
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.io.Closeable
import java.io.IOException
import java.util.concurrent.Executors
import org.json.JSONObject

const val LIVE_DEMO_PORT = 47633
val liveScenes = listOf("目标检测（80 类）", "手势识别", "人体姿态", "工地安全帽检测",
    "智慧农场", "图形引擎", "抓取实验", "弹弓打靶", "CoreMark 跑分（芯片信息）", "NES 经典游戏")
val liveChapters = listOf("自研 NPU · 多模型部署", "自研 NPU · 多模型部署",
    "自研 NPU · 多模型部署", "落地应用", "落地应用", "自研渲染器", "体感交互", "体感交互",
    "自研 CPU · 跑分与经典游戏", "自研 CPU · 跑分与经典游戏")
val livePresets = listOf("原始", "自动亮度", "降噪", "自动亮度 + 降噪")
data class LiveBoard(val connected: Boolean = false, val scene: Int = 0,
    val preset: Int = 0, val luma: Int = 0, val busy: Boolean = false)

object LiveDemoJson {
    fun command(action: Int, arg: Int): String = JSONObject().put("demo", JSONObject()
        .put("action", action).put("arg", arg)).toString()
    fun pad(keys: Int): String = JSONObject().put("pad", JSONObject()
        .put("keys", keys)).toString()
    fun readBoard(line: String): LiveBoard {
        val root = JSONObject(line)
        require(root.keys().asSequence().toSet() == setOf("board")) { "需要 board 对象" }
        val board = root.getJSONObject("board")
        val fields = setOf("connected", "scene", "preset", "luma", "busy")
        require(board.keys().asSequence().toSet() == fields) {
            "board 需要 connected、scene、preset、luma、busy"
        }
        require(board.get("connected") is Boolean) { "connected 必须为布尔值" }
        require(board.get("busy") is Boolean) { "busy 必须为布尔值" }
        listOf("scene", "preset", "luma").forEach {
            require(board.get(it) is Int) { "$it 必须为整数" }
        }
        return LiveBoard(board.getBoolean("connected"), board.getInt("scene"),
            board.getInt("preset"), board.getInt("luma"), board.getBoolean("busy"))
    }
}

class LiveDemoSession : Closeable {
    var board by mutableStateOf(LiveBoard())
        private set
    var connected by mutableStateOf(false)
        private set
    var error by mutableStateOf("")
        private set
    private val main = Handler(Looper.getMainLooper())
    private val outgoing = Executors.newSingleThreadExecutor()
    private var peer: RemotePeer? = null
    private var closed = false
    private fun post(block: () -> Unit) { main.post { if (!closed) block() } }
    private val transport = RemoteTransport(true, { "" }, { connection ->
        post { peer = connection; connected = true; error = "" }
    }, { line ->
        val snapshot = LiveDemoJson.readBoard(line)
        post { board = snapshot }
    }, { message -> post { peer = null; connected = false; error = message } },
        port = LIVE_DEMO_PORT)
    fun command(action: Int, arg: Int) = send(LiveDemoJson.command(action, arg))
    fun pad(keys: Int) = send(LiveDemoJson.pad(keys))
    private fun send(line: String) {
        val connection = peer ?: return
        outgoing.execute {
            try { connection.send(line) }
            catch (failure: IOException) {
                connection.close()
                post { peer = null; connected = false; error = "连接错误：${failure.message}" }
            }
        }
    }
    override fun close() {
        closed = true
        transport.close()
        outgoing.shutdownNow()
    }
}

@Composable
fun LiveDemoBar(board: LiveBoard, connected: Boolean, error: String = "",
    command: (Int, Int) -> Unit = { _, _ -> }, pad: (Int) -> Unit = {}) {
    val scene = when (board.scene) {
        0 -> "未进入演示"
        255 -> "演示目录"
        else -> "${board.scene}/10 ${liveScenes[board.scene - 1]}"
    }
    Surface(tonalElevation = 4.dp) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 4.dp)) {
            Text("现场演示 · PC ${if (connected) "已连接" else "未连接"}" +
                " · 板端${if (board.connected) "已连接" else "未连接"} · $scene" +
                " · 档位 ${board.preset} · 亮度 ${board.luma}" +
                if (board.busy) " · 切换中" else "")
            if (error.isNotEmpty()) Text(error, color = MaterialTheme.colorScheme.error)
            Row(Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton({ command(2, 0) }, enabled = connected && !board.busy) {
                    Text("上一场景")
                }
                OutlinedButton({ command(1, 0) }, enabled = connected && !board.busy) {
                    Text("下一场景")
                }
                livePresets.forEachIndexed { index, label ->
                    FilterChip(board.preset == index, { command(3, index) },
                        { Text("$index $label") }, enabled = connected && !board.busy)
                }
            }
            Row(Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                liveScenes.forEachIndexed { index, label ->
                    FilterChip(board.scene == index + 1, { command(0, index + 1) },
                        { Text("${index + 1} · ${liveChapters[index]} · $label") },
                        enabled = connected && !board.busy)
                }
            }
            if (board.scene == 10) LiveGamepad(connected, pad)
        }
    }
}

@Composable
fun LiveGamepad(connected: Boolean, send: (Int) -> Unit = {}) {
    var keys by remember { mutableIntStateOf(0) }
    val currentSend by rememberUpdatedState(send)
    DisposableEffect(connected) {
        onDispose { keys = 0; currentSend(0) }
    }
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        listOf("↑", "↓", "←", "→", "A", "B", "Select", "Start", "确认", "返回")
            .forEachIndexed { index, label ->
                Box(Modifier.size(64.dp, 48.dp)
                    .background(if (keys and (1 shl index) != 0)
                        MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.surfaceVariant)
                    .pointerInput(connected) {
                        if (connected) detectTapGestures(onPress = {
                            keys = keys or (1 shl index)
                            currentSend(keys)
                            try { awaitRelease() } finally {
                                keys = keys and (1 shl index).inv()
                                currentSend(keys)
                            }
                        })
                    }, contentAlignment = Alignment.Center) { Text(label) }
            }
    }
}
