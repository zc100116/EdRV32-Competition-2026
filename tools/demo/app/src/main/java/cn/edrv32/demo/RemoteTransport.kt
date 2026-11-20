// RemoteTransport.kt — T-PHONE-REMOTE; one phone listener and one tablet connector.
// Blocking TCP runs on an IO thread; protocol errors close the peer and surface to the UI.
package cn.edrv32.demo

import java.io.BufferedWriter
import java.io.Closeable
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.io.IOException
import org.json.JSONException

const val REMOTE_PORT = 47632

class RemotePeer(private val socket: Socket) : Closeable {
    private val writer: BufferedWriter = socket.getOutputStream().bufferedWriter()
    init { socket.tcpNoDelay = true }
    @Synchronized fun send(line: String) {
        writer.write(line)
        writer.newLine()
        writer.flush()
    }
    fun receive(consume: (String) -> Unit) {
        val reader = socket.getInputStream().bufferedReader()
        while (true) consume(reader.readLine() ?: throw IOException("连接已断开"))
    }
    override fun close() = socket.close()
}

class RemoteTransport(
    private val phone: Boolean, private val gateway: () -> String,
    private val connected: (RemotePeer) -> Unit,
    private val receive: (String) -> Unit, private val status: (String) -> Unit,
    private val socketFactory: () -> Socket = { Socket() },
) : Closeable {
    @Volatile private var running = true
    @Volatile private var socket: Socket? = null
    private val server = if (phone) ServerSocket(REMOTE_PORT) else null
    private val thread = Thread({
        while (running) {
            try {
                val connection = if (phone) server!!.accept() else socketFactory().also {
                    socket = it
                    it.connect(InetSocketAddress(gateway(), REMOTE_PORT), 1000)
                }
                socket = connection
                RemotePeer(connection).use { peer ->
                    connected(peer)
                    peer.receive(receive)
                }
            } catch (error: IOException) {
                if (running) status("连接错误：${error.message}")
            } catch (error: JSONException) {
                if (running) status("协议错误：${error.message}")
            } catch (error: IllegalArgumentException) {
                if (running) status("协议错误：${error.message}")
            } finally {
                socket?.close()
                socket = null
            }
            if (running && !phone) {
                try { Thread.sleep(1000) } catch (_: InterruptedException) { return@Thread }
            }
        }
    }, "demo-remote").apply { start() }
    override fun close() {
        running = false
        server?.close()
        socket?.close()
        thread.interrupt()
    }
}
