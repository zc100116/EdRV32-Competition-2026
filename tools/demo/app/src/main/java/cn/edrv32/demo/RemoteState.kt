// RemoteState.kt — T-PHONE-REMOTE; authoritative reducer and wire snapshots.
// Both displays use the same model time, advanced from the tablet's monotonic clock.
package cn.edrv32.demo

import org.json.JSONArray
import org.json.JSONObject

enum class RemoteAction { SCENE, PREVIOUS, NEXT, TOGGLE, RESET, DEMO, INTRUDE, DRAG, HAT }
data class RemoteCommand(
    val action: RemoteAction, val scene: String = "home", val id: Int = 0,
    val point: FarmPoint = FarmPoint(0f, 0f),
)
data class RemoteState(
    val scene: String = "home", val index: Int = 0, val playing: Boolean = true,
    val seconds: Double = 0.0, val clock: Long = 0, val demoStart: Double? = null,
    val intrusion: Double? = null, val dragged: Map<Int, FarmPoint> = emptyMap(),
    val hats: Map<Int, SiteHatAction> = emptyMap(),
) {
    fun at(now: Long, animated: Boolean): RemoteState = copy(
        seconds = seconds + if (playing && animated) (now - clock) / 1000.0 else 0.0,
        clock = now)
    fun farm() = FarmModel.frame(seconds, demoStart != null, intrusion, dragged)
    fun site() = SiteModel.frame(seconds, demoStart != null, hats, dragged)
}

fun reduceRemote(state: RemoteState, command: RemoteCommand, count: Int): RemoteState =
    when (command.action) {
        RemoteAction.SCENE -> RemoteState(scene = command.scene, clock = state.clock)
        RemoteAction.PREVIOUS -> state.copy(index = (state.index - 1 + count) % count)
        RemoteAction.NEXT -> state.copy(index = (state.index + 1) % count)
        RemoteAction.TOGGLE -> state.copy(playing = !state.playing)
        RemoteAction.RESET -> RemoteState(scene = state.scene, index = state.index,
            clock = state.clock)
        RemoteAction.DEMO -> RemoteState(scene = state.scene, index = state.index,
            clock = state.clock, demoStart = 0.0)
        RemoteAction.INTRUDE -> state.copy(playing = true, demoStart = null,
            intrusion = state.seconds)
        RemoteAction.DRAG -> state.copy(dragged = state.dragged + (command.id to command.point))
        RemoteAction.HAT -> {
            val worker = state.site().workers.first { it.id == command.id }
            state.copy(hats = state.hats +
                (command.id to SiteHatAction(state.seconds, !worker.wearing)))
        }
    }

object RemoteJson {
    fun command(command: RemoteCommand): String = JSONObject()
        .put("action", command.action.name).put("scene", command.scene).put("id", command.id)
        .put("x", command.point.x).put("y", command.point.y).toString()
    fun readCommand(line: String): RemoteCommand {
        val json = JSONObject(line)
        return RemoteCommand(RemoteAction.valueOf(json.getString("action")),
            json.getString("scene"), json.getInt("id"),
            FarmPoint(json.getDouble("x").toFloat(), json.getDouble("y").toFloat()))
    }
    fun state(state: RemoteState): String {
        val dragged = JSONArray()
        state.dragged.forEach { (id, p) -> dragged.put(JSONObject().put("id", id)
            .put("x", p.x).put("y", p.y)) }
        val hats = JSONArray()
        state.hats.forEach { (id, a) -> hats.put(JSONObject().put("id", id)
            .put("seconds", a.seconds).put("wearing", a.wearing)) }
        return JSONObject().put("scene", state.scene).put("index", state.index)
            .put("playing", state.playing).put("seconds", state.seconds).put("clock", state.clock)
            .put("demoStart", state.demoStart ?: JSONObject.NULL)
            .put("intrusion", state.intrusion ?: JSONObject.NULL)
            .put("dragged", dragged).put("hats", hats).toString()
    }
    fun readState(line: String): RemoteState {
        val j = JSONObject(line)
        val dragged = j.getJSONArray("dragged")
        val hats = j.getJSONArray("hats")
        return RemoteState(j.getString("scene"), j.getInt("index"), j.getBoolean("playing"),
            j.getDouble("seconds"), j.getLong("clock"),
            if (j.isNull("demoStart")) null else j.getDouble("demoStart"),
            if (j.isNull("intrusion")) null else j.getDouble("intrusion"),
            (0 until dragged.length()).associate {
                val p = dragged.getJSONObject(it)
                p.getInt("id") to FarmPoint(p.getDouble("x").toFloat(), p.getDouble("y").toFloat())
            }, (0 until hats.length()).associate {
                val a = hats.getJSONObject(it)
                a.getInt("id") to SiteHatAction(a.getDouble("seconds"), a.getBoolean("wearing"))
            })
    }
}
