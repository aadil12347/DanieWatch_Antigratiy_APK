import 'dart:math';
import 'package:flutter/material.dart';

/// Centralized responsive scaling utility.
///
/// All sizes in the app were designed for a reference screen of 375 × 812 dp
/// (standard iPhone X). This class provides helpers that scale those values
/// proportionally to the **current device** so the UI looks identical on the
/// design device and adapts gracefully everywhere else.
///
/// Usage:
/// ```dart
/// final r = Responsive(context);
/// Container(
///   width:   r.w(120),   // 120dp on reference → proportional elsewhere
///   height:  r.h(64),    // height-based
///   padding: EdgeInsets.all(r.w(16)),
///   child: Text('Hello', style: TextStyle(fontSize: r.f(14))),
/// );
/// ```
class Responsive {
  /// Reference design dimensions
  static const double _designWidth = 375.0;
  static const double _designHeight = 812.0;

  final double screenWidth;
  final double screenHeight;

  Responsive._(this.screenWidth, this.screenHeight);

  factory Responsive(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Responsive._(size.width, size.height);
  }

  // ── Scale Factors ──────────────────────────────────────────────────────────

  double get _sw => screenWidth / _designWidth;
  double get _sh => screenHeight / _designHeight;
  /// Font scale uses the *smaller* ratio so text never overflows.
  double get _sf => min(_sw, _sh);

  // ── Public Helpers ─────────────────────────────────────────────────────────

  /// Scale a **width / horizontal** value (padding, margin, card width …).
  double w(double value) => value * _sw;

  /// Scale a **height / vertical** value (spacing, card height …).
  double h(double value) => value * _sh;

  /// Scale a **font size**. Uses the smaller axis ratio for safety.
  double f(double value) => value * _sf;

  /// Scale using the **diagonal** ratio (balanced for squares, icons, etc.).
  double d(double value) {
    final designDiag = sqrt(_designWidth * _designWidth + _designHeight * _designHeight);
    final screenDiag = sqrt(screenWidth * screenWidth + screenHeight * screenHeight);
    return value * (screenDiag / designDiag);
  }

  /// Symmetric horizontal padding scaled.
  EdgeInsets ph(double value) => EdgeInsets.symmetric(horizontal: w(value));

  /// Symmetric vertical padding scaled.
  EdgeInsets pv(double value) => EdgeInsets.symmetric(vertical: h(value));

  /// All-sides padding scaled.
  EdgeInsets pa(double value) => EdgeInsets.all(w(value));

  // ── Grid Helpers ───────────────────────────────────────────────────────────

  /// Responsive grid column count.
  /// - < 400dp  → 2 columns
  /// - 400-599  → 2 columns
  /// - 600-899  → 3 columns
  /// - 900+     → 4 columns
  int get gridColumns {
    if (screenWidth >= 900) return 4;
    if (screenWidth >= 600) return 3;
    return 2;
  }

  /// Whether the device is considered a tablet (≥ 600dp).
  bool get isTablet => screenWidth >= 600;

  /// Whether the device is considered very small (< 340dp).
  bool get isSmall => screenWidth < 340;

  // ── Clamped helpers (prevent values from going too small/large) ─────────

  /// Scale width but clamp result between [minVal] and [maxVal].
  double wClamped(double value, {double? minVal, double? maxVal}) {
    final scaled = w(value);
    double result = scaled;
    if (minVal != null && result < minVal) result = minVal;
    if (maxVal != null && result > maxVal) result = maxVal;
    return result;
  }

  /// Scale font but clamp result between [minVal] and [maxVal].
  double fClamped(double value, {double? minVal, double? maxVal}) {
    final scaled = f(value);
    double result = scaled;
    if (minVal != null && result < minVal) result = minVal;
    if (maxVal != null && result > maxVal) result = maxVal;
    return result;
  }
}
