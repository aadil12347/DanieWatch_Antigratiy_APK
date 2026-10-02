import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Pure Vector Canvas Painters for Vidstack Icons (`media-icons`).
/// Zero external SVG dependencies, perfectly crisp at any DPI.
class VidstackIcon extends StatelessWidget {
  final Widget Function(BuildContext context, Color color, double size) builder;
  final Color color;
  final double size;

  const VidstackIcon._({
    super.key,
    required this.builder,
    this.color = Colors.white,
    this.size = 22.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: builder(context, color, size),
    );
  }

  // ─── Play / Pause / Replay ─────────────────────────────────────────────

  factory VidstackIcon.play({Key? key, Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      key: key,
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _PlayPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.pause({Key? key, Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      key: key,
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _PausePainter(color: c),
      ),
    );
  }

  factory VidstackIcon.replay({Key? key, Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      key: key,
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _ReplayPainter(color: c),
      ),
    );
  }

  // ─── Seek ±10s ─────────────────────────────────────────────────────────

  factory VidstackIcon.seekBackward10({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _Seek10Painter(color: c, isForward: false),
      ),
    );
  }

  factory VidstackIcon.seekForward10({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _Seek10Painter(color: c, isForward: true),
      ),
    );
  }

  // ─── Volume States ─────────────────────────────────────────────────────

  factory VidstackIcon.volumeHigh({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _VolumePainter(color: c, state: _VolumeState.high),
      ),
    );
  }

  factory VidstackIcon.volumeLow({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _VolumePainter(color: c, state: _VolumeState.low),
      ),
    );
  }

  factory VidstackIcon.volumeMute({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _VolumePainter(color: c, state: _VolumeState.mute),
      ),
    );
  }

  // ─── Captions / Subtitles ──────────────────────────────────────────────

  factory VidstackIcon.captions({
    Color color = Colors.white,
    double size = 22.0,
    bool isActive = false,
  }) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _CaptionsPainter(color: c, isActive: isActive),
      ),
    );
  }

  // ─── Settings Gear ─────────────────────────────────────────────────────

  factory VidstackIcon.settings({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => Center(
        child: Icon(
          Icons.settings_rounded,
          color: c,
          size: s,
        ),
      ),
    );
  }

  // ─── PiP & Fullscreen ──────────────────────────────────────────────────

  factory VidstackIcon.pip({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _PipPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.fullscreen({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _FullscreenPainter(color: c, isExit: false),
      ),
    );
  }

  factory VidstackIcon.exitFullscreen({Color color = Colors.white, double size = 22.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _FullscreenPainter(color: c, isExit: true),
      ),
    );
  }

  // ─── Navigation & Controls ─────────────────────────────────────────────

  factory VidstackIcon.chevronRight({Color color = Colors.white, double size = 18.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _ChevronPainter(color: c, isRight: true),
      ),
    );
  }

  factory VidstackIcon.chevronLeft({Color color = Colors.white, double size = 18.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _ChevronPainter(color: c, isRight: false),
      ),
    );
  }

  factory VidstackIcon.check({Color color = Colors.white, double size = 18.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _CheckPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.server({Color color = Colors.white, double size = 20.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _ServerPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.audio({Color color = Colors.white, double size = 20.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _AudioPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.speed({Color color = Colors.white, double size = 20.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _SpeedPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.quality({Color color = Colors.white, double size = 20.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _QualityPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.aspect({Color color = Colors.white, double size = 20.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _AspectPainter(color: c),
      ),
    );
  }

  factory VidstackIcon.lock({Color color = Colors.white, double size = 20.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _LockPainter(color: c, isLocked: true),
      ),
    );
  }

  factory VidstackIcon.unlock({Color color = Colors.white, double size = 20.0}) {
    return VidstackIcon._(
      color: color,
      size: size,
      builder: (_, c, s) => CustomPaint(
        size: Size(s, s),
        painter: _LockPainter(color: c, isLocked: false),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VECTOR PAINTERS
// ─────────────────────────────────────────────────────────────────────────────

class _PlayPainter extends CustomPainter {
  final Color color;
  _PlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Rounded triangle
    final path = Path()
      ..moveTo(w * 0.28, h * 0.18)
      ..lineTo(w * 0.82, h * 0.47)
      ..quadraticBezierTo(w * 0.88, h * 0.50, w * 0.82, h * 0.53)
      ..lineTo(w * 0.28, h * 0.82)
      ..quadraticBezierTo(w * 0.22, h * 0.85, w * 0.22, h * 0.78)
      ..lineTo(w * 0.22, h * 0.22)
      ..quadraticBezierTo(w * 0.22, h * 0.15, w * 0.28, h * 0.18)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PlayPainter oldDelegate) => oldDelegate.color != color;
}

class _PausePainter extends CustomPainter {
  final Color color;
  _PausePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;
    final barW = w * 0.22;
    final barH = h * 0.65;
    final top = (h - barH) / 2;
    final radius = Radius.circular(barW * 0.45);

    // Left bar
    final leftRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, top, barW, barH),
      radius,
    );
    // Right bar
    final rightRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.56, top, barW, barH),
      radius,
    );

    canvas.drawRRect(leftRect, paint);
    canvas.drawRRect(rightRect, paint);
  }

  @override
  bool shouldRepaint(_PausePainter oldDelegate) => oldDelegate.color != color;
}

class _ReplayPainter extends CustomPainter {
  final Color color;
  _ReplayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.10
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.36;

    // Arc from 45 deg to 300 deg
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.25,
      math.pi * 1.45,
      false,
      paint,
    );

    // Arrow tip
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final arrowCenter = Offset(
      center.dx + radius * math.cos(math.pi * 0.25),
      center.dy + radius * math.sin(math.pi * 0.25),
    );

    final arrowPath = Path()
      ..moveTo(arrowCenter.dx - size.width * 0.08, arrowCenter.dy - size.height * 0.14)
      ..lineTo(arrowCenter.dx + size.width * 0.08, arrowCenter.dy + size.height * 0.02)
      ..lineTo(arrowCenter.dx - size.width * 0.14, arrowCenter.dy + size.height * 0.08)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(_ReplayPainter oldDelegate) => oldDelegate.color != color;
}

class _Seek10Painter extends CustomPainter {
  final Color color;
  final bool isForward;
  _Seek10Painter({required this.color, required this.isForward});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.38;

    if (isForward) {
      // Clockwise circular arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi * 0.65,
        math.pi * 1.50,
        false,
        strokePaint,
      );

      // Arrowhead pointing right at top
      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      final tipX = center.dx + radius * math.cos(-math.pi * 0.65);
      final tipY = center.dy + radius * math.sin(-math.pi * 0.65);

      final path = Path()
        ..moveTo(tipX, tipY - size.height * 0.10)
        ..lineTo(tipX + size.width * 0.12, tipY + size.height * 0.04)
        ..lineTo(tipX - size.width * 0.04, tipY + size.height * 0.08)
        ..close();
      canvas.drawPath(path, arrowPaint);
    } else {
      // Counter-clockwise circular arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi * 0.35,
        -math.pi * 1.50,
        false,
        strokePaint,
      );

      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      final tipX = center.dx + radius * math.cos(-math.pi * 0.35);
      final tipY = center.dy + radius * math.sin(-math.pi * 0.35);

      final path = Path()
        ..moveTo(tipX, tipY - size.height * 0.10)
        ..lineTo(tipX - size.width * 0.12, tipY + size.height * 0.04)
        ..lineTo(tipX + size.width * 0.04, tipY + size.height * 0.08)
        ..close();
      canvas.drawPath(path, arrowPaint);
    }

    // Number "10" centered
    final textPainter = TextPainter(
      text: TextSpan(
        text: '10',
        style: TextStyle(
          color: color,
          fontSize: size.width * 0.36,
          fontWeight: FontWeight.w800,
          fontFamily: 'sans-serif',
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2 + size.height * 0.04,
      ),
    );
  }

  @override
  bool shouldRepaint(_Seek10Painter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isForward != isForward;
}

enum _VolumeState { high, low, mute }

class _VolumePainter extends CustomPainter {
  final Color color;
  final _VolumeState state;
  _VolumePainter({required this.color, required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Speaker body
    final body = Path()
      ..moveTo(w * 0.12, h * 0.38)
      ..lineTo(w * 0.28, h * 0.38)
      ..lineTo(w * 0.46, h * 0.22)
      ..quadraticBezierTo(w * 0.50, h * 0.20, w * 0.50, h * 0.26)
      ..lineTo(w * 0.50, h * 0.74)
      ..quadraticBezierTo(w * 0.50, h * 0.80, w * 0.46, h * 0.78)
      ..lineTo(w * 0.28, h * 0.62)
      ..lineTo(w * 0.12, h * 0.62)
      ..quadraticBezierTo(w * 0.08, h * 0.62, w * 0.08, h * 0.58)
      ..lineTo(w * 0.08, h * 0.42)
      ..quadraticBezierTo(w * 0.08, h * 0.38, w * 0.12, h * 0.38)
      ..close();

    canvas.drawPath(body, fillPaint);

    if (state == _VolumeState.low || state == _VolumeState.high) {
      // First wave arc
      canvas.drawArc(
        Rect.fromCenter(center: Offset(w * 0.46, h * 0.50), width: w * 0.42, height: h * 0.42),
        -math.pi * 0.30,
        math.pi * 0.60,
        false,
        strokePaint,
      );
    }

    if (state == _VolumeState.high) {
      // Second outer wave arc
      canvas.drawArc(
        Rect.fromCenter(center: Offset(w * 0.46, h * 0.50), width: w * 0.70, height: h * 0.70),
        -math.pi * 0.30,
        math.pi * 0.60,
        false,
        strokePaint,
      );
    }

    if (state == _VolumeState.mute) {
      // Diagonal strike-through line
      final strikePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.10
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      canvas.drawLine(
        Offset(w * 0.62, h * 0.34),
        Offset(w * 0.88, h * 0.66),
        strikePaint,
      );
      canvas.drawLine(
        Offset(w * 0.88, h * 0.34),
        Offset(w * 0.62, h * 0.66),
        strikePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_VolumePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.state != state;
}

class _CaptionsPainter extends CustomPainter {
  final Color color;
  final bool isActive;
  _CaptionsPainter({required this.color, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..isAntiAlias = true;

    // Rounded rectangular badge
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.18, w * 0.84, h * 0.64),
      Radius.circular(w * 0.14),
    );
    canvas.drawRRect(rect, strokePaint);

    // CC text inside
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'CC',
        style: TextStyle(
          color: color,
          fontSize: w * 0.32,
          fontWeight: FontWeight.w900,
          fontFamily: 'sans-serif',
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (w - textPainter.width) / 2,
        (h - textPainter.height) / 2 + (isActive ? -h * 0.02 : 0),
      ),
    );

    // Active indicator: glowing dot/line at the bottom
    if (isActive) {
      final activePaint = Paint()
        ..color = const Color(0xFFE50914)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.28, h * 0.90, w * 0.44, h * 0.10),
          Radius.circular(w * 0.05),
        ),
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CaptionsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isActive != isActive;
}

class _SettingsGearPainter extends CustomPainter {
  final Color color;
  _SettingsGearPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.40;
    final innerR = size.width * 0.16;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Center circular hub
    canvas.drawCircle(center, innerR, strokePaint);

    // 6 outer teeth
    for (int i = 0; i < 6; i++) {
      final angle = i * (math.pi / 3);
      final p1 = Offset(
        center.dx + (innerR + size.width * 0.06) * math.cos(angle),
        center.dy + (innerR + size.width * 0.06) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      canvas.drawLine(p1, p2, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_SettingsGearPainter oldDelegate) => oldDelegate.color != color;
}

class _PipPainter extends CustomPainter {
  final Color color;
  _PipPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..isAntiAlias = true;

    // Main screen frame
    final mainScreen = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.14, w * 0.84, h * 0.68),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(mainScreen, strokePaint);

    // Floating mini screen (bottom right)
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final miniScreen = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.48, h * 0.44, w * 0.38, h * 0.32),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(miniScreen, fillPaint);
  }

  @override
  bool shouldRepaint(_PipPainter oldDelegate) => oldDelegate.color != color;
}

class _FullscreenPainter extends CustomPainter {
  final Color color;
  final bool isExit;
  _FullscreenPainter({required this.color, required this.isExit});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    final arm = w * 0.24;

    if (!isExit) {
      // 4 corners expanding outward
      // Top-Left
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.10, h * 0.10 + arm)
          ..lineTo(w * 0.10, h * 0.10)
          ..lineTo(w * 0.10 + arm, h * 0.10),
        strokePaint,
      );
      // Top-Right
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.90 - arm, h * 0.10)
          ..lineTo(w * 0.90, h * 0.10)
          ..lineTo(w * 0.90, h * 0.10 + arm),
        strokePaint,
      );
      // Bottom-Left
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.10, h * 0.90 - arm)
          ..lineTo(w * 0.10, h * 0.90)
          ..lineTo(w * 0.10 + arm, h * 0.90),
        strokePaint,
      );
      // Bottom-Right
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.90 - arm, h * 0.90)
          ..lineTo(w * 0.90, h * 0.90)
          ..lineTo(w * 0.90, h * 0.90 - arm),
        strokePaint,
      );
    } else {
      // 4 corners pointing inward
      // Top-Left
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.32, h * 0.14)
          ..lineTo(w * 0.32, h * 0.32)
          ..lineTo(w * 0.14, h * 0.32),
        strokePaint,
      );
      // Top-Right
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.68, h * 0.14)
          ..lineTo(w * 0.68, h * 0.32)
          ..lineTo(w * 0.86, h * 0.32),
        strokePaint,
      );
      // Bottom-Left
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.14, h * 0.68)
          ..lineTo(w * 0.32, h * 0.68)
          ..lineTo(w * 0.32, h * 0.86),
        strokePaint,
      );
      // Bottom-Right
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.86, h * 0.68)
          ..lineTo(w * 0.68, h * 0.68)
          ..lineTo(w * 0.68, h * 0.86),
        strokePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_FullscreenPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isExit != isExit;
}

