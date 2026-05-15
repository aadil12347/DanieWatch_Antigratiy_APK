package com.daniewatch.native_muxer

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * Uses Android's native MediaExtractor + MediaMuxer to convert
 * HLS TS/fMP4 segments into a single MP4 file.
 *
 * Includes manual SPS/PPS extraction for H.264 streams in TS containers,
 * since MediaExtractor often fails to populate csd-0/csd-1 from MPEG-TS.
 */
class MediaMuxerHelper {
    companion object {
        private const val TAG = "MediaMuxerHelper"
        private const val BUFFER_SIZE = 1024 * 1024 // 1MB read buffer

        // H.264 NAL unit types
        private const val NAL_TYPE_SPS = 7
        private const val NAL_TYPE_PPS = 8
        private const val NAL_TYPE_IDR = 5
    }

    fun muxSegmentsToMp4(segmentDir: String, outputPath: String): String {
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

        // Step 1: Binary-concat segments into continuous stream files
        val videoExt = File(videoMedia.first()).extension
        val videoCombined = File(segmentDir, "_video_combined.$videoExt").absolutePath
        binaryConcat(videoInits + videoMedia, videoCombined)
        Log.d(TAG, "Video combined: ${File(videoCombined).length() / (1024*1024)} MB")

        var audioCombined: String? = null
        if (hasSeparateAudio) {
            val audioExt = File(audioMedia.first()).extension
            audioCombined = File(segmentDir, "_audio_combined.$audioExt").absolutePath
            binaryConcat(audioInits + audioMedia, audioCombined)
            Log.d(TAG, "Audio combined: ${File(audioCombined).length() / (1024*1024)} MB")
        }

        // Step 2: Use MediaExtractor + MediaMuxer to create MP4
        try {
            muxWithMediaApis(videoCombined, audioCombined, outputPath)
        } finally {
            safeDelete(videoCombined)
            if (audioCombined != null) safeDelete(audioCombined)
        }

        val outputFile = File(outputPath)
        if (!outputFile.exists() || outputFile.length() < 100 * 1024) {
            throw Exception("Output MP4 is too small or missing (${outputFile.length()} bytes)")
        }

        Log.d(TAG, "✅ MP4 created: ${outputFile.length() / (1024 * 1024)} MB")
        return outputPath
    }

