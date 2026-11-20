// RemoteSession.kt — T-PHONE-REMOTE; Android gateway discovery and UI-thread state ownership.
// Socket callbacks post to the main looper; all local and remote actions share the reducer.
package cn.edrv32.demo

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Network
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.Closeable
import java.io.IOException
import java.net.NetworkInterface
import java.util.concurrent.Executors

fun remoteClock(): Long = SystemClock.elapsedRealtime()

class RemoteSession(private val repository: MediaRepository, val phone: Boolean) : Closeable {
    var state by mutableStateOf(RemoteState(clock = remoteClock()))
        private set
    var connected by mutableStateOf(false)
        private set
    var error by mutableStateOf("")
        private set
    private var offset = 0L
    private val main = Handler(Looper.getMainLooper())
    private val outgoing = Executors.newSingleThreadExecutor()
    private var peer: RemotePeer? = null
    private var closed = false
    private fun post(block: () -> Unit) { main.post { if (!closed) block() } }
    private val connectivity = repository.context
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    @Volatile private var wifi: Network? = null
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { wifi = network }
        override fun onLost(network: Network) { if (wifi == network) wifi = null }
    }
    init {
        if (!phone) connectivity.registerNetworkCallback(NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(), networkCallback)
    }
    private val transport = RemoteTransport(phone, ::gateway, { connection ->
        post {
            peer = connection
            connected = true
            error = ""
            if (!phone) broadcast()
        }
    }, { line ->
        if (phone) {
            val snapshot = RemoteJson.readState(line)
            repository.scenes.firstOrNull { it.id == snapshot.scene }
                ?: require(snapshot.scene == "home") { "未知场景 ${snapshot.scene}" }
            val received = remoteClock()
            post { state = snapshot; offset = snapshot.clock - received }
        } else {
            val command = RemoteJson.readCommand(line)
            if (command.action == RemoteAction.SCENE) {
                require(command.scene == "home" || repository.scenes.any {
                    it.id == command.scene }) { "未知场景 ${command.scene}" }
            }
            post { command(command) }
        }
    }, { message -> post { connected = false; peer = null; error = message } },
        socketFactory = { wifiNetwork().socketFactory.createSocket() })

    private fun wifiNetwork() = wifi ?: throw IOException("未连接手机热点")
    private fun gateway(): String {
        val route = connectivity.getLinkProperties(wifiNetwork())?.routes?.firstOrNull {
            it.isDefaultRoute && it.gateway is java.net.Inet4Address
        } ?: throw IOException("当前 Wi-Fi 没有 IPv4 默认网关")
        return route.gateway!!.hostAddress!!
    }
    fun current(now: Long = remoteClock()): RemoteState {
        val scene = repository.scenes.firstOrNull { it.id == state.scene }
        val item = scene?.items?.get(state.index)
        return state.at(now + if (phone) offset else 0,
            state.scene == "farm" || item?.type == "site" || item?.type == "street")
    }
    private fun send(line: String) {
        val connection = peer ?: return
        outgoing.execute {
            try { connection.send(line) } catch (failure: IOException) {
                connection.close()
                post { connected = false; peer = null; error = "连接错误：${failure.message}" }
            }
        }
    }
    private fun broadcast() {
        state = current()
        send(RemoteJson.state(state))
    }
    fun command(command: RemoteCommand) {
        if (phone) {
            send(RemoteJson.command(command))
        } else {
            val scene = repository.scenes.firstOrNull { it.id == state.scene }
            state = reduceRemote(current(), command, scene?.items?.size ?: 1)
            broadcast()
        }
    }
    override fun close() {
        closed = true
        transport.close()
        if (!phone) connectivity.unregisterNetworkCallback(networkCallback)
        outgoing.shutdownNow()
    }
}

fun hotspotAddresses(): String = NetworkInterface.getNetworkInterfaces().toList()
    .flatMap { it.inetAddresses.toList() }
    .filter { it is java.net.Inet4Address && !it.isLoopbackAddress }
    .joinToString(" / ") { it.hostAddress!! }
