/// Utility to convert raw technical exceptions into clean,
/// user-friendly error messages suitable for UI display and
/// notification text.
///
/// Usage:
///   final clean = ErrorSanitizer.sanitize(e);
///   final clean = ErrorSanitizer.sanitize(e.toString());
class ErrorSanitizer {
  ErrorSanitizer._(); // no instances

  /// Convert any exception / error string into a short,
  /// professional message the user can understand.
  static String sanitize(dynamic error) {
    final raw = (error ?? '').toString().toLowerCase();

    // ── Network / Connectivity ───────────────────────────
    if (_matchesAny(raw, [
      'socketexception',
      'connection refused',
      'connection reset',
      'connection closed',
      'network is unreachable',
      'failed host lookup',
      'no address associated',
      'no internet',
    ])) {
      return 'No internet connection. Please check your network and try again.';
    }

    if (_matchesAny(raw, [
      'connection timed out',
      'connecttimeout',
      'connectiontimeout',
      'connect_timeout',
    ])) {
      return 'Connection timed out. The server took too long to respond.';
    }

    if (_matchesAny(raw, [
      'receive timeout',
      'receivetimeout',
      'receive_timeout',
      'send timeout',
      'sendtimeout',
    ])) {
      return 'Transfer timed out. Please try again on a faster connection.';
    }

    // ── HTTP Status Codes ────────────────────────────────
    if (_matchesAny(raw, ['status code: 404', 'statuscode: 404', '404 not found', 'status code of 404'])) {
      return 'Content not found. The link may have expired.';
    }

    if (_matchesAny(raw, ['status code: 403', 'statuscode: 403', '403 forbidden', 'status code of 403'])) {
      return 'Access denied. The link may have expired.';
    }

    if (_matchesAny(raw, ['status code: 500', 'statuscode: 500', '500 internal', 'status code of 500'])) {
      return 'Server error. Please try again later.';
    }

    if (_matchesAny(raw, ['status code: 502', 'status code: 503', 'status code: 504', 'bad gateway', 'service unavailable'])) {
      return 'Server is temporarily unavailable. Please try again later.';
    }

    if (_matchesAny(raw, ['status code: 429', 'too many requests'])) {
      return 'Too many requests. Please wait a moment and try again.';
    }

    // ── DioException patterns ────────────────────────────
    if (raw.contains('dioexception')) {
      if (raw.contains('cancel')) {
        return 'Download was cancelled.';
      }
      if (raw.contains('response')) {
        return 'Server returned an unexpected response.';
      }
      return 'Network error occurred. Please try again.';
    }

    // ── SSL / Certificate ────────────────────────────────
    if (_matchesAny(raw, [
      'certificate',
      'handshake',
      'ssl',
      'tls',
      'bad_certificate',
    ])) {
      return 'Secure connection failed. Please check your network settings.';
    }

    // ── Storage / File System ────────────────────────────
    if (_matchesAny(raw, [
      'no space left',
      'disk full',
      'storage',
      'enospc',
    ])) {
      return 'Not enough storage space. Please free up some space and try again.';
    }

    if (_matchesAny(raw, [
      'permission denied',
      'permission',
      'access denied',
    ])) {
      return 'Storage permission denied. Please grant permissions in settings.';
    }

    if (_matchesAny(raw, ['file not found', 'no such file'])) {
      return 'File not found on device.';
    }

    // ── Download-specific ────────────────────────────────
    if (raw.contains('download cancelled') || raw.contains('cancelled')) {
      return 'Download was cancelled.';
    }

    if (raw.contains('no segments found')) {
      return 'Could not process video stream. Please try a different quality.';
    }

    if (raw.contains('mp4 conversion failed') || raw.contains('ffmpeg')) {
      return 'Failed to finalize video. Please try again.';
    }

    if (raw.contains('failed to save file')) {
      return 'Failed to save file. Please check your storage.';
    }

    if (_matchesAny(raw, ['failed to download', 'after 3 attempts', 'after $_maxRetries'])) {
      return 'Download failed after multiple retries. Please try again.';
    }

    // ── Extraction ───────────────────────────────────────
    if (_matchesAny(raw, ['extraction', 'extractor', 'extract'])) {
      return 'Could not extract video source. Please try again.';
    }

    // ── Generic / Fallback ───────────────────────────────
    // If the raw message is already short and clean (no stack trace),
    // pass it through.
    final cleaned = _stripTechnicalPrefix(error.toString());
    if (cleaned.length <= 80 && !cleaned.contains('\n') && !cleaned.contains('Exception')) {
      return cleaned;
    }

    return 'Something went wrong. Please try again.';
  }

  static const int _maxRetries = 3;

  static bool _matchesAny(String haystack, List<String> needles) {
    return needles.any((n) => haystack.contains(n));
  }

  /// Strip common Dart exception prefixes like "Exception: ", "DioException [...]:"
  static String _stripTechnicalPrefix(String raw) {
    String cleaned = raw;

    // Remove "Exception: " prefix
    cleaned = cleaned.replaceAll(RegExp(r'^Exception:\s*', caseSensitive: false), '');

    // Remove "DioException [...]: " prefix
    cleaned = cleaned.replaceAll(RegExp(r'^DioException\s*\[.*?\]:\s*', caseSensitive: false), '');

    // Remove "FormatException: " prefix
    cleaned = cleaned.replaceAll(RegExp(r'^FormatException:\s*', caseSensitive: false), '');

    // Remove stack trace lines (anything after first newline)
    final nlIndex = cleaned.indexOf('\n');
    if (nlIndex > 0) cleaned = cleaned.substring(0, nlIndex);

    return cleaned.trim();
  }
}
