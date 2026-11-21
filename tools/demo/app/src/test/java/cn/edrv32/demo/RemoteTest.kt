// RemoteTest.kt — T-PHONE-REMOTE; reducer, clock and actual localhost TCP acceptance.
package cn.edrv32.demo

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Test

class RemoteTest {
    @Test fun commandsAndClock() {
        var state = RemoteState(clock = 1000)
        fun apply(action: RemoteAction, scene: String = "home", id: Int = 0,
            point: FarmPoint = FarmPoint(0f, 0f)) {
            state = reduceRemote(state, RemoteCommand(action, scene, id, point), 3)
        }
        apply(RemoteAction.SCENE, "farm")
        assertEquals("farm", state.scene)
        apply(RemoteAction.DRAG, id = 3, point = FarmPoint(1200f, 700f))
        assertEquals(FarmPoint(1200f, 700f), state.dragged[3])
        apply(RemoteAction.DEMO)
        assertEquals(0.0, state.demoStart!!, 0.0)
        assertTrue(state.dragged.isEmpty())
        state = state.at(8000, true)
        assertEquals(7.0, state.seconds, 0.0)
        apply(RemoteAction.INTRUDE)
        assertEquals(7.0, state.intrusion!!, 0.0)
        assertNull(state.demoStart)
        apply(RemoteAction.TOGGLE)
        assertFalse(state.playing)
        assertEquals(7.0, state.at(10000, true).seconds, 0.0)
        apply(RemoteAction.RESET)
        assertEquals(RemoteState(scene = "farm", clock = 8000), state)
        apply(RemoteAction.SCENE, "helmet")
        apply(RemoteAction.HAT, id = 0)
        assertEquals(SiteHatAction(0.0, false), state.hats[0])
        state = state.at(10000, true)
        assertFalse(state.site().workers[0].wearing)
        apply(RemoteAction.HAT, id = 0)
        assertEquals(SiteHatAction(2.0, true), state.hats[0])
        apply(RemoteAction.PREVIOUS)
        assertEquals(2, state.index)
        apply(RemoteAction.NEXT)
        assertEquals(0, state.index)
        apply(RemoteAction.NEXT)
        assertEquals(1, state.index)
        assertEquals(state, RemoteJson.readState(RemoteJson.state(state)))
        RemoteAction.entries.forEach {
            val command = RemoteCommand(it, "farm", 3, FarmPoint(1250f, 600f))
            assertEquals(command, RemoteJson.readCommand(RemoteJson.command(command)))
        }
    }

    private fun <T> LinkedBlockingQueue<T>.await(): T =
        poll(5, TimeUnit.SECONDS) ?: error("Timed out awaiting TCP message")

    @Test fun localhostCommandsSnapshotsAndReconnect() {
        val tablet = AtomicReference(RemoteState(clock = 5000))
        val phoneStates = LinkedBlockingQueue<RemoteState>()
        val phonePeers = LinkedBlockingQueue<RemotePeer>()
        val tabletPeers = LinkedBlockingQueue<RemotePeer>()
        val errors = LinkedBlockingQueue<String>()
        val server = RemoteTransport(true, { "127.0.0.1" }, { phonePeers.put(it) },
            { phoneStates.put(RemoteJson.readState(it)) }, { errors.put(it) })
        val client = RemoteTransport(false, { "127.0.0.1" }, {
            tabletPeers.put(it)
            it.send(RemoteJson.state(tablet.get()))
        }, { line ->
            val next = reduceRemote(tablet.get(), RemoteJson.readCommand(line), 2)
            tablet.set(next)
            tabletPeers.peek()!!.send(RemoteJson.state(next))
        }, { errors.put(it) })
        try {
            var phone = phonePeers.await()
            assertEquals(tablet.get(), phoneStates.await())
            val commands = listOf(
                RemoteCommand(RemoteAction.SCENE, "farm"),
                RemoteCommand(RemoteAction.DRAG, id = 3, point = FarmPoint(1500f, 720f)),
                RemoteCommand(RemoteAction.DEMO), RemoteCommand(RemoteAction.RESET),
                RemoteCommand(RemoteAction.SCENE, "helmet"),
                RemoteCommand(RemoteAction.HAT, id = 0), RemoteCommand(RemoteAction.NEXT),
                RemoteCommand(RemoteAction.TOGGLE))
            commands.forEach { command ->
                phone.send(RemoteJson.command(command))
                val snapshot = phoneStates.await()
                assertEquals(tablet.get(), snapshot)
                // Phone clock is 250 ms behind the tablet; compare at an identical instant.
                val localNow = 6000L
                val offset = snapshot.clock - 4750L
                val remote = snapshot.at(localNow + offset, true)
                val local = tablet.get().at(6250, true)
                assertEquals(local, remote)
                assertEquals(local.farm(), remote.farm())
                assertEquals(local.site(), remote.site())
            }
            phone.close()
            tabletPeers.await()
            phone = phonePeers.await()
            assertEquals(tablet.get(), phoneStates.await())
            // Malformed protocol input must close the peer and report the parse failure.
            phone.send("{broken")
            var message = errors.await()
            while (!message.startsWith("协议错误")) message = errors.await()
            assertTrue(message.startsWith("协议错误"))
        } finally {
            client.close()
            server.close()
        }
    }
}
