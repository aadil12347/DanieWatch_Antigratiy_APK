package com.daniewatch.native_muxer

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

class NativeMuxerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.daniewatch.app/native_muxer")
        channel.setMethodCallHandler(this)
        appContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "muxToMp4" -> {
                val segmentDir = call.argument<String>("segmentDir")
                val outputPath = call.argument<String>("outputPath")

                if (segmentDir == null || outputPath == null) {
                    result.error("INVALID_ARGS", "segmentDir and outputPath are required", null)
                    return
                }

                // Binary-concat on background thread, then Transformer on main thread
                executor.execute {
                    try {
                        val helper = TransformerMuxer(appContext)
                        helper.muxSegmentsToMp4(segmentDir, outputPath, result, mainHandler)
                    } catch (e: Exception) {
                        Log.e("NativeMuxerPlugin", "Muxing failed: ${e.message}", e)
                        mainHandler.post {
                            result.error("MUX_ERROR", e.message ?: "Unknown muxing error", null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
