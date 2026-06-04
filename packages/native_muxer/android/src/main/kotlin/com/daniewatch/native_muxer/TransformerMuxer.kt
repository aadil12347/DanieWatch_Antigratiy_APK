package com.daniewatch.native_muxer

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
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
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Ultra-fast TS→MP4 muxer with 3-tier fallback:
 *
 * 1. FAST: Direct MediaExtractor+MediaMuxer (stream copy, ~30-60s)
 * 2. MEDIUM: Transformer with transmuxAudio=true (stream copy, ~1-2min)
 * 3. SLOW: Transformer with transmuxAudio=false (re-encode audio, ~10-20min)
 */
@OptIn(UnstableApi::class)
class TransformerMuxer(private val context: Context) {
    companion object {
        private const val TAG = "TransformerMuxer"
        private const val TIMEOUT = 1800L // 30 min
        private const val IO_BUF = 4 * 1024 * 1024
        private const val MUX_BUF = 2 * 1024 * 1024
    }

    var onProgress: ((String, Double, String, Long) -> Unit)? = null
    private var t0 = 0L
    private fun ms() = System.currentTimeMillis() - t0
    private fun rpt(ph: String, p: Double, m: String) { onProgress?.invoke(ph, p, m, ms()) }

    fun muxSegmentsToMp4(
        segmentDir: String, outputPath: String,
        result: MethodChannel.Result, mainHandler: Handler
    ) {
        t0 = System.currentTimeMillis()
        val dir = File(segmentDir)
        if (!dir.exists() || !dir.isDirectory) throw Exception("Segment dir not found")

        val names = (dir.listFiles() ?: throw Exception("Cannot list dir"))
            .filter { it.isFile && it.length() > 0 }.map { it.name }.sorted()

        val vInit = mutableListOf<String>(); val vSeg = mutableListOf<String>()
        val aInit = mutableListOf<String>(); val aSeg = mutableListOf<String>()
        for (n in names) { when {
            n.startsWith("v_init_") -> vInit.add(File(segmentDir, n).absolutePath)
            n.startsWith("v_seg_")  -> vSeg.add(File(segmentDir, n).absolutePath)
            n.startsWith("a_init_") -> aInit.add(File(segmentDir, n).absolutePath)
            n.startsWith("a_seg_")  -> aSeg.add(File(segmentDir, n).absolutePath)
        }}
        if (vSeg.isEmpty()) throw Exception("No video segments found")
        val hasAudio = aSeg.isNotEmpty()
        Log.d(TAG, "Muxing: ${vSeg.size} video + ${aSeg.size} audio segments")

        // ── Phase 1: Parallel binary concat ──
        rpt("concat", 0.0, "preparing")
        val vFile = File(segmentDir, "_video_combined.ts").absolutePath
        var aFile: String? = null
        if (hasAudio) {
            aFile = File(segmentDir, "_audio_combined.ts").absolutePath
            val ex = Executors.newFixedThreadPool(2)
            val vf = ex.submit { binaryConcat(vInit + vSeg, vFile) }
            val af = ex.submit { binaryConcat(aInit + aSeg, aFile!!) }
            vf.get(); af.get(); ex.shutdown()
        } else {
            binaryConcat(vInit + vSeg, vFile)
        }
        rpt("concat", 1.0, "done")
        Log.d(TAG, "Concat: ${ms()}ms | V:${File(vFile).length()/(1024*1024)}MB" +
            if (aFile!=null) " A:${File(aFile).length()/(1024*1024)}MB" else "")

        File(outputPath).let { if (it.exists()) it.delete() }

        // ── Phase 2: 3-tier muxing ──
        var method = "direct_remux"
        var directError = ""

        // Tier 1: Direct remux (fastest, ~30-60s)
        try {
            rpt("muxing", 0.0, "direct_remux")
            Log.d(TAG, "⚡ Tier 1: Direct remux...")
            if (hasAudio && aFile != null) directRemuxSeparate(vFile, aFile, outputPath)
            else directRemuxSingle(vFile, outputPath)
            rpt("muxing", 1.0, "direct_remux")
            Log.d(TAG, "✅ Direct remux OK in ${ms()}ms")
        } catch (e: Exception) {
            directError = "${e.javaClass.simpleName}: ${e.message}"
            Log.w(TAG, "Tier 1 FAILED: $directError", e)
            File(outputPath).let { if (it.exists()) it.delete() }

            // Tier 2: Transformer with stream-copy audio (fast, ~1-2min)
            method = "transformer_copy"
            try {
                rpt("muxing", 0.0, "transformer_copy")
                Log.d(TAG, "⚡ Tier 2: Transformer stream-copy...")
                transformerMux(vFile, aFile, outputPath, mainHandler, hasAudio, transmuxAudio = true)
                rpt("muxing", 1.0, "transformer_copy")
                Log.d(TAG, "✅ Transformer copy OK in ${ms()}ms")
            } catch (e2: Exception) {
                Log.w(TAG, "Tier 2 FAILED: ${e2.message}", e2)
                File(outputPath).let { if (it.exists()) it.delete() }

                // Tier 3: Transformer with audio re-encode (slow but proven, ~10-20min)
                method = "transformer_reencode"
                rpt("muxing", 0.0, "transformer_reencode")
                Log.d(TAG, "🔄 Tier 3: Transformer re-encode...")
                transformerMux(vFile, aFile, outputPath, mainHandler, hasAudio, transmuxAudio = false)
                rpt("muxing", 1.0, "transformer_reencode")
                Log.d(TAG, "✅ Transformer re-encode OK in ${ms()}ms")
            }
        }

        // Cleanup
        File(vFile).let { if (it.exists()) it.delete() }
        aFile?.let { File(it).let { f -> if (f.exists()) f.delete() } }

        val out = File(outputPath)
        if (!out.exists() || out.length() < 100*1024) {
            mainHandler.post { result.error("MUX_ERROR", "Output too small (${out.length()} bytes)", null) }
            return
        }
        val totalSec = ms() / 1000
        val msg = "✅ MP4: ${out.length()/(1024*1024)}MB in ${totalSec}s ($method)" +
            if (directError.isNotEmpty()) " [direct_err: $directError]" else ""
        Log.d(TAG, msg)
        // Send method + error info to Dart for diagnostics
        rpt("complete", 1.0, "$method|$directError")
        mainHandler.post { result.success(outputPath) }
    }

