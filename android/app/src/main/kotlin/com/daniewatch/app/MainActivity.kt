package com.daniewatch.app

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.daniewatch.app/pip"
    private var pipMethodChannel: MethodChannel? = null
    private var isPlaying: Boolean = true

    companion object {
        private const val ACTION_SEEK_BACKWARD = "com.daniewatch.app.SEEK_BACKWARD"
        private const val ACTION_PLAY_PAUSE = "com.daniewatch.app.PLAY_PAUSE"
        private const val ACTION_SEEK_FORWARD = "com.daniewatch.app.SEEK_FORWARD"
        private const val REQUEST_SEEK_BACKWARD = 1
        private const val REQUEST_PLAY_PAUSE = 2
        private const val REQUEST_SEEK_FORWARD = 3
    }

    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_SEEK_BACKWARD -> {
                    pipMethodChannel?.invokeMethod("onPipAction", "seekBackward")
                }
                ACTION_PLAY_PAUSE -> {
                    isPlaying = !isPlaying
                    pipMethodChannel?.invokeMethod("onPipAction", if (isPlaying) "play" else "pause")
                    // Update PiP params to reflect new play/pause icon
                    updatePipActions()
                }
                ACTION_SEEK_FORWARD -> {
                    pipMethodChannel?.invokeMethod("onPipAction", "seekForward")
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPipMode" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val aspectWidth = call.argument<Int>("aspectWidth") ?: 16
                        val aspectHeight = call.argument<Int>("aspectHeight") ?: 9
                        try {
                            isPlaying = true // Assume playing when entering PiP
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(aspectWidth, aspectHeight))
                                .setActions(buildPipActions())
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", "Failed to enter PiP: ${e.message}", null)
                        }
                    } else {
                        result.error("PIP_UNSUPPORTED", "PiP requires Android 8.0+", null)
                    }
                }
                "updatePipPlayState" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        isPlaying = call.argument<Boolean>("isPlaying") ?: true
                        updatePipActions()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "isPipSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }
                "isInPipMode" -> {
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            isInPictureInPictureMode
                        else false
                    )
                }
                else -> result.notImplemented()
            }
        }

        // Register PiP action broadcast receiver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val filter = IntentFilter().apply {
                addAction(ACTION_SEEK_BACKWARD)
                addAction(ACTION_PLAY_PAUSE)
                addAction(ACTION_SEEK_FORWARD)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(pipActionReceiver, filter)
            }
        }
    }

    private fun buildPipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()

        val actions = mutableListOf<RemoteAction>()

        // 1. Seek Backward (10s)
        val seekBackwardIntent = PendingIntent.getBroadcast(
            this, REQUEST_SEEK_BACKWARD,
            Intent(ACTION_SEEK_BACKWARD).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, R.drawable.ic_pip_seek_backward),
                "Rewind",
                "Seek backward 10 seconds",
                seekBackwardIntent
            )
        )

        // 2. Play/Pause
        val playPauseIntent = PendingIntent.getBroadcast(
            this, REQUEST_PLAY_PAUSE,
            Intent(ACTION_PLAY_PAUSE).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val playPauseIcon = if (isPlaying) R.drawable.ic_pip_pause else R.drawable.ic_pip_play
        val playPauseTitle = if (isPlaying) "Pause" else "Play"
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, playPauseIcon),
                playPauseTitle,
                "$playPauseTitle video",
                playPauseIntent
            )
        )

        // 3. Seek Forward (10s)
        val seekForwardIntent = PendingIntent.getBroadcast(
            this, REQUEST_SEEK_FORWARD,
            Intent(ACTION_SEEK_FORWARD).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, R.drawable.ic_pip_seek_forward),
                "Forward",
                "Seek forward 10 seconds",
                seekForwardIntent
            )
        )

        return actions
    }

    private fun updatePipActions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
            val params = PictureInPictureParams.Builder()
                .setActions(buildPipActions())
                .build()
            setPictureInPictureParams(params)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipMethodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Notify Flutter that the user pressed home (opportunity for auto-PiP)
        pipMethodChannel?.invokeMethod("onUserLeaveHint", null)
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(pipActionReceiver)
        } catch (_: Exception) {}
    }
}