class _ChevronPainter extends CustomPainter {
  final Color color;
  final bool isRight;
  _ChevronPainter({required this.color, required this.isRight});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path();
    if (isRight) {
      path.moveTo(w * 0.35, h * 0.20);
      path.lineTo(w * 0.68, h * 0.50);
      path.lineTo(w * 0.35, h * 0.80);
    } else {
      path.moveTo(w * 0.65, h * 0.20);
      path.lineTo(w * 0.32, h * 0.50);
      path.lineTo(w * 0.65, h * 0.80);
    }
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isRight != isRight;
}

class _CheckPainter extends CustomPainter {
  final Color color;
  _CheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path()
      ..moveTo(w * 0.18, h * 0.52)
      ..lineTo(w * 0.40, h * 0.74)
      ..lineTo(w * 0.82, h * 0.26);

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.color != color;
}

class _ServerPainter extends CustomPainter {
  final Color color;
  _ServerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..isAntiAlias = true;

    // Top rack
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.10, h * 0.18, w * 0.80, h * 0.28), Radius.circular(w * 0.08)),
      strokePaint,
    );
    // Bottom rack
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.10, h * 0.54, w * 0.80, h * 0.28), Radius.circular(w * 0.08)),
      strokePaint,
    );

    // Indicator LED dots
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawCircle(Offset(w * 0.24, h * 0.32), w * 0.04, dotPaint);
    canvas.drawCircle(Offset(w * 0.24, h * 0.68), w * 0.04, dotPaint);
  }

  @override
  bool shouldRepaint(_ServerPainter oldDelegate) => oldDelegate.color != color;
}

