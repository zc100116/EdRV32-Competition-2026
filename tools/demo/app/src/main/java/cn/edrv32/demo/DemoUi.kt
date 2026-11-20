// DemoUi.kt — R5-10/13; Material 3 offline gallery and three-second controls. UI clock.
package cn.edrv32.demo

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
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
    val preferences = remember {
        repository.context.getSharedPreferences("remote-role", android.content.Context.MODE_PRIVATE)
    }
    var phone by remember { mutableStateOf(preferences.getBoolean("phone", false)) }
    val session = remember(phone) { RemoteSession(repository, phone) }
    DisposableEffect(session) { onDispose { session.close() } }
    var phoneHome by remember(phone) { mutableStateOf(false) }
    var sources by remember { mutableStateOf(false) }
    val address by produceState("", phone) {
        if (phone) while (true) { value = hotspotAddresses(); delay(1000) }
    }
    val command: (RemoteCommand) -> Unit = { session.command(it) }
    val home = {
        if (phone) phoneHome = true
        command(RemoteCommand(RemoteAction.SCENE))
    }
    BackHandler(session.state.scene != "home" || sources) { sources = false; home() }
    val role: (Boolean) -> Unit = {
        phone = it
        preferences.edit().putBoolean("phone", it).apply()
    }
    if (sources) SourcesScreen(repository) { sources = false }
    else if (session.state.scene == "home" || (phone && phoneHome)) {
        Column {
            RoleBar(phone, role)
            if (phone) ConnectionBar(session.connected, session.error, address)
            HomeScreen(repository, {
                phoneHome = false
                command(RemoteCommand(RemoteAction.SCENE, scene = it))
            },
                { sources = true })
        }
    } else {
        val scene = repository.scenes.first { it.id == session.state.scene }
        ControlledScreen(repository, scene, session, address, home)
    }
}

