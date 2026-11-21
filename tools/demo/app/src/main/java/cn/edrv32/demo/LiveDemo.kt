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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.io.Closeable
import java.io.IOException
import java.util.concurrent.Executors
import org.json.JSONObject

const val LIVE_DEMO_PORT = 47633
val liveScenes = listOf("目标检测", "手势识别", "人体姿态", "工地安全帽检测",
    "智慧农场", "图像处理", "图形引擎", "抓取实验", "弹弓打靶", "CoreMark 跑分", "NES 经典游戏")
val liveChapters = listOf("自研 NPU · 多模型部署", "自研 NPU · 多模型部署",
    "自研 NPU · 多模型部署", "落地应用", "落地应用", "自研图像处理", "自研渲染器", "体感交互", "体感交互",
    "自研 CPU · 跑分与经典游戏", "自研 CPU · 跑分与经典游戏")
val livePresets = listOf("原始", "暗光增强", "降噪", "暗光增强 + 降噪")
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

class LiveDemoSession(private val follow: (String) -> Unit = {}) : Closeable {
    var ui by mutableStateOf(LiveUi())
        private set
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
        when (JSONObject(line).keys().asSequence().toSet()) {
            setOf("board") -> {
                val snapshot = LiveDemoJson.readBoard(line)
                post {
                    if (snapshot.scene != board.scene) follow(liveTabletScene(snapshot.scene))
                    board = snapshot
                }
            }
            setOf("ui") -> {
                val snapshot = LiveUiJson.read(line)
                post { ui = snapshot }
            }
            setOf("ui_error") -> {
                val message = JSONObject(line).getJSONObject("ui_error").getString("message")
                post { error = message }
            }
            else -> throw IllegalArgumentException("需要 board、ui 或 ui_error 对象")
        }
    }, { message -> post { peer = null; connected = false; error = message } },
        port = LIVE_DEMO_PORT)
    fun command(action: Int, arg: Int) = send(LiveDemoJson.command(action, arg))
    fun pad(keys: Int) = send(LiveDemoJson.pad(keys))
    fun uiAct(action: LiveUiAction) = send(LiveUiJson.action(action))
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

// Shared by the independent touch targets: releasing one finger retains the others.
fun livePadKeys(keys: Int, bit: Int, pressed: Boolean): Int =
    if (pressed) keys or (1 shl bit) else keys and (1 shl bit).inv()

private val sceneGroups = listOf(0..2, 3..4, 5..5, 6..6, 7..8, 9..10)
private val chapterShort = listOf("自研 NPU", "落地应用", "图像处理", "渲染器", "体感交互", "自研 CPU")

@Composable
fun LiveDemoBar(board: LiveBoard, connected: Boolean, error: String = "",
    command: (Int, Int) -> Unit = { _, _ -> }, pad: (Int) -> Unit = {},
    ui: LiveUi = LiveUi(), uiAct: (LiveUiAction) -> Unit = {}) {
    val scene = when (board.scene) {
        0 -> "未进入演示"
        255 -> "演示目录"
        else -> "${board.scene}/11 · ${liveScenes[board.scene - 1]}"
    }
    var expanded by remember { mutableStateOf(false) }
    val enabled = connected && !board.busy
    Surface(tonalElevation = 4.dp) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("现场演示 · PC ${if (connected) "已连接" else "未连接"}" +
                " · 板端${if (board.connected) "已连接" else "未连接"}" +
                " · 档位 ${if (board.preset == 255) "自定义" else livePresets[board.preset]}" +
                " · 亮度 ${board.luma}" + if (board.busy) " · 切换中" else "",
                style = MaterialTheme.typography.bodySmall)
            if (error.isNotEmpty()) Text(error, color = MaterialTheme.colorScheme.error)
            Row(Modifier.fillMaxWidth().height(44.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton({ expanded = !expanded }, enabled = enabled,
                    modifier = Modifier.width(240.dp).fillMaxHeight(),
                    contentPadding = PaddingValues(6.dp)) {
                    Text("场景 $scene ▾", style = MaterialTheme.typography.labelSmall,
                        maxLines = 1)
                }
                OutlinedButton({ command(2, 0) }, enabled = enabled,
                    modifier = Modifier.width(76.dp).fillMaxHeight(),
                    contentPadding = PaddingValues(4.dp)) {
                    Text("上一场景", style = MaterialTheme.typography.labelSmall)
                }
                OutlinedButton({ command(1, 0) }, enabled = enabled,
                    modifier = Modifier.width(76.dp).fillMaxHeight(),
                    contentPadding = PaddingValues(4.dp)) {
                    Text("下一场景", style = MaterialTheme.typography.labelSmall)
                }
                livePresets.forEachIndexed { index, label ->
                    FilterChip(board.preset == index, { command(3, index) },
                        { Text(label, style = MaterialTheme.typography.labelSmall) },
                        enabled = enabled)
                }
            }
            if (expanded) LiveSceneGrid(board.scene, enabled) { action, arg ->
                expanded = false; command(action, arg)
            }
            Row(Modifier.fillMaxWidth().height(288.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                LiveMirror(ui, connected, Modifier.weight(1f).fillMaxHeight(), uiAct)
                Box(Modifier.width(if (board.scene == 11) 440.dp else 208.dp).fillMaxHeight(),
                    contentAlignment = Alignment.Center) {
                    if (board.scene == 11) LiveGamepad(connected, pad)
                    else LiveNavigation(connected, pad)
                }
            }
        }
    }
}

