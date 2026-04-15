import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:floaty_chatheads/floaty_chatheads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton controller for PIP (Picture-in-Picture) mode lifecycle.
///
/// Manages launching/closing the floating overlay, passing video data
/// to the overlay engine, and handling "restore in app" events.
class PipController {
  PipController._();
  static final PipController instance = PipController._();

  bool _isInPipMode = false;
  bool get isInPipMode => _isInPipMode;

  StreamSubscription? _dataSubscription;

  /// Callback invoked when the user taps "Open in App" in the PIP overlay.
  /// Receives a Map with: {url, position, title, tmdbId, mediaType, season, episode, originalUrl}
  void Function(Map<String, dynamic>)? onRestoreRequested;

  /// Enter PIP mode with the given video data.
  ///
  /// Steps:
  /// 1. Check/request SYSTEM_ALERT_WINDOW permission
  /// 2. Save restore data to SharedPreferences (backup)
  /// 3. Launch the floating overlay via floaty_chatheads
  /// 4. Send video data to the overlay
  Future<bool> enterPipMode({
    required String videoUrl,
    required double currentPosition,
    required String title,
    required int tmdbId,
    required String mediaType,
    String? originalUrl,
    int? season,
    int? episode,
  }) async {
    if (_isInPipMode) {
      debugPrint('[PIP] Already in PIP mode');
      return false;
    }

    // 1. Check permission
    final granted = await FloatyChatheads.checkPermission();
    if (!granted) {
      await FloatyChatheads.requestPermission();
      // Re-check after user returns from settings
      final nowGranted = await FloatyChatheads.checkPermission();
      if (!nowGranted) {
        debugPrint('[PIP] Permission denied by user');
        return false;
      }
    }

    // 2. Save restore data to SharedPreferences as backup
    final restoreData = {
      'url': videoUrl,
      'position': currentPosition,
      'title': title,
      'tmdbId': tmdbId,
      'mediaType': mediaType,
      'originalUrl': originalUrl,
      'season': season,
      'episode': episode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pip_restore_data', jsonEncode(restoreData));
    } catch (e) {
      debugPrint('[PIP] Failed to save restore data: $e');
    }

    // 3. Listen for data from overlay
    _dataSubscription?.cancel();
    _dataSubscription = FloatyChatheads.onData.listen((data) {
      debugPrint('[PIP] Received data from overlay: $data');
      if (data is Map) {
        final action = data['action'];
        if (action == 'restore') {
          _handleRestore(data);
        } else if (action == 'close') {
          _handleClose();
        }
      }
    });

    // 4. Launch the floating overlay
    try {
      await FloatyChatheads.showChatHead(
        entryPoint: 'pipOverlayMain',
        iconWidget: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF111111),
            border: Border.all(color: const Color(0xFFE11D48), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE11D48).withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
          ),
        ),
        notification: const NotificationConfig(
          title: 'DanieWatch PIP',
        ),
        sizePreset: ContentSizePreset.card,
      );

      _isInPipMode = true;

      // 5. Send video data to the overlay after a brief delay to let it initialize
      await Future.delayed(const Duration(milliseconds: 800));
      await FloatyChatheads.shareData(restoreData);
      debugPrint('[PIP] Entered PIP mode with: $title @ ${currentPosition}s');

      return true;
    } catch (e) {
      debugPrint('[PIP] Failed to launch overlay: $e');
      _isInPipMode = false;
      return false;
    }
  }

  /// Programmatically exit PIP mode.
  Future<void> exitPipMode() async {
    if (!_isInPipMode) return;
    try {
      await FloatyChatheads.closeChatHead();
    } catch (e) {
      debugPrint('[PIP] Error closing overlay: $e');
    }
    _handleClose();
  }

  void _handleRestore(Map data) {
    debugPrint('[PIP] Restore requested with position: ${data['position']}');
    _isInPipMode = false;
    _dataSubscription?.cancel();
    _dataSubscription = null;

    // Close the overlay
    try {
      FloatyChatheads.closeChatHead();
    } catch (e) {
      debugPrint('[PIP] Error closing overlay on restore: $e');
    }

    // Invoke restore callback with full data
    if (onRestoreRequested != null) {
      final restoreInfo = {
        'url': data['url'] ?? '',
        'position': (data['position'] as num?)?.toDouble() ?? 0.0,
        'title': data['title'] ?? '',
        'tmdbId': data['tmdbId'] ?? 0,
        'mediaType': data['mediaType'] ?? 'movie',
        'originalUrl': data['originalUrl'],
        'season': data['season'],
        'episode': data['episode'],
      };
      onRestoreRequested!(restoreInfo);
    }

    _clearSavedData();
  }

  void _handleClose() {
    debugPrint('[PIP] PIP closed');
    _isInPipMode = false;
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _clearSavedData();
  }

  Future<void> _clearSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pip_restore_data');
    } catch (e) {
      debugPrint('[PIP] Failed to clear restore data: $e');
    }
  }

  /// Check if there's pending PIP restore data (for cold start recovery).
  Future<Map<String, dynamic>?> getPendingRestoreData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('pip_restore_data');
      if (json != null) {
        return jsonDecode(json) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[PIP] Failed to read restore data: $e');
    }
    return null;
  }

  Future<void> init() async {
    // Initialization block if needed for cold-starts
    final data = await getPendingRestoreData();
    if (data != null) {
      debugPrint('[PIP] Found pending restore data from previous crash/close: $data');
      // Could auto-restore here, but for now we just clear it or handle it in home screen
    }
  }

  void dispose() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
  }
}