@Composable
fun RoleBar(phone: Boolean, choose: (Boolean) -> Unit = {}) {
    Row(Modifier.fillMaxWidth().background(Ink).padding(horizontal = 24.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text("演示角色", color = Muted)
        FilterChip(!phone, { choose(false) }, { Text("平板显示端") })
        FilterChip(phone, { choose(true) }, { Text("手机遥控端") })
    }
}

@Composable
fun ConnectionBar(connected: Boolean, error: String = "", address: String = "") {
    Row(Modifier.fillMaxWidth().background(Ink).padding(horizontal = 20.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween) {
        Text(if (connected) "已连接平板" else "等待平板连接", color = Gold, fontSize = 14.sp)
        Text("热点 $address : $REMOTE_PORT", color = Muted, fontSize = 12.sp)
    }
    if (error.isNotEmpty()) Text(error, color = Color(0xFFFF9F8C), fontSize = 12.sp,
        modifier = Modifier.background(Ink).fillMaxWidth().padding(horizontal = 20.dp))
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
                    } else if (scene.id == "helmet") {
                        SiteCanvas(repository, SiteModel.frame(0.0),
                            Modifier.fillMaxWidth().aspectRatio(16f / 9),
                            onTap = { enter(scene.id) }, onHat = { enter(scene.id) })
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
fun ControlledScreen(repository: MediaRepository, scene: DemoScene, session: RemoteSession,
    address: String, back: () -> Unit) {
    var controls by remember(scene.id) { mutableStateOf(true) }
    var interaction by remember { mutableIntStateOf(0) }
    var now by remember { mutableLongStateOf(remoteClock()) }
    var pendingDrag by remember { mutableStateOf<RemoteCommand?>(null) }
    fun reveal() { controls = true; interaction++ }
    fun act(action: RemoteAction) { session.command(RemoteCommand(action)); reveal() }
    LaunchedEffect(interaction) { delay(3000); controls = false }
    LaunchedEffect(session) {
        while (true) { withFrameNanos { now = remoteClock() } }
    }
    // Coalesce the latest scene coordinate, including the release coordinate, at <=30 Hz.
    LaunchedEffect(session) {
        while (true) {
            delay(34)
            pendingDrag?.let { session.command(it); pendingDrag = null }
        }
    }
    val state = session.current(now)
    val item = scene.items[state.index]
    LaunchedEffect(state.scene, state.index, state.playing, session.phone) {
        if (!session.phone && state.playing && item.type == "image/jpeg") {
            delay(5000)
            session.command(RemoteCommand(RemoteAction.NEXT))
        }
    }
    val drag: (Int, FarmPoint) -> Unit = { id, point ->
        val command = RemoteCommand(RemoteAction.DRAG, id = id, point = point)
        if (session.phone) pendingDrag = command else session.command(command)
    }
    RemoteSceneScreen(repository, scene, state, session.phone, session.connected,
        session.error, address, controls,
        back = { back(); reveal() },
        previous = { act(RemoteAction.PREVIOUS) }, next = { act(RemoteAction.NEXT) },
        toggle = { act(RemoteAction.TOGGLE) }, reveal = { reveal() },
        reset = { act(RemoteAction.RESET) }, runDemo = { act(RemoteAction.DEMO) },
        intrude = { act(RemoteAction.INTRUDE) }, drag = drag,
        hat = { session.command(RemoteCommand(RemoteAction.HAT, id = it)) })
}

@Composable
fun RemoteSceneScreen(repository: MediaRepository, scene: DemoScene, state: RemoteState,
    phone: Boolean, connected: Boolean, error: String = "", address: String = "",
    controls: Boolean = true, back: () -> Unit = {}, previous: () -> Unit = {},
    next: () -> Unit = {}, toggle: () -> Unit = {}, reveal: () -> Unit = {},
    reset: () -> Unit = {}, runDemo: () -> Unit = {}, intrude: () -> Unit = {},
    drag: (Int, FarmPoint) -> Unit = { _, _ -> }, hat: (Int) -> Unit = {}) {
    val item = scene.items[state.index]
    val farm = if (scene.id == "farm") state.farm() else null
    val site = if (item.type == "site") state.site() else null
    if (phone) Column(Modifier.fillMaxSize().background(Ink)) {
        ConnectionBar(connected, error, address)
        Box(Modifier.weight(1f).fillMaxWidth().clipToBounds(),
            contentAlignment = Alignment.Center) {
            SceneScreen(repository, scene, item, state.playing, false, farm,
                previous = previous, next = next, drag = drag, site = site, hat = hat,
                posterOnly = true)
        }
        SceneControls(farm != null, site != null, state.playing, back, previous, next,
            toggle, reset, runDemo, intrude)
    } else SceneScreen(repository, scene, item, state.playing, controls, farm,
        back, previous, next, toggle, reveal, reset, runDemo, intrude, drag, site, hat,
        connection = if (connected) "● 已连接遥控" else
            if (error.isEmpty()) "○ 等待遥控" else "○ $error")
}

@Composable
fun SceneControls(farm: Boolean, site: Boolean, playing: Boolean,
    back: () -> Unit, previous: () -> Unit, next: () -> Unit, toggle: () -> Unit,
    reset: () -> Unit, runDemo: () -> Unit, intrude: () -> Unit) {
    Row(Modifier.padding(horizontal = 18.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        OutlinedButton(back) { Text("‹ 返回") }
        if (!farm) {
            OutlinedButton(previous) { Text("上一个") }
            OutlinedButton(next) { Text("下一个") }
        }
        if (farm || site) {
            if (farm) OutlinedButton(intrude) { Text("闯入") }
            OutlinedButton(runDemo) { Text("演示") }
            OutlinedButton(reset) { Text("复位") }
        }
        Button(toggle) { Text(if (playing) "暂停" else "播放") }
    }
}

@Composable
fun SceneScreen(repository: MediaRepository, scene: DemoScene, item: DemoMedia,
    playing: Boolean = false, controls: Boolean = false, farm: FarmFrame? = null,
    back: () -> Unit = {}, previous: () -> Unit = {}, next: () -> Unit = {},
    toggle: () -> Unit = {}, reveal: () -> Unit = {}, reset: () -> Unit = {},
    runDemo: () -> Unit = {}, intrude: () -> Unit = {},
    drag: (Int, FarmPoint) -> Unit = { _, _ -> }, site: SiteFrame? = null,
    hat: (Int) -> Unit = {}, posterOnly: Boolean = false, connection: String = "") {
    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        var displacement by remember { mutableFloatStateOf(0f) }
        val gestures = if (farm == null && site == null) Modifier.pointerInput(item.id) {
            detectTapGestures { reveal() }
        }.pointerInput(item.id) {
            detectHorizontalDragGestures(onDragStart = { displacement = 0f },
                onHorizontalDrag = { change, amount -> change.consume(); displacement += amount },
                onDragEnd = {
                    if (displacement < -80) next()
                    else if (displacement > 80) previous()
                })
        } else Modifier
        Box(Modifier.aspectRatio(16f / 9, matchHeightConstraintsFirst = true).clipToBounds()) {
            if (farm != null) {
                FarmCanvas(repository, farm, Modifier.fillMaxSize(), reveal, drag)
            } else if (site != null) {
                SiteCanvas(repository, site, Modifier.fillMaxSize(), reveal, hat, drag)
            } else if (item.type == "video/mp4" && !posterOnly && !LocalInspectionMode.current) {
                VideoSurface(repository, item, playing, Modifier.fillMaxSize())
            } else {
                val image = remember(item.path) { repository.image(item.poster) }
                Image(image, item.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            }
            if (farm == null && site == null) Box(Modifier.matchParentSize().then(gestures))
            AnimatedVisibility(controls, enter = fadeIn(), exit = fadeOut(),
                modifier = Modifier.align(Alignment.BottomCenter)) {
                Column(Modifier.fillMaxWidth().background(Brush.verticalGradient(
                    listOf(Color.Transparent, Ink.copy(alpha = .95f)))).padding(18.dp)) {
                    Text("${scene.name} / ${item.name}", fontSize = 13.sp, color = Color.White,
                        modifier = Modifier.padding(start = 8.dp, bottom = 10.dp))
                    if (connection.isNotEmpty()) Text(connection, fontSize = 11.sp,
                        color = Muted, modifier = Modifier.padding(start = 8.dp))
                    SceneControls(farm != null, site != null, playing, back, previous, next,
                        toggle, reset, runDemo, intrude)
                }
            }
        }
    }
}
