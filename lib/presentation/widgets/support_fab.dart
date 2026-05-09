import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../providers/support_provider.dart';
import '../providers/admin_provider.dart';
import '../providers/support_modal_provider.dart';

/// A draggable floating support button with velocity-based spring physics.
/// Snaps to screen edges with momentum from the user's drag gesture.
class SupportFAB extends ConsumerStatefulWidget {
  const SupportFAB({super.key});

  @override
  ConsumerState<SupportFAB> createState() => _SupportFABState();
}

class _SupportFABState extends ConsumerState<SupportFAB>
    with TickerProviderStateMixin {
  static const _fabSize = 48.0;
  static const _edgePadding = 12.0;
  static const _prefsKeyX = 'support_fab_x';
  static const _prefsKeyY = 'support_fab_y';

  // Separate X and Y animation controllers for independent spring physics
  late AnimationController _xController;
  late AnimationController _yController;
  Animation<double>? _xAnim;
  Animation<double>? _yAnim;

  Offset _position = Offset.zero;
  bool _initialized = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _xController = AnimationController.unbounded(vsync: this);
    _yController = AnimationController.unbounded(vsync: this);
    _xController.addListener(_onAnimUpdate);
    _yController.addListener(_onAnimUpdate);
    _loadPosition();
  }

  void _onAnimUpdate() {
    if (!mounted) return;
    setState(() {
      _position = Offset(
        _xAnim?.value ?? _xController.value,
        _yAnim?.value ?? _yController.value,
      );
    });
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_prefsKeyX);
    final y = prefs.getDouble(_prefsKeyY);
    if (x != null && y != null) {
      _position = Offset(x, y);
    }
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKeyX, _position.dx);
    await prefs.setDouble(_prefsKeyY, _position.dy);
  }

  void _initDefaultPosition(Size screenSize, EdgeInsets padding) {
    if (_position == Offset.zero) {
      _position = Offset(
        screenSize.width - _fabSize - _edgePadding,
        screenSize.height - padding.bottom - 160,
      );
    }
  }

  void _onPanStart(DragStartDetails details) {
    _xController.stop();
    _yController.stop();
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details, Size screenSize, EdgeInsets padding) {
    setState(() => _isDragging = false);

    final velocity = details.velocity.pixelsPerSecond;

    // Determine snap edge based on position + velocity direction
    final centerX = _position.dx + _fabSize / 2;
    final halfScreen = screenSize.width / 2;
    // If velocity is strong enough, use its direction; otherwise use position
    double targetX;
    if (velocity.dx.abs() > 300) {
      targetX = velocity.dx < 0
          ? _edgePadding
          : screenSize.width - _fabSize - _edgePadding;
    } else {
      targetX = centerX < halfScreen
          ? _edgePadding
          : screenSize.width - _fabSize - _edgePadding;
    }

    // Vertical: project with velocity then clamp
    final minY = padding.top + _edgePadding;
    final maxY = screenSize.height - padding.bottom - _fabSize - 120;
    // Project position forward based on velocity (momentum)
    final projectedY = _position.dy + velocity.dy * 0.15;
    final targetY = projectedY.clamp(minY, maxY);

    // Spring physics for X (horizontal snap)
    const xSpring = SpringDescription(mass: 1.0, stiffness: 200, damping: 22);
    final xSim = SpringSimulation(xSpring, _position.dx, targetX, velocity.dx);
    _xAnim = null;
    _xController.animateWith(xSim);

    // Spring physics for Y (vertical momentum settle)
    const ySpring = SpringDescription(mass: 1.0, stiffness: 150, damping: 20);
    final ySim = SpringSimulation(ySpring, _position.dy, targetY, velocity.dy);
    _yAnim = null;
    _yController.animateWith(ySim);

    // Save after animation settles
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _savePosition();
    });
  }

  bool _shouldShow(String location) {
    final hidePatterns = [
      '/profile',
      '/account-settings',
      '/security-settings',
      '/notifications',
      '/notification-settings',
      '/admin-console',
      '/support-inbox',
      '/requests',
    ];
    for (final p in hidePatterns) {
      if (location.startsWith(p)) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isModalOpen = ref.watch(supportModalProvider);

    if (!_shouldShow(location) || isModalOpen) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    if (!_initialized) return const SizedBox.shrink();
    _initDefaultPosition(screenSize, padding);

    // Clamp display position
    final minY = padding.top + _edgePadding;
    final maxY = screenSize.height - padding.bottom - _fabSize - 120;
    final clampedY = _position.dy.clamp(minY, maxY);
    final clampedX = _position.dx.clamp(_edgePadding, screenSize.width - _fabSize - _edgePadding);

    // Get unread count
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final unreadCount = isAdmin
        ? ref.watch(adminUnreadCountProvider)
        : ref.watch(userUnreadCountProvider);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (d) => _onPanEnd(d, screenSize, padding),
        onTap: () => ref.read(supportModalProvider.notifier).state = true,
        child: AnimatedScale(
          scale: _isDragging ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            width: _fabSize,
            height: _fabSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF047857)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: _isDragging ? 0.5 : 0.35),
                  blurRadius: _isDragging ? 20 : 14,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: Icon(Icons.support_agent_rounded, color: Colors.white, size: 24),
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.background, width: 1.5),
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
                      child: Center(
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