@Composable
private fun LiveSceneGrid(scene: Int, enabled: Boolean, command: (Int, Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        sceneGroups.forEachIndexed { chapter, indices ->
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("${chapter + 1} · ${chapterShort[chapter]}",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(vertical = 2.dp))
                indices.forEach { index ->
                    val selected = scene == index + 1
                    val colors = if (selected) ButtonDefaults.filledTonalButtonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary)
                    else ButtonDefaults.filledTonalButtonColors()
                    FilledTonalButton({ command(0, index + 1) },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = enabled,
                        shape = RoundedCornerShape(12.dp), colors = colors,
                        contentPadding = PaddingValues(8.dp)) {
                        Text("${index + 1} ${liveScenes[index]}",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

@Composable
fun LiveGamepad(connected: Boolean, send: (Int) -> Unit = {}) {
    var keys by remember { mutableIntStateOf(0) }
    val currentSend by rememberUpdatedState(send)
    val change: (Int, Boolean) -> Unit = { bit, pressed ->
        keys = livePadKeys(keys, bit, pressed)
        currentSend(keys)
    }
    DisposableEffect(connected) { onDispose { keys = 0; currentSend(0) } }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(192.dp)) {
            PadKey("↑", 0, keys, connected, change, Modifier.align(Alignment.TopCenter), 64.dp)
            PadKey("↓", 1, keys, connected, change, Modifier.align(Alignment.BottomCenter), 64.dp)
            PadKey("←", 2, keys, connected, change, Modifier.align(Alignment.CenterStart), 64.dp)
            PadKey("→", 3, keys, connected, change, Modifier.align(Alignment.CenterEnd), 64.dp)
        }
        Column(Modifier.width(216.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                PadKey("B", 5, keys, connected, change, size = 96.dp, round = true)
                PadKey("A", 4, keys, connected, change, size = 96.dp, round = true)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                PadKey("确认", 8, keys, connected, change, size = 56.dp)
                PadKey("返回", 9, keys, connected, change, size = 56.dp)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                PadKey("Select", 6, keys, connected, change, size = 64.dp)
                PadKey("Start", 7, keys, connected, change, size = 64.dp)
            }
        }
    }
}

@Composable
fun PadKey(label: String, bit: Int, keys: Int, connected: Boolean,
    change: (Int, Boolean) -> Unit, modifier: Modifier = Modifier, size: Dp,
    round: Boolean = false) {
    val pressed = keys and (1 shl bit) != 0
    val currentChange by rememberUpdatedState(change)
    val shape = if (round) CircleShape else RoundedCornerShape(16.dp)
    val background = if (pressed) MaterialTheme.colorScheme.primary
        else MaterialTheme.colorScheme.surfaceVariant
    val foreground = if (pressed) MaterialTheme.colorScheme.onPrimary
        else MaterialTheme.colorScheme.onSurfaceVariant
    Box(modifier.size(size).clip(shape).background(background)
        .pointerInput(connected) {
            if (connected) detectTapGestures(onPress = {
                currentChange(bit, true)
                try { awaitRelease() } finally { currentChange(bit, false) }
            })
        }, contentAlignment = Alignment.Center) {
        Text(label, color = foreground, fontWeight = FontWeight.Bold,
            style = if (round) MaterialTheme.typography.headlineLarge
                else MaterialTheme.typography.titleMedium)
    }
}
