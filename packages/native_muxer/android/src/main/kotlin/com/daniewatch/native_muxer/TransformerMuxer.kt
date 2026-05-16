package com.daniewatch.native_muxer

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
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
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Uses ExoPlayer Transformer for TS→MP4 conversion.
 *
 * Key design decisions for A/V sync:
 * - Video: transmux (stream-copy) — fast, no quality loss
 * - Audio: re-encode — forces Transformer to generate fresh, mathematically
 *   correct timestamps aligned to the video timeline. This fixes accumulated
 *   PTS drift between video and audio tracks across 100+ HLS segments.
 *
 * Performance optimizations:
 * - Parallel binary concat (video + audio run simultaneously)
 * - 4 MB I/O buffer (vs 512 KB) for faster disk reads/writes
 */
@OptIn(UnstableApi::class)
class TransformerMuxer(private val context: Context) {
    companion object {
        private const val TAG = "TransformerMuxer"
        private const val TIMEOUT_SECONDS = 600L
        private const val IO_BUFFER_SIZE = 4 * 1024 * 1024  // 4 MB for fast I/O
    }

    fun muxSegmentsToMp4(
        segmentDir: String,
        outputPath: String,
        result: MethodChannel.Result,
        mainHandler: Handler
    ) {
        val dir = File(segmentDir)
        if (!dir.exists() || !dir.isDirectory) throw Exception("Segment dir not found: $segmentDir")

        val files = dir.listFiles() ?: throw Exception("Cannot list segment dir")
        val fileNames = files.filter { it.isFile && it.length() > 0 }.map { it.name }.sorted()

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

        if (videoMedia.isEmpty()) throw Exception("No video segments found")

        val hasSeparateAudio = audioMedia.isNotEmpty()
        Log.d(TAG, "Muxing: ${videoMedia.size} video + ${audioMedia.size} audio segments")

        // ── Parallel binary-concat: video + audio run simultaneously ──
        val videoCombined = File(segmentDir, "_video_combined.ts").absolutePath
        var audioCombined: String? = null

        if (hasSeparateAudio) {
            audioCombined = File(segmentDir, "_audio_combined.ts").absolutePath
            val concatExecutor = Executors.newFixedThreadPool(2)

            val videoFuture = concatExecutor.submit {
                binaryConcat(videoInits + videoMedia, videoCombined)
                Log.d(TAG, "Video combined: ${File(videoCombined).length() / (1024 * 1024)} MB")
            }
            val audioFuture = concatExecutor.submit {
                binaryConcat(audioInits + audioMedia, audioCombined!!)
                Log.d(TAG, "Audio combined: ${File(audioCombined!!).length() / (1024 * 1024)} MB")
            }

            // Wait for both to finish
            videoFuture.get()
            audioFuture.get()
            concatExecutor.shutdown()
        } else {
            // No separate audio — just concat video
            binaryConcat(videoInits + videoMedia, videoCombined)
            Log.d(TAG, "Video combined: ${File(videoCombined).length() / (1024 * 1024)} MB")
        }

        // Delete previous output
        File(outputPath).let { if (it.exists()) it.delete() }

        // Run Transformer on main thread (required by ExoPlayer)
        val latch = CountDownLatch(1)
        var transformError: Exception? = null

        mainHandler.post {
            try {
                val listener = object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Log.d(TAG, "✅ Transformer completed")
                        latch.countDown()
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        Log.e(TAG, "Transformer error: ${exportException.message}", exportException)
                        transformError = exportException
                        latch.countDown()
                    }
                }

                // ── Transformer with desync fix ──
                // setMaxDelayBetweenMuxerSamplesMs: prevents stalls on timestamp gaps
                val transformer = Transformer.Builder(context)
                    .setMaxDelayBetweenMuxerSamplesMs(C.TIME_UNSET)
                    .addListener(listener)
                    .build()

                if (hasSeparateAudio && audioCombined != null) {
                    val videoItem = EditedMediaItem.Builder(
                        MediaItem.fromUri(Uri.fromFile(File(videoCombined)))
                    ).setRemoveAudio(true).build()

                    val audioItem = EditedMediaItem.Builder(
                        MediaItem.fromUri(Uri.fromFile(File(audioCombined)))
                    ).setRemoveVideo(true).build()

                    // ── DESYNC FIX ──
                    // setTransmuxVideo(true)  = stream-copy video (fast, no quality loss)
                    // setTransmuxAudio(false) = RE-ENCODE audio with fresh timestamps
                    //
                    // Why this fixes desync:
                    // Each HLS segment has slightly different audio vs video duration
                    // (e.g., 6.006s video, 5.994s audio). Over 100+ segments this
                    // accumulates to 1-2 seconds of drift. By re-encoding audio,
                    // Transformer generates mathematically correct timestamps from
                    // the decoded sample count (sample_number / sample_rate = exact time),
                    // eliminating all accumulated drift.
                    val composition = Composition.Builder(
                        EditedMediaItemSequence(videoItem),
                        EditedMediaItemSequence(audioItem)
                    ).setTransmuxVideo(true)
                     .setTransmuxAudio(false)  // RE-ENCODE audio for perfect sync
                     .build()

                    Log.d(TAG, "Starting Transformer (separate A+V, audio re-encode for sync)...")
                    transformer.start(composition, outputPath)
                } else {
                    // Single input (video+audio already muxed in TS)
                    val mediaItem = MediaItem.fromUri(Uri.fromFile(File(videoCombined)))
                    val editedItem = EditedMediaItem.Builder(mediaItem).build()
                    val composition = Composition.Builder(
                        EditedMediaItemSequence(editedItem)
                    ).setTransmuxVideo(true)
                     .setTransmuxAudio(false)  // RE-ENCODE audio for sync safety
                     .build()

                    Log.d(TAG, "Starting Transformer (single input, audio re-encode)...")
                    transformer.start(composition, outputPath)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start Transformer: ${e.message}", e)
                transformError = e
                latch.countDown()
            }
        }

        // Wait for completion
        val completed = latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)

        // Cleanup temp files
        File(videoCombined).let { if (it.exists()) it.delete() }
        if (audioCombined != null) File(audioCombined).let { if (it.exists()) it.delete() }

        if (!completed) {
            mainHandler.post { result.error("MUX_ERROR", "Transformer timed out", null) }
            return
        }
        if (transformError != null) {
            mainHandler.post { result.error("MUX_ERROR", transformError!!.message ?: "Transformer failed", null) }
            return
        }

        val outputFile = File(outputPath)
        if (!outputFile.exists() || outputFile.length() < 100 * 1024) {
            mainHandler.post { result.error("MUX_ERROR", "Output too small (${outputFile.length()} bytes)", null) }
            return
        }

        Log.d(TAG, "✅ MP4 created: ${outputFile.length() / (1024 * 1024)} MB")
        mainHandler.post { result.success(outputPath) }
    }

    private fun binaryConcat(inputPaths: List<String>, outputPath: String) {
        FileOutputStream(outputPath).use { out ->
            val buf = ByteArray(IO_BUFFER_SIZE)  // 4 MB buffer for fast I/O
            for (path in inputPaths) {
                val file = File(path)
                if (!file.exists() || file.length() == 0L) continue
                FileInputStream(file).use { input ->
                    var n: Int; while (input.read(buf).also { n = it } != -1) out.write(buf, 0, n)
                }
            }
            out.flush()
        }
    }
}
