import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../providers/support_provider.dart';
import '../providers/admin_provider.dart';
import '../providers/support_modal_provider.dart';


/// A draggable floating support button that snaps to screen edges.
/// Visible on all pages except video player, profile, notifications, admin,
/// and request pages. Shows unread badge. Tapping opens the support modal.
class SupportFAB extends ConsumerStatefulWidget {
  const SupportFAB({super.key});

  @override
  ConsumerState<SupportFAB> createState() => _SupportFABState();
}

class _SupportFABState extends ConsumerState<SupportFAB>
    with SingleTickerProviderStateMixin {
  static const _fabSize = 48.0;
  static const _edgePadding = 16.0;
  static const _prefsKeyX = 'support_fab_x';
  static const _prefsKeyY = 'support_fab_y';

  late AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  Offset _position = Offset.zero;
  bool _initialized = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _snapController.addListener(() {
      if (_snapAnimation != null) {
        setState(() => _position = _snapAnimation!.value);
      }
    });
    _loadPosition();
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
      // Default: bottom-right corner above the navbar
      _position = Offset(
        screenSize.width - _fabSize - _edgePadding,
        screenSize.height - padding.bottom - 160,
      );
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _position += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details, Size screenSize, EdgeInsets padding) {
    _isDragging = false;
    // Snap to nearest horizontal edge
    final centerX = _position.dx + _fabSize / 2;
    final halfScreen = screenSize.width / 2;

    double targetX;
    if (centerX < halfScreen) {
      // Snap left
      targetX = _edgePadding;
    } else {
      // Snap right
      targetX = screenSize.width - _fabSize - _edgePadding;
    }

    // Clamp vertical
    final minY = padding.top + _edgePadding;
    final maxY = screenSize.height - padding.bottom - _fabSize - 120; // above navbar
    final targetY = _position.dy.clamp(minY, maxY);

    final target = Offset(targetX, targetY);

    _snapAnimation = Tween<Offset>(
      begin: _position,
      end: target,
    ).animate(CurvedAnimation(
      parent: _snapController,
      curve: Curves.easeOutBack,
    ));

    _snapController.forward(from: 0).then((_) {
      _position = target;
      _savePosition();
    });
  }

  bool _shouldShow(String location) {
    // Hide on these routes
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

    for (final pattern in hidePatterns) {
      if (location.startsWith(pattern)) return false;
    }

    return true;
  }

  @override
  void dispose() {
    _snapController.dispose();
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

    // Clamp position within bounds
    final minY = padding.top + _edgePadding;
    final maxY = screenSize.height - padding.bottom - _fabSize - 120;
    final clampedY = _position.dy.clamp(minY, maxY);
    final clampedX = _position.dx.clamp(_edgePadding, screenSize.width - _fabSize - _edgePadding);
    final clampedPos = Offset(clampedX, clampedY);

    // Get unread count
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final unreadCount = isAdmin
        ? ref.watch(adminUnreadCountProvider)
        : ref.watch(userUnreadCountProvider);

    return Positioned(
      left: clampedPos.dx,
      top: clampedPos.dy,
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: (details) => _onPanEnd(details, screenSize, padding),
        onTap: () {
          // Open the support modal
          ref.read(supportModalProvider.notifier).state = true;
        },
        child: AnimatedScale(
          scale: _isDragging ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
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
                  color: const Color(0xFF059669).withValues(alpha: 0.4),
                  blurRadius: 16,
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
                // Icon
                const Center(
                  child: Icon(
                    Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                // Badge
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
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
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
