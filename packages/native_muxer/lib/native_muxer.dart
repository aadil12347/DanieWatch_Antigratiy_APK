import 'package:flutter/services.dart';

/// Native Android muxer for TS→MP4 conversion with progress reporting.
class NativeMuxer {
  static const MethodChannel _channel =
      MethodChannel('com.daniewatch.app/native_muxer');

  /// Progress callback: phase, progress(0-1), method, elapsedMs
  static Function(String phase, double progress, String method, int elapsedMs)?
      onMuxProgress;

  static Future<String> muxToMp4({
    required String segmentDir,
    required String outputPath,
  }) async {
    // Listen for progress from native side
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onMuxProgress') {
        final args = call.arguments as Map;
        onMuxProgress?.call(
          args['phase'] as String,
          (args['progress'] as num).toDouble(),
          args['method'] as String,
          (args['elapsedMs'] as num).toInt(),
        );
      }
    });

    final result = await _channel.invokeMethod<String>('muxToMp4', {
      'segmentDir': segmentDir,
      'outputPath': outputPath,
    });

    _channel.setMethodCallHandler(null);

    if (result == null) {
      throw PlatformException(
        code: 'MUX_FAILED',
        message: 'Native muxer returned null',
      );
    }

    return result;
  }
}
