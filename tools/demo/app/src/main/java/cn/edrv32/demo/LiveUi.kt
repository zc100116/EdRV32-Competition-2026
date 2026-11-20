// LiveUi.kt — live-demo L7/L8 mirror wire model and controls; main UI thread.
package cn.edrv32.demo

import androidx.compose.foundation.layout.*
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
    1 -> "traffic"
    2 -> "gesture"
    3 -> "dance"
    4 -> "helmet"
    5 -> "farm"
    else -> "home"
}

@Composable
fun LiveMirror(ui: LiveUi, connected: Boolean, send: (LiveUiAction) -> Unit = {}) {
    Text(ui.title, style = MaterialTheme.typography.titleMedium)
    listOf("页面", "抽屉").forEachIndexed { area, title ->
        val items = ui.items.filter { it.area == area }
        if (items.isNotEmpty()) {
            Text(title, style = MaterialTheme.typography.labelLarge)
            items.forEach { item ->
                val act: (Int, Int) -> Unit = { action, value ->
                    send(LiveUiAction(ui.revision, item.id, action, value))
                }
                when (item.kind) {
                    0 -> FilledTonalButton({ act(0, 0) }, enabled = connected,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                        Text(item.label)
                    }
                    1 -> Row(Modifier.fillMaxWidth().heightIn(min = 48.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(item.label, Modifier.weight(1f))
                        Switch(item.value != 0, { act(0, 0) }, enabled = connected)
                    }
                    2 -> if (item.min >= item.max) {
                        Text("${item.label}：${item.value}",
                            Modifier.fillMaxWidth().heightIn(min = 48.dp))
                    } else {
                        var value by remember(ui.revision, item.id, item.value) {
                            mutableFloatStateOf(item.value.toFloat())
                        }
                        Row(Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text("${item.label}：${value.roundToInt()}", Modifier.weight(1f))
                            Slider(value, { value = it }, Modifier.weight(2f).heightIn(min = 48.dp),
                                enabled = connected, valueRange = item.min.toFloat()..item.max.toFloat(),
                                onValueChangeFinished = { act(1, value.roundToInt()) })
                        }
                    }
                    3 -> {
                        var expanded by remember { mutableStateOf(false) }
                        Box {
                            OutlinedButton({ expanded = true }, enabled = connected,
                                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                                Text("${item.label}：${item.selectedLabel} ▾")
                            }
                            DropdownMenu(expanded, { expanded = false }) {
                                item.options.forEachIndexed { index, option ->
                                    DropdownMenuItem(text = { Text(option) }, onClick = {
                                        expanded = false; act(1, index)
                                    }, modifier = Modifier.heightIn(min = 48.dp))
                                }
                            }
                        }
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
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        listOf("↑" to 0, "↓" to 1, "←" to 2, "→" to 3,
            "上一个" to 11, "下一个" to 10, "确认" to 8, "返回" to 9).forEach { (label, bit) ->
            PadKey(label, bit, keys, connected, change, size = 72.dp)
        }
    }
}

@Composable
fun LiveControlTabs(ui: LiveUi, scene: Int, connected: Boolean, tab: Int,
    select: (Int) -> Unit = {}, pad: (Int) -> Unit = {},
    uiAct: (LiveUiAction) -> Unit = {}) {
    TabRow(tab) {
        listOf("画面控件", "导航").forEachIndexed { index, label ->
            Tab(tab == index, { select(index) }, text = { Text(label) })
        }
    }
    if (tab == 0) LiveMirror(ui, connected, uiAct)
    else if (scene == 11) LiveGamepad(connected, pad)
    else LiveNavigation(connected, pad)
}
