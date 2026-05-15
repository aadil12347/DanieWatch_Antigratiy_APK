package com.daniewatch.native_muxer

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Uses ExoPlayer Transformer (media3) to convert HLS TS/fMP4 segments
 * into a properly muxed MP4 file.
 *
 * Transformer handles TS demuxing, codec config extraction (SPS/PPS),
 * and MP4 muxing automatically with hardware acceleration.
 */
@OptIn(UnstableApi::class)
class TransformerMuxer(private val context: Context) {
    companion object {
        private const val TAG = "TransformerMuxer"
        private const val TIMEOUT_SECONDS = 600L // 10 minutes max
    }

    /**
     * Binary-concat segments then use Transformer to convert to MP4.
     * This method is called from a background thread.
     * The result is delivered asynchronously via the MethodChannel.Result.
     */
    fun muxSegmentsToMp4(
        segmentDir: String,
        outputPath: String,
        result: MethodChannel.Result,
        mainHandler: Handler
    ) {
        val dir = File(segmentDir)
        if (!dir.exists() || !dir.isDirectory) {
            throw Exception("Segment directory not found: $segmentDir")
        }

        val files = dir.listFiles() ?: throw Exception("Cannot list segment directory")
        val fileNames = files.filter { it.isFile && it.length() > 0 }
            .map { it.name }
            .sorted()

        val videoInits = mutableListOf<String>()
        val videoMedia = mutableListOf<String>()
        val audioInits = mutableListOf<String>()
        val audioMedia = mutableListOf<String>()

        for (name in fileNames) {
            when {
                name.startsWith("v_init_") -> videoInits.add(File(segmentDir, name).absolutePath)
                name.startsWith("v_seg_") -> videoMedia.add(File(segmentDir, name).absolutePath)
                name.startsWith("a_init_") -> audioInits.add(File(segmentDir, name).absolutePath)
                name.startsWith("a_seg_") -> audioMedia.add(File(segmentDir, name).absolutePath)
            }
        }

        if (videoMedia.isEmpty()) {
            throw Exception("No video segments found in $segmentDir")
        }

        val hasSeparateAudio = audioMedia.isNotEmpty()
        Log.d(TAG, "Muxing: ${videoMedia.size} video + ${audioMedia.size} audio segments")

        // Binary-concat segments into continuous stream files
        val videoCombined = File(segmentDir, "_video_combined.ts").absolutePath
        binaryConcat(videoInits + videoMedia, videoCombined)
        Log.d(TAG, "Video combined: ${File(videoCombined).length() / (1024*1024)} MB")

        var audioCombined: String? = null
        if (hasSeparateAudio) {
            audioCombined = File(segmentDir, "_audio_combined.ts").absolutePath
            binaryConcat(audioInits + audioMedia, audioCombined)
            Log.d(TAG, "Audio combined: ${File(audioCombined).length() / (1024*1024)} MB")
        }

        // Delete any previous output
        safeDelete(outputPath)

        // Use Transformer on main thread (required by ExoPlayer)
        val latch = CountDownLatch(1)
        var transformError: Exception? = null

        mainHandler.post {
            try {
                val listener = object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Log.d(TAG, "✅ Transformer completed successfully")
                        latch.countDown()
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        Log.e(TAG, "Transformer error: ${exportException.message}", exportException)
                        transformError = exportException
                        latch.countDown()
                    }
                }

                val transformer = Transformer.Builder(context)
                    .addListener(listener)
                    .build()

                if (hasSeparateAudio && audioCombined != null) {
                    // Separate video + audio: use Composition to merge
                    val videoItem = EditedMediaItem.Builder(
                        MediaItem.fromUri(Uri.fromFile(File(videoCombined)))
                    ).setRemoveAudio(true).build()

                    val audioItem = EditedMediaItem.Builder(
                        MediaItem.fromUri(Uri.fromFile(File(audioCombined)))
                    ).setRemoveVideo(true).build()

                    val composition = Composition.Builder(
                        EditedMediaItemSequence(videoItem),
                        EditedMediaItemSequence(audioItem)
                    ).setTransmuxVideo(true)
                     .setTransmuxAudio(true)
                     .build()

                    Log.d(TAG, "Starting Transformer with Composition (separate A+V)...")
                    transformer.start(composition, outputPath)
                } else {
                    // Muxed audio+video: single input
                    val mediaItem = MediaItem.fromUri(Uri.fromFile(File(videoCombined)))
                    val editedItem = EditedMediaItem.Builder(mediaItem).build()
                    val composition = Composition.Builder(
                        EditedMediaItemSequence(editedItem)
                    ).setTransmuxVideo(true)
                     .setTransmuxAudio(true)
                     .build()

                    Log.d(TAG, "Starting Transformer with single input...")
                    transformer.start(composition, outputPath)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start Transformer: ${e.message}", e)
                transformError = e
                latch.countDown()
            }
        }

        // Wait for Transformer to finish
        val completed = latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)

        // Cleanup temp files
        safeDelete(videoCombined)
        if (audioCombined != null) safeDelete(audioCombined)

        if (!completed) {
            mainHandler.post {
                result.error("MUX_ERROR", "Transformer timed out after ${TIMEOUT_SECONDS}s", null)
            }
            return
        }

        if (transformError != null) {
            mainHandler.post {
                result.error("MUX_ERROR", transformError!!.message ?: "Transformer failed", null)
            }
            return
        }

        val outputFile = File(outputPath)
        if (!outputFile.exists() || outputFile.length() < 100 * 1024) {
            mainHandler.post {
                result.error("MUX_ERROR", "Output MP4 is too small or missing (${outputFile.length()} bytes)", null)
            }
            return
        }

        Log.d(TAG, "✅ MP4 created: ${outputFile.length() / (1024 * 1024)} MB")
        mainHandler.post {
            result.success(outputPath)
        }
    }

    private fun binaryConcat(inputPaths: List<String>, outputPath: String) {
        FileOutputStream(outputPath).use { out ->
            val buf = ByteArray(256 * 1024)
            for (path in inputPaths) {
                val file = File(path)
                if (!file.exists() || file.length() == 0L) continue
                FileInputStream(file).use { input ->
                    var bytesRead: Int
                    while (input.read(buf).also { bytesRead = it } != -1) {
                        out.write(buf, 0, bytesRead)
                    }
                }
            }
            out.flush()
        }
    }

    private fun safeDelete(path: String) {
        try {
            val f = File(path)
            if (f.exists()) f.delete()
        } catch (_: Exception) {}
    }
}
