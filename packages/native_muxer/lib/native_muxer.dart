import 'package:flutter/services.dart';

/// Native Android MediaMuxer wrapper for TS→MP4 conversion.
///
/// Uses Android's MediaExtractor + MediaMuxer APIs for:
///  - Guaranteed A/V sync (native PTS/DTS handling)
///  - Stream-copy speed (no re-encoding)
///  - Works in both main and background isolates
class NativeMuxer {
  static const MethodChannel _channel =
      MethodChannel('com.daniewatch.app/native_muxer');

  /// Mux HLS segments from [segmentDir] into a single MP4 at [outputPath].
  ///
  /// The segment directory should contain files named:
  ///   - `v_init_*.mp4` / `v_seg_*.ts` (video)
  ///   - `a_init_*.mp4` / `a_seg_*.ts` (audio, optional)
  ///
  /// Returns the output path on success.
  /// Throws [PlatformException] on failure.
  static Future<String> muxToMp4({
    required String segmentDir,
    required String outputPath,
  }) async {
    final result = await _channel.invokeMethod<String>('muxToMp4', {
      'segmentDir': segmentDir,
      'outputPath': outputPath,
    });

    if (result == null) {
      throw PlatformException(
        code: 'MUX_FAILED',
        message: 'Native muxer returned null',
      );
    }

    return result;
  }
}