    // ── Direct Remux: separate video + audio ──
    private fun directRemuxSeparate(videoPath: String, audioPath: String, outputPath: String) {
        val vEx = MediaExtractor(); val aEx = MediaExtractor()
        try {
            vEx.setDataSource(videoPath); aEx.setDataSource(audioPath)
            val vi = findTrack(vEx, "video/"); val ai = findTrack(aEx, "audio/")
            if (vi < 0) throw Exception("No video track found (tracks=${vEx.trackCount})")
            if (ai < 0) throw Exception("No audio track found (tracks=${aEx.trackCount})")
            vEx.selectTrack(vi); aEx.selectTrack(ai)
            val vFmt = vEx.getTrackFormat(vi); val aFmt = aEx.getTrackFormat(ai)
            val rate = if (aFmt.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                aFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 48000
            Log.d(TAG, "V:${vFmt.getString(MediaFormat.KEY_MIME)} A:${aFmt.getString(MediaFormat.KEY_MIME)} rate=$rate")

            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                val mv = muxer.addTrack(vFmt); val ma = muxer.addTrack(aFmt)
                muxer.start()
                val buf = ByteBuffer.allocate(MUX_BUF); val info = MediaCodec.BufferInfo()

                // Video (PTS preserved)
                var vc = 0L
                while (true) {
                    val sz = vEx.readSampleData(buf, 0); if (sz < 0) break
                    info.set(0, sz, vEx.sampleTime, vEx.sampleFlags)
                    muxer.writeSampleData(mv, buf, info); vEx.advance(); vc++
                    if (vc % 1000 == 0L) rpt("muxing", 0.1 + 0.4 * (vc.toDouble() / (vc + 1000)), "direct_remux")
                }
                rpt("muxing", 0.5, "direct_remux")

                // Audio (PTS corrected from frame count)
                var ac = 0L; val fs = 1024L
                while (true) {
                    val sz = aEx.readSampleData(buf, 0); if (sz < 0) break
                    info.set(0, sz, ac * fs * 1_000_000L / rate, aEx.sampleFlags)
                    muxer.writeSampleData(ma, buf, info); aEx.advance(); ac++
                    if (ac % 1000 == 0L) rpt("muxing", 0.5 + 0.4 * (ac.toDouble() / (ac + 1000)), "direct_remux")
                }
                Log.d(TAG, "Remuxed: $vc video + $ac audio samples")
                muxer.stop()
            } finally { muxer.release() }
        } finally { vEx.release(); aEx.release() }
    }

