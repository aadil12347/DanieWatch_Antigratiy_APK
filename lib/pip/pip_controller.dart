import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Singleton controller for PIP (Picture-in-Picture) mode using Android's native API.
///
/// Uses a MethodChannel to communicate with the native Android PiP implementation.
/// The video continues playing inside the same Flutter activity, which Android
/// shrinks into a mini floating window.
class PipController {
  PipController._();
  static final PipController instance = PipController._();

  static const _channel = MethodChannel('com.daniewatch.app/pip');

  bool _isInPipMode = false;
  bool get isInPipMode => _isInPipMode;

  /// Callback invoked when PiP mode changes (entering or exiting).
  void Function(bool isInPip)? onPipModeChanged;

  /// Callback invoked when the user presses home while in the video player.
  /// This can be used for auto-PiP on home press.
  VoidCallback? onUserLeaveHint;

  /// Initialize the PiP controller and set up method channel listeners.
  Future<void> init() async {
    _channel.setMethodCallHandler(_handleMethodCall);
    debugPrint('[PIP] Controller initialized with native Android PiP');
  }

  /// Handle method calls from the native side.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipChanged':
        final bool isInPip = call.arguments as bool;
        _isInPipMode = isInPip;
        debugPrint('[PIP] Mode changed: $isInPip');
        onPipModeChanged?.call(isInPip);
        break;
      case 'onUserLeaveHint':
        debugPrint('[PIP] User leave hint received');
        onUserLeaveHint?.call();
        break;
    }
  }

  /// Enter PiP mode. The current activity will shrink into a mini floating window.
  /// The video WebView continues playing inside the window.
  ///
  /// [aspectWidth] and [aspectHeight] control the PiP window aspect ratio.
  /// Default is 16:9 for video content.
  Future<bool> enterPipMode({
    int aspectWidth = 16,
    int aspectHeight = 9,
  }) async {
    if (_isInPipMode) {
      debugPrint('[PIP] Already in PiP mode');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('enterPipMode', {
        'aspectWidth': aspectWidth,
        'aspectHeight': aspectHeight,
      });
      debugPrint('[PIP] enterPipMode result: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[PIP] Failed to enter PiP: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[PIP] Unexpected error entering PiP: $e');
      return false;
    }
  }

  /// Check if PiP mode is supported on this device.
  Future<bool> isPipSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPipSupported');
      return result ?? false;
    } catch (e) {
      debugPrint('[PIP] Error checking PiP support: $e');
      return false;
    }
  }

  /// Check current PiP state from the native side.
  Future<bool> checkPipState() async {
    try {
      final result = await _channel.invokeMethod<bool>('isInPipMode');
      _isInPipMode = result ?? false;
      return _isInPipMode;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    onPipModeChanged = null;
    onUserLeaveHint = null;
  }
}
