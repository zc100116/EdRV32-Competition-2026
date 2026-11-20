// LiveDemoTest.kt — L3 relay JSON and independent localhost listeners.
package cn.edrv32.demo

import java.net.Socket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LiveDemoTest {
    @Test fun protocol() {
        for (scene in 1..10) {
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
        assertEquals(LiveBoard(true, 10, 3, 110), LiveDemoJson.readBoard(
            """{"board":{"connected":true,"scene":10,"preset":3,"luma":110,"busy":false}}"""))
        listOf("{}", "{bad",
            """{"board":{"connected":"true","scene":1,"preset":0,
                "luma":0,"busy":false}}""",
            """{"board":{"connected":true,"scene":1.5,"preset":0,
                "luma":0,"busy":false}}""").forEach {
            assertThrows(Exception::class.java) { LiveDemoJson.readBoard(it) }
        }
        assertEquals(10, liveScenes.size)
        assertEquals(10, liveChapters.size)
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
                                phone.send(LiveDemoJson.command(0, 10))
                                val command = pc.getInputStream().bufferedReader().readLine()
                                assertEquals(10, JSONObject(command)
                                    .getJSONObject("demo").getInt("arg"))
                                pcPeer.send("""{"board":{"connected":true,"scene":10,
                                    "preset":1,"luma":90,"busy":false}}""".replace("\n", ""))
                                assertEquals(LiveBoard(true, 10, 1, 90), pcStates.await())
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
