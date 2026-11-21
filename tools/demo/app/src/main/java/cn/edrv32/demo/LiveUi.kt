// LiveUi.kt — live-demo L7/L8 mirror wire model and controls; main UI thread.
package cn.edrv32.demo

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.json.JSONObject
import kotlin.math.roundToInt

data class LiveUiItem(val id: Int, val kind: Int, val value: Int, val min: Int,
    val max: Int, val label: String, val options: List<String>, val area: Int)
// L13.4: a custom preset has no selected option on the board.
val LiveUiItem.selectedLabel: String get() = options.getOrNull(value) ?: "未选"

data class LiveUi(val revision: Long = 0, val page: Int = 0, val title: String = "等待板端控件",
    val items: List<LiveUiItem> = emptyList())
data class LiveUiAction(val revision: Long, val id: Int, val action: Int, val value: Int = 0)

object LiveUiJson {
    fun action(value: LiveUiAction): String = JSONObject().put("ui_act", JSONObject()
        .put("revision", value.revision).put("id", value.id).put("action", value.action)
        .put("value", value.value)).toString()
    fun read(line: String): LiveUi {
        val root = JSONObject(line)
        require(root.keys().asSequence().toSet() == setOf("ui")) { "需要 ui 对象" }
        val ui = root.getJSONObject("ui")
        val items = ui.getJSONArray("items")
        return LiveUi(ui.getLong("revision"), ui.getInt("page"), ui.getString("title"),
            (0 until items.length()).map { index ->
                val item = items.getJSONObject(index)
                val options = item.getJSONArray("options")
                LiveUiItem(item.getInt("id"), item.getInt("kind"), item.getInt("value"),
                    item.getInt("min"), item.getInt("max"), item.getString("label"),
                    (0 until options.length()).map { options.getString(it) }, item.getInt("area"))
            })
    }
}

fun liveTabletScene(scene: Int): String = when (scene) {
    1 -> "street"
    2 -> "gesture"
    3 -> "dance"
    4 -> "helmet"
    5 -> "farm"
    else -> "home"
}

@Composable
fun LiveMirror(ui: LiveUi, connected: Boolean, modifier: Modifier = Modifier,
    send: (LiveUiAction) -> Unit = {}) {
    Column(modifier.verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(ui.title, style = MaterialTheme.typography.labelLarge, maxLines = 1)
        listOf("页面", "抽屉").forEachIndexed { area, title ->
            val items = ui.items.filter { it.area == area }
            if (items.isNotEmpty()) {
                Text(title, style = MaterialTheme.typography.labelSmall)
                items.chunked(3).forEach { row ->
                    Row(Modifier.fillMaxWidth().height(44.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        row.forEach { item ->
                            key(ui.revision, item.id) {
                                Box(Modifier.weight(1f).fillMaxHeight()) {
                                    LiveMirrorItem(item, connected) { action, value ->
                                        send(LiveUiAction(ui.revision, item.id, action, value))
                                    }
                                }
                            }
                        }
                        repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun LiveMirrorItem(item: LiveUiItem, connected: Boolean,
    act: (Int, Int) -> Unit) {
    when (item.kind) {
        0 -> FilledTonalButton({ act(0, 0) }, enabled = connected,
            modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(6.dp)) {
            Text(item.label, style = MaterialTheme.typography.labelSmall, maxLines = 2)
        }
        1 -> Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            Text(item.label, Modifier.weight(1f),
                style = MaterialTheme.typography.labelSmall, maxLines = 2)
            Switch(item.value != 0, { act(0, 0) }, enabled = connected)
        }
        2 -> if (item.min >= item.max) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) {
                Text("${item.label}：${item.value}",
                    style = MaterialTheme.typography.labelSmall, maxLines = 2)
            }
        } else {
            var value by remember(item.id, item.value) {
                mutableFloatStateOf(item.value.toFloat())
            }
            Column(Modifier.fillMaxSize()) {
                Text("${item.label}：${value.roundToInt()}",
                    style = MaterialTheme.typography.labelSmall, maxLines = 1)
                Slider(value, { value = it }, Modifier.fillMaxWidth().height(26.dp),
                    enabled = connected, valueRange = item.min.toFloat()..item.max.toFloat(),
                    onValueChangeFinished = { act(1, value.roundToInt()) })
            }
        }
        3 -> {
            var expanded by remember { mutableStateOf(false) }
            Box(Modifier.fillMaxSize()) {
                OutlinedButton({ expanded = true }, enabled = connected,
                    modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(6.dp)) {
                    Text("${item.label}：${item.selectedLabel} ▾",
                        style = MaterialTheme.typography.labelSmall, maxLines = 2)
                }
                DropdownMenu(expanded, { expanded = false }) {
                    item.options.forEachIndexed { index, option ->
                        DropdownMenuItem(text = { Text(option) }, onClick = {
                            expanded = false; act(1, index)
                        })
                    }
                }
            }
        }
    }
}

@Composable
fun LiveNavigation(connected: Boolean, send: (Int) -> Unit = {}) {
    var keys by remember { mutableIntStateOf(0) }
    val currentSend by rememberUpdatedState(send)
    val change: (Int, Boolean) -> Unit = { bit, pressed ->
        keys = livePadKeys(keys, bit, pressed)
        currentSend(keys)
    }
    DisposableEffect(connected) { onDispose { keys = 0; currentSend(0) } }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(168.dp)) {
            PadKey("↑", 0, keys, connected, change, Modifier.align(Alignment.TopCenter), 56.dp)
            PadKey("↓", 1, keys, connected, change, Modifier.align(Alignment.BottomCenter), 56.dp)
            PadKey("←", 2, keys, connected, change, Modifier.align(Alignment.CenterStart), 56.dp)
            PadKey("→", 3, keys, connected, change, Modifier.align(Alignment.CenterEnd), 56.dp)
        }
        listOf(listOf("上一个" to 11, "下一个" to 10),
            listOf("确认" to 8, "返回" to 9)).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { (label, bit) ->
                    PadKey(label, bit, keys, connected, change,
                        Modifier.width(88.dp).height(48.dp), 48.dp)
                }
            }
        }
    }
}