    private fun muxWithMediaApis(
        videoPath: String,
        audioPath: String?,
        outputPath: String
    ) {
        safeDelete(outputPath)

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val videoExtractor = MediaExtractor()
        var audioExtractor: MediaExtractor? = null

        try {
            // ── Extract video track ──
            videoExtractor.setDataSource(videoPath)
            val videoTrackIndex = findTrack(videoExtractor, "video/")
            if (videoTrackIndex < 0) {
                throw Exception("No video track found in combined video file")
            }
            videoExtractor.selectTrack(videoTrackIndex)
            val videoFormat = videoExtractor.getTrackFormat(videoTrackIndex)
            Log.d(TAG, "Video track: ${videoFormat.getString(MediaFormat.KEY_MIME)}")

            // Check if CSD (codec specific data) is present
            val hasCsd = videoFormat.containsKey("csd-0")
            Log.d(TAG, "Video format has csd-0: $hasCsd")

            if (!hasCsd) {
                // Read first keyframe to extract SPS/PPS NAL units
                Log.d(TAG, "Extracting SPS/PPS from bitstream...")
                injectCodecConfig(videoExtractor, videoFormat)
            }

            val muxerVideoTrack = muxer.addTrack(videoFormat)

            // ── Extract audio track ──
            var muxerAudioTrack = -1
            if (audioPath != null) {
                audioExtractor = MediaExtractor()
                audioExtractor.setDataSource(audioPath)
                val audioTrackIndex = findTrack(audioExtractor, "audio/")
                if (audioTrackIndex >= 0) {
                    audioExtractor.selectTrack(audioTrackIndex)
                    val audioFormat = audioExtractor.getTrackFormat(audioTrackIndex)
                    muxerAudioTrack = muxer.addTrack(audioFormat)
                    Log.d(TAG, "Audio track: ${audioFormat.getString(MediaFormat.KEY_MIME)}")
                }
            } else {
                val audioTrackIndex = findTrack(videoExtractor, "audio/")
                if (audioTrackIndex >= 0) {
                    audioExtractor = MediaExtractor()
                    audioExtractor.setDataSource(videoPath)
                    audioExtractor.selectTrack(audioTrackIndex)
                    val audioFormat = audioExtractor.getTrackFormat(audioTrackIndex)
                    muxerAudioTrack = muxer.addTrack(audioFormat)
                    Log.d(TAG, "Audio track (muxed): ${audioFormat.getString(MediaFormat.KEY_MIME)}")
                }
            }

            // ── Start muxing ──
            muxer.start()

            val buffer = ByteBuffer.allocate(BUFFER_SIZE)
            val bufferInfo = MediaCodec.BufferInfo()

            val videoSamples = writeSamples(videoExtractor, muxer, muxerVideoTrack, buffer, bufferInfo)
            Log.d(TAG, "Wrote $videoSamples video samples")

            if (audioExtractor != null && muxerAudioTrack >= 0) {
                val audioSamples = writeSamples(audioExtractor, muxer, muxerAudioTrack, buffer, bufferInfo)
                Log.d(TAG, "Wrote $audioSamples audio samples")
            }

            try {
                muxer.stop()
                Log.d(TAG, "Muxer stopped successfully")
            } catch (e: Exception) {
                Log.w(TAG, "MediaMuxer.stop() threw (often benign): ${e.message}")
            }
        } finally {
            try { videoExtractor.release() } catch (_: Exception) {}
            try { audioExtractor?.release() } catch (_: Exception) {}
            try { muxer.release() } catch (_: Exception) {}
        }
    }

