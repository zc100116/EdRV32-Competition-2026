// DemoUi.kt — R5-10/13; Material 3 offline gallery and three-second controls. UI clock.
package cn.edrv32.demo

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

private val Ink = Color(0xFF101E25)
private val Panel = Color(0xFF20363F)
private val Gold = Color(0xFFDABD89)
private val Muted = Color(0xFFA7BBBF)

@Composable
fun DemoTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = darkColorScheme(primary = Gold, background = Ink,
        surface = Panel, onSurface = Color(0xFFF4F0E6))) {
        CompositionLocalProvider(LocalContentColor provides Color(0xFFF4F0E6), content = content)
    }
}

@Composable
fun DemoApp(repository: MediaRepository) {
    var destination by remember { mutableStateOf("home") }
    BackHandler(destination != "home") { destination = "home" }
    Crossfade(targetState = destination, label = "scene transition") { screen ->
        when (screen) {
            "home" -> HomeScreen(repository, { destination = it }, { destination = "sources" })
            "sources" -> SourcesScreen(repository) { destination = "home" }
            else -> MediaScreen(repository, repository.scenes.first { it.id == screen }) {
                destination = "home"
            }
        }
    }
}

@Composable
fun HomeScreen(repository: MediaRepository, enter: (String) -> Unit = {},
    sources: () -> Unit = {}) {
    Column(Modifier.fillMaxSize().background(Brush.linearGradient(
        listOf(Color(0xFF173338), Ink))).padding(horizontal = 38.dp, vertical = 24.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("EdRV32  /  LIVE DEMO", color = Gold, fontSize = 12.sp,
                    letterSpacing = 3.sp)
                Text("把视界，放进镜头", fontSize = 32.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 10.dp))
                Text("选择场景，让开发板的摄像头对准屏幕。", color = Muted, fontSize = 15.sp,
                    modifier = Modifier.padding(top = 8.dp, bottom = 24.dp))
            }
            OutlinedButton(onClick = sources) { Text("素材来源  ↗") }
        }
        LazyVerticalGrid(columns = GridCells.Fixed(4), modifier = Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            items(repository.scenes) { scene ->
                val thumbnail = remember(scene.id) { repository.image(scene.thumbnail) }
                Card(onClick = { enter(scene.id) }, shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = Panel)) {
                    if (scene.id == "farm") {
                        FarmCanvas(repository, FarmModel.frame(0.0, true),
                            Modifier.fillMaxWidth().aspectRatio(16f / 9),
                            onTap = { enter(scene.id) })
                    } else Image(thumbnail, null,
                        Modifier.fillMaxWidth().aspectRatio(16f / 9),
                        contentScale = ContentScale.Crop)
                    Column(Modifier.padding(12.dp)) {
                        Text(scene.name, fontSize = 20.sp, fontWeight = FontWeight.Medium)
                        Text(scene.app, color = Muted, fontSize = 12.sp, lineHeight = 16.sp,
                            modifier = Modifier.padding(top = 5.dp))
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween) {
            Text("离线演示素材包", color = Muted, fontSize = 12.sp)
            Text("7 个场景 · 一块屏幕", color = Muted, fontSize = 12.sp)
        }
    }
}

