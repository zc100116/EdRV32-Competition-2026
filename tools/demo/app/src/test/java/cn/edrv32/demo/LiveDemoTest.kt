// LiveDemoTest.kt — L3 relay JSON and independent localhost listeners.
package cn.edrv32.demo

import java.net.Socket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LiveDemoTest {
    @Test fun unselectedMirrorChoice() {
        val item = LiveUiItem(3, 3, -1, 0, 0, "快捷档", listOf("原始", "降噪"), 1)
        assertEquals("未选", item.selectedLabel)
        assertEquals("未选", item.copy(value = 2).selectedLabel)
        assertEquals("降噪", item.copy(value = 1).selectedLabel)
    }

    @Test fun simultaneousPadKeysAndIndependentRelease() {
        var keys = livePadKeys(0, 3, true)
        keys = livePadKeys(keys, 4, true)
        assertEquals((1 shl 3) or (1 shl 4), keys)
        assertEquals(keys, JSONObject(LiveDemoJson.pad(keys)).getJSONObject("pad").getInt("keys"))
        keys = livePadKeys(keys, 5, true)
        assertEquals((1 shl 3) or (1 shl 4) or (1 shl 5), keys)
        keys = livePadKeys(keys, 4, false)
        assertEquals((1 shl 3) or (1 shl 5), keys)
        keys = livePadKeys(keys, 3, false)
        assertEquals(1 shl 5, keys)
        assertEquals(0, livePadKeys(keys, 5, false))
        for (bit in 0..9) {
            assertEquals(1 shl bit, livePadKeys(0, bit, true))
            assertEquals(0, livePadKeys(1 shl bit, bit, false))
        }
    }

    @Test fun protocol() {
        for (scene in 1..11) {
            val message = JSONObject(LiveDemoJson.command(0, scene)).getJSONObject("demo")
            assertEquals(0, message.getInt("action"))
            assertEquals(scene, message.getInt("arg"))
        }
        for (preset in 0..3) {
            val message = JSONObject(LiveDemoJson.command(3, preset)).getJSONObject("demo")
            assertEquals(3, message.getInt("action"))
            assertEquals(preset, message.getInt("arg"))
        }
        for (bit in 0..11) assertEquals(1 shl bit,
            JSONObject(LiveDemoJson.pad(1 shl bit)).getJSONObject("pad").getInt("keys"))
        assertEquals(LiveBoard(true, 11, 3, 110), LiveDemoJson.readBoard(
            """{"board":{"connected":true,"scene":11,"preset":3,"luma":110,"busy":false}}"""))
        listOf("{}", "{bad",
            """{"board":{"connected":"true","scene":1,"preset":0,
                "luma":0,"busy":false}}""",
            """{"board":{"connected":true,"scene":1.5,"preset":0,
                "luma":0,"busy":false}}""").forEach {
            assertThrows(Exception::class.java) { LiveDemoJson.readBoard(it) }
        }
        assertEquals(11, liveScenes.size)
        assertEquals(11, liveChapters.size)
    }

    @Test fun mirrorJsonAndTabletMapping() {
        val action = JSONObject(LiveUiJson.action(LiveUiAction(123, 9, 1, -256)))
            .getJSONObject("ui_act")
        assertEquals(setOf("revision", "id", "action", "value"),
            action.keys().asSequence().toSet())
        assertEquals(123, action.getInt("revision"))
        assertEquals(9, action.getInt("id"))
        assertEquals(1, action.getInt("action"))
        assertEquals(-256, action.getInt("value"))
        assertEquals(4294967295L, JSONObject(LiveUiJson.action(
            LiveUiAction(4294967295L, 1, 0))).getJSONObject("ui_act").getLong("revision"))
        val ui = LiveUiJson.read("""{"ui":{"revision":7,"page":4,"title":"图形引擎",
            "items":[{"id":3,"kind":3,"value":1,"min":0,"max":0,"label":"模式",
            "options":["立方体","球体"],"area":1}]}}""")
        assertEquals(LiveUi(7, 4, "图形引擎", listOf(
            LiveUiItem(3, 3, 1, 0, 0, "模式", listOf("立方体", "球体"), 1))), ui)
        assertEquals(listOf("street", "gesture", "dance", "helmet", "farm"),
            (1..5).map(::liveTabletScene))
        (6..11).plus(listOf(0, 255)).forEach { assertEquals("home", liveTabletScene(it)) }
        val manual = reduceRemote(RemoteState(scene = liveTabletScene(1)),
            RemoteCommand(RemoteAction.SCENE, scene = "detect"), 1)
        assertEquals("detect", manual.scene)
    }

    private fun <T> LinkedBlockingQueue<T>.await(): T =
        poll(5, TimeUnit.SECONDS) ?: error("Timed out awaiting relay")

    @Test fun separateListenersAndMalformedPeer() {
        val pcStates = LinkedBlockingQueue<LiveBoard>()
        val peers = LinkedBlockingQueue<RemotePeer>()
        val errors = LinkedBlockingQueue<String>()
        val tabletLines = LinkedBlockingQueue<String>()
        RemoteTransport(true, { "" }, {}, { tabletLines.put(it) }, { errors.offer(it) }).use {
            RemoteTransport(true, { "" }, { peers.put(it) },
                { pcStates.put(LiveDemoJson.readBoard(it)) }, { errors.offer(it) },
                port = LIVE_DEMO_PORT).use {
                Socket("127.0.0.1", REMOTE_PORT).use { tablet ->
                    RemotePeer(tablet).use { tabletPeer ->
                        Socket("127.0.0.1", LIVE_DEMO_PORT).use { pc ->
                            RemotePeer(pc).use { pcPeer ->
                                val phone = peers.await()
                                phone.send(LiveDemoJson.command(0, 11))
                                val command = pc.getInputStream().bufferedReader().readLine()
                                assertEquals(11, JSONObject(command)
                                    .getJSONObject("demo").getInt("arg"))
                                pcPeer.send("""{"board":{"connected":true,"scene":11,
                                    "preset":1,"luma":90,"busy":false}}""".replace("\n", ""))
                                assertEquals(LiveBoard(true, 11, 1, 90), pcStates.await())
                                pcPeer.send("{bad")
                                assertTrue(errors.await().startsWith("协议错误"))
                                assertEquals(-1, pc.getInputStream().read())
                                tabletPeer.send("tablet-still-connected")
                                assertEquals("tablet-still-connected", tabletLines.await())
                            }
                        }
                        Socket("127.0.0.1", LIVE_DEMO_PORT).use { pc ->
                            peers.await().send(LiveDemoJson.pad(16))
                            val line = pc.getInputStream().bufferedReader().readLine()
                            assertEquals(16, JSONObject(line)
                                .getJSONObject("pad").getInt("keys"))
                        }
                    }
                }
            }
        }
    }
}