class _AudioPainter extends CustomPainter {
  final Color color;
  _AudioPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 5 vertical waveform bars
    final bars = [0.35, 0.70, 0.95, 0.60, 0.40];
    for (int i = 0; i < bars.length; i++) {
      final x = w * (0.18 + i * 0.16);
      final barH = h * bars[i];
      final y1 = (h - barH) / 2;
      final y2 = y1 + barH;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), strokePaint);
    }
  }

  @override
  bool shouldRepaint(_AudioPainter oldDelegate) => oldDelegate.color != color;
}

class _SpeedPainter extends CustomPainter {
  final Color color;
  _SpeedPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.38;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Speedometer dial arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi * 0.85,
      math.pi * 1.70,
      false,
      strokePaint,
    );

    // Indicator needle pointing up-right
    final needlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawLine(
      center,
      Offset(center.dx + r * 0.65 * math.cos(-math.pi * 0.30), center.dy + r * 0.65 * math.sin(-math.pi * 0.30)),
      needlePaint,
    );

    // Pivot dot
    canvas.drawCircle(center, size.width * 0.06, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SpeedPainter oldDelegate) => oldDelegate.color != color;
}

class _QualityPainter extends CustomPainter {
  final Color color;
  _QualityPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..isAntiAlias = true;

    // Outer screen badge
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.20, w * 0.84, h * 0.60),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(rect, strokePaint);

    // "HD" text inside
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'HD',
        style: TextStyle(
          color: color,
          fontSize: w * 0.32,
          fontWeight: FontWeight.w900,
          fontFamily: 'sans-serif',
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(_QualityPainter oldDelegate) => oldDelegate.color != color;
}