    // ── Direct Remux: single muxed input ──
    private fun directRemuxSingle(inputPath: String, outputPath: String) {
        val ex = MediaExtractor()
        try {
            ex.setDataSource(inputPath)
            val vi = findTrack(ex, "video/"); if (vi < 0) throw Exception("No video track")
            val ai = findTrack(ex, "audio/"); val hasA = ai >= 0
            val vFmt = ex.getTrackFormat(vi)
            val aFmt = if (hasA) ex.getTrackFormat(ai) else null
            val rate = if (hasA && aFmt!!.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                aFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 48000

            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                val mv = muxer.addTrack(vFmt)
                val ma = if (hasA) muxer.addTrack(aFmt!!) else -1
                muxer.start()
                val buf = ByteBuffer.allocate(MUX_BUF); val info = MediaCodec.BufferInfo()

                ex.selectTrack(vi)
                while (true) {
                    val sz = ex.readSampleData(buf, 0); if (sz < 0) break
                    info.set(0, sz, ex.sampleTime, ex.sampleFlags)
                    muxer.writeSampleData(mv, buf, info); ex.advance()
                }
                if (hasA) {
                    ex.unselectTrack(vi); ex.selectTrack(ai)
                    ex.seekTo(0, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                    var ac = 0L; val fs = 1024L
                    while (true) {
                        val sz = ex.readSampleData(buf, 0); if (sz < 0) break
                        info.set(0, sz, ac * fs * 1_000_000L / rate, ex.sampleFlags)
                        muxer.writeSampleData(ma, buf, info); ac++; ex.advance()
                    }
                }
                muxer.stop()
            } finally { muxer.release() }
        } finally { ex.release() }
    }

    // ── Transformer Mux (with progress polling) ──
    private fun transformerMux(
        vPath: String, aPath: String?, outPath: String, handler: Handler,
        hasAudio: Boolean, transmuxAudio: Boolean
    ) {
        val latch = CountDownLatch(1); var err: Exception? = null
        var transformer: Transformer? = null
        val methodName = if (transmuxAudio) "transformer_copy" else "transformer_reencode"

        handler.post {
            try {
                val listener = object : Transformer.Listener {
                    override fun onCompleted(c: Composition, r: ExportResult) {
                        Log.d(TAG, "✅ $methodName done"); latch.countDown()
                    }
                    override fun onError(c: Composition, r: ExportResult, e: ExportException) {
                        Log.e(TAG, "$methodName error: ${e.message}", e); err = e; latch.countDown()
                    }
                }
                val t = Transformer.Builder(context)
                    .setMaxDelayBetweenMuxerSamplesMs(C.TIME_UNSET)
                    .addListener(listener).build()
                transformer = t

                if (hasAudio && aPath != null) {
                    val vi = EditedMediaItem.Builder(
                        MediaItem.fromUri(Uri.fromFile(File(vPath)))
                    ).setRemoveAudio(true).build()
                    val ai = EditedMediaItem.Builder(
                        MediaItem.fromUri(Uri.fromFile(File(aPath)))
                    ).setRemoveVideo(true).build()
                    val comp = Composition.Builder(
                        EditedMediaItemSequence(vi), EditedMediaItemSequence(ai)
                    ).setTransmuxVideo(true).setTransmuxAudio(transmuxAudio).build()
                    t.start(comp, outPath)
                } else {
                    val mi = MediaItem.fromUri(Uri.fromFile(File(vPath)))
                    val ei = EditedMediaItem.Builder(mi).build()
                    val comp = Composition.Builder(
                        EditedMediaItemSequence(ei)
                    ).setTransmuxVideo(true).setTransmuxAudio(transmuxAudio).build()
                    t.start(comp, outPath)
                }
            } catch (e: Exception) { err = e; latch.countDown() }
        }

        // Poll progress every 2 seconds
        val progressHolder = ProgressHolder()
        while (!latch.await(2, TimeUnit.SECONDS)) {
            try {
                val t = transformer
                if (t != null) {
                    handler.post {
                        try {
                            val state = t.getProgress(progressHolder)
                            if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                                val p = progressHolder.progress.toDouble() / 100.0
                                rpt("muxing", p.coerceIn(0.0, 1.0), methodName)
                            }
                        } catch (_: Exception) {}
                    }
                }
            } catch (_: Exception) {}
        }

        if (err != null) throw err!!
    }

    private fun findTrack(ex: MediaExtractor, prefix: String): Int {
        for (i in 0 until ex.trackCount) {
            val m = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
            if (m?.startsWith(prefix) == true) return i
        }; return -1
    }

    private fun binaryConcat(paths: List<String>, out: String) {
        FileOutputStream(out).use { os ->
            val buf = ByteArray(IO_BUF)
            for ((i, p) in paths.withIndex()) {
                val f = File(p); if (!f.exists() || f.length() == 0L) continue
                FileInputStream(f).use { inp ->
                    var n: Int; while (inp.read(buf).also { n = it } != -1) os.write(buf, 0, n)
                }
                if (i % 20 == 0) rpt("concat", i.toDouble() / paths.size, "concat")
            }; os.flush()
        }
    }
}