@Composable
fun SourcesScreen(repository: MediaRepository, back: () -> Unit = {}) {
    Column(Modifier.fillMaxSize().background(Ink).padding(30.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically) {
            Text("素材来源", fontSize = 28.sp)
            OutlinedButton(onClick = back) { Text("‹ 返回") }
        }
        Text("本地素材 · 原作者与许可逐项列出 · 地址仅供查阅", color = Muted,
            modifier = Modifier.padding(vertical = 18.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(repository.scenes.flatMap { it.items }) { item ->
                Surface(color = Panel, shape = RoundedCornerShape(12.dp)) {
                    Column(Modifier.fillMaxWidth().padding(18.dp)) {
                        Text(item.name, color = Gold, fontWeight = FontWeight.Medium)
                        Text("作者 / 来源：${item.author}", fontSize = 13.sp)
                        Text(item.source, color = Muted, fontSize = 12.sp)
                        Text("许可：${item.license}", fontSize = 13.sp)
                        Text(item.licenseUrl, color = Muted, fontSize = 12.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun MediaScreen(repository: MediaRepository, scene: DemoScene, back: () -> Unit) {
    var index by remember { mutableIntStateOf(0) }
    var playing by remember { mutableStateOf(true) }
    var controls by remember { mutableStateOf(true) }
    var interaction by remember { mutableIntStateOf(0) }
    var seconds by remember { mutableDoubleStateOf(0.0) }
    var demo by remember { mutableStateOf(false) }
    var intrusion by remember { mutableStateOf<Double?>(null) }
    val dragged = remember { mutableStateMapOf<Int, FarmPoint>() }
    val farm = scene.id == "farm"
    val item = scene.items[index]
    fun reveal() { controls = true; interaction++ }
    fun change(delta: Int) {
        index = (index + delta + scene.items.size) % scene.items.size
        reveal()
    }
    LaunchedEffect(interaction) { delay(3000); controls = false }
    LaunchedEffect(index, playing) {
        if (playing && item.type == "image/jpeg") {
            delay(5000)
            index = (index + 1) % scene.items.size
        }
    }
    LaunchedEffect(playing, farm) {
        if (farm && playing) {
            var previous = withFrameNanos { it }
            while (true) {
                val now = withFrameNanos { it }
                seconds += (now - previous) / 1_000_000_000.0
                previous = now
            }
        }
    }
    SceneScreen(repository, scene, item, playing, controls,
        if (farm) FarmModel.frame(seconds, demo, intrusion, dragged) else null,
        back = back, previous = { change(-1) }, next = { change(1) },
        toggle = { playing = !playing; reveal() }, reveal = { reveal() },
        reset = {
            seconds = 0.0; playing = true; demo = false; intrusion = null
            dragged.clear(); reveal()
        },
        runDemo = {
            seconds = 0.0; playing = true; demo = true; intrusion = null
            dragged.clear(); reveal()
        },
        intrude = { playing = true; demo = false; intrusion = seconds; reveal() },
        drag = { id, point -> dragged[id] = point })
}

@Composable
fun SceneScreen(repository: MediaRepository, scene: DemoScene, item: DemoMedia,
    playing: Boolean = false, controls: Boolean = false, farm: FarmFrame? = null,
    back: () -> Unit = {}, previous: () -> Unit = {}, next: () -> Unit = {},
    toggle: () -> Unit = {}, reveal: () -> Unit = {}, reset: () -> Unit = {},
    runDemo: () -> Unit = {}, intrude: () -> Unit = {},
    drag: (Int, FarmPoint) -> Unit = { _, _ -> }) {
    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        var displacement by remember { mutableFloatStateOf(0f) }
        val gestures = if (farm == null) Modifier.pointerInput(item.id) {
            detectTapGestures { reveal() }
        }.pointerInput(item.id) {
            detectHorizontalDragGestures(onDragStart = { displacement = 0f },
                onHorizontalDrag = { change, amount -> change.consume(); displacement += amount },
                onDragEnd = {
                    if (displacement < -80) next()
                    else if (displacement > 80) previous()
                })
        } else Modifier
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9).clipToBounds()) {
            if (farm != null) {
                FarmCanvas(repository, farm, Modifier.fillMaxSize(), reveal, drag)
            } else if (item.type == "video/mp4" && !LocalInspectionMode.current) {
                VideoSurface(repository, item, playing, Modifier.fillMaxSize())
            } else {
                val image = remember(item.path) { repository.image(item.poster) }
                Image(image, item.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            }
            if (farm == null) Box(Modifier.matchParentSize().then(gestures))
            AnimatedVisibility(controls, enter = fadeIn(), exit = fadeOut(),
                modifier = Modifier.align(Alignment.BottomCenter)) {
                Column(Modifier.fillMaxWidth().background(Brush.verticalGradient(
                    listOf(Color.Transparent, Ink.copy(alpha = .95f)))).padding(18.dp)) {
                    Text("${scene.name} / ${item.name}", fontSize = 13.sp, color = Color.White,
                        modifier = Modifier.padding(start = 8.dp, bottom = 10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(back) { Text("‹ 返回") }
                        if (farm == null) {
                            OutlinedButton(previous) { Text("上一个") }
                            OutlinedButton(next) { Text("下一个") }
                        } else {
                            OutlinedButton(intrude) { Text("闯入") }
                            OutlinedButton(runDemo) { Text("演示") }
                            OutlinedButton(reset) { Text("复位") }
                        }
                        Button(toggle) { Text(if (playing) "暂停" else "播放") }
                    }
                }
            }
        }
    }
}