class _AspectPainter extends CustomPainter {
  final Color color;
  _AspectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..isAntiAlias = true;

    // Outer widescreen frame
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, h * 0.22, w * 0.84, h * 0.56), Radius.circular(w * 0.10)),
      strokePaint,
    );

    // Inside horizontal expansion arrows < >
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Left arrow <
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.34, h * 0.38)
        ..lineTo(w * 0.24, h * 0.50)
        ..lineTo(w * 0.34, h * 0.62),
      arrowPaint,
    );

    // Right arrow >
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.66, h * 0.38)
        ..lineTo(w * 0.76, h * 0.50)
        ..lineTo(w * 0.66, h * 0.62),
      arrowPaint,
    );
  }

  @override
  bool shouldRepaint(_AspectPainter oldDelegate) => oldDelegate.color != color;
}

class _LockPainter extends CustomPainter {
  final Color color;
  final bool isLocked;
  _LockPainter({required this.color, required this.isLocked});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Padlock body
    final bodyPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.20, h * 0.44, w * 0.60, h * 0.46), Radius.circular(w * 0.12)),
      bodyPaint,
    );

    // Padlock keyhole cutout
    final holePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.50, h * 0.62), w * 0.07, holePaint);

    // Shackle arc
    if (isLocked) {
      final shackle = Path()
        ..moveTo(w * 0.32, h * 0.44)
        ..lineTo(w * 0.32, h * 0.30)
        ..arcTo(
          Rect.fromCenter(center: Offset(w * 0.50, h * 0.30), width: w * 0.36, height: h * 0.36),
          math.pi,
          math.pi,
          false,
        )
        ..lineTo(w * 0.68, h * 0.44);
      canvas.drawPath(shackle, strokePaint);
    } else {
      // Unlocked shackle (lifted and swung)
      final shackle = Path()
        ..moveTo(w * 0.32, h * 0.44)
        ..lineTo(w * 0.32, h * 0.22)
        ..arcTo(
          Rect.fromCenter(center: Offset(w * 0.50, h * 0.22), width: w * 0.36, height: h * 0.36),
          math.pi,
          math.pi,
          false,
        )
        ..lineTo(w * 0.68, h * 0.30);
      canvas.drawPath(shackle, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_LockPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isLocked != isLocked;
}
