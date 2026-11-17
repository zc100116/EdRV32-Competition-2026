// VideoSurface.kt — R5-10/13; asset-only Media3 player lifecycle. Android UI clock.
package cn.edrv32.demo

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView

@Composable
fun VideoSurface(repository: MediaRepository, item: DemoMedia, playing: Boolean,
    modifier: Modifier = Modifier) {
    val player = remember(item.id) {
        ExoPlayer.Builder(repository.context).build().apply {
            setMediaItem(MediaItem.fromUri(Uri.parse("asset:///${item.path}")))
            addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    throw IllegalStateException("Cannot play ${item.path}: ${error.message}", error)
                }
            })
            repeatMode = Player.REPEAT_MODE_ONE
            volume = 0f
            prepare()
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(playing, player) { player.playWhenReady = playing }
    AndroidView(modifier = modifier, factory = { context ->
        PlayerView(context).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            this.player = player
        }
    }, update = { it.player = player })
}