    /**
     * Extract SPS and PPS NAL units from the H.264 bitstream and inject
     * them into the MediaFormat as csd-0 (SPS) and csd-1 (PPS).
     *
     * MediaExtractor for TS streams often fails to populate these,
     * causing MPEG4Writer to report "Missing codec specific data".
     */
    private fun injectCodecConfig(extractor: MediaExtractor, format: MediaFormat) {
        // Read the first few samples to find SPS/PPS
        val tempBuffer = ByteBuffer.allocate(BUFFER_SIZE)
        var sps: ByteArray? = null
        var pps: ByteArray? = null

        // Try reading up to 30 samples to find SPS/PPS
        for (i in 0 until 30) {
            tempBuffer.clear()
            val size = extractor.readSampleData(tempBuffer, 0)
            if (size < 0) break

            val data = ByteArray(size)
            tempBuffer.position(0)
            tempBuffer.get(data, 0, size)

            // Parse NAL units from this sample
            val nalUnits = parseNalUnits(data)
            for (nal in nalUnits) {
                val nalType = nal[0].toInt() and 0x1F
                when (nalType) {
                    NAL_TYPE_SPS -> {
                        sps = nal
                        Log.d(TAG, "Found SPS: ${nal.size} bytes")
                    }
                    NAL_TYPE_PPS -> {
                        pps = nal
                        Log.d(TAG, "Found PPS: ${nal.size} bytes")
                    }
                }
            }

            if (sps != null && pps != null) break
            extractor.advance()
        }

        // Seek back to the beginning
        extractor.seekTo(0, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

        if (sps != null) {
            // csd-0: start code (00 00 00 01) + SPS
            val csd0 = ByteBuffer.allocate(4 + sps.size)
            csd0.put(byteArrayOf(0x00, 0x00, 0x00, 0x01))
            csd0.put(sps)
            csd0.flip()
            format.setByteBuffer("csd-0", csd0)
            Log.d(TAG, "Injected csd-0 (SPS): ${4 + sps.size} bytes")
        }

        if (pps != null) {
            // csd-1: start code (00 00 00 01) + PPS
            val csd1 = ByteBuffer.allocate(4 + pps.size)
            csd1.put(byteArrayOf(0x00, 0x00, 0x00, 0x01))
            csd1.put(pps)
            csd1.flip()
            format.setByteBuffer("csd-1", csd1)
            Log.d(TAG, "Injected csd-1 (PPS): ${4 + pps.size} bytes")
        }

        if (sps == null || pps == null) {
            Log.w(TAG, "Could not find SPS/PPS in bitstream (sps=${sps != null}, pps=${pps != null})")
        }
    }

    /**
     * Parse H.264 NAL units from a buffer.
     * Handles both Annex-B (start codes: 00 00 00 01 or 00 00 01)
     * and AVCC (4-byte length prefix) formats.
     */
    private fun parseNalUnits(data: ByteArray): List<ByteArray> {
        val nalUnits = mutableListOf<ByteArray>()

        // Try Annex-B format first (start code based)
        val startCodePositions = mutableListOf<Int>()
        var i = 0
        while (i < data.size - 3) {
            if (data[i] == 0x00.toByte() && data[i+1] == 0x00.toByte()) {
                if (data[i+2] == 0x01.toByte()) {
                    startCodePositions.add(i + 3)
                    i += 3
                    continue
                } else if (i < data.size - 4 && data[i+2] == 0x00.toByte() && data[i+3] == 0x01.toByte()) {
                    startCodePositions.add(i + 4)
                    i += 4
                    continue
                }
            }
            i++
        }

        if (startCodePositions.isNotEmpty()) {
            // Annex-B format
            for (j in startCodePositions.indices) {
                val start = startCodePositions[j]
                val end = if (j + 1 < startCodePositions.size) {
                    // Find start of next start code
                    var sc = startCodePositions[j + 1]
                    // Go back past the start code
                    if (sc >= 4 && data[sc-4] == 0x00.toByte() && data[sc-3] == 0x00.toByte()
                        && data[sc-2] == 0x00.toByte() && data[sc-1] == 0x01.toByte()) {
                        sc - 4
                    } else if (sc >= 3 && data[sc-3] == 0x00.toByte() && data[sc-2] == 0x00.toByte()
                        && data[sc-1] == 0x01.toByte()) {
                        sc - 3
                    } else {
                        sc
                    }
                } else {
                    data.size
                }
                if (end > start) {
                    nalUnits.add(data.copyOfRange(start, end))
                }
            }
        } else {
            // Try AVCC format (4-byte length prefix)
            var pos = 0
            while (pos + 4 < data.size) {
                val nalLen = ((data[pos].toInt() and 0xFF) shl 24) or
                        ((data[pos+1].toInt() and 0xFF) shl 16) or
                        ((data[pos+2].toInt() and 0xFF) shl 8) or
                        (data[pos+3].toInt() and 0xFF)
                pos += 4
                if (nalLen > 0 && pos + nalLen <= data.size) {
                    nalUnits.add(data.copyOfRange(pos, pos + nalLen))
                    pos += nalLen
                } else {
                    break
                }
            }
        }

        return nalUnits
    }

    private fun findTrack(extractor: MediaExtractor, mimePrefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(mimePrefix)) {
                return i
            }
        }
        return -1
    }

    private fun writeSamples(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        trackIndex: Int,
        buffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ): Long {
        var sampleCount = 0L
        while (true) {
            buffer.clear()
            val sampleSize = extractor.readSampleData(buffer, 0)
            if (sampleSize < 0) break

            bufferInfo.offset = 0
            bufferInfo.size = sampleSize
            bufferInfo.presentationTimeUs = extractor.sampleTime
            bufferInfo.flags = extractor.sampleFlags

            muxer.writeSampleData(trackIndex, buffer, bufferInfo)
            sampleCount++
            extractor.advance()
        }
        return sampleCount
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
