import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Content for the "More" expandable modal in the bottom navbar.
/// Shows page navigation buttons for secondary screens.
class MoreModalContent extends StatelessWidget {
  final String currentRoute;
  final VoidCallback onClose;
  
  const MoreModalContent({
    super.key, 
    required this.currentRoute,
    required this.onClose,
  });

  static const _pages = [
    _MorePage('Anime', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, '/anime'),
    _MorePage('Korean', Icons.live_tv_outlined, Icons.live_tv_rounded, '/korean'),
    _MorePage('Bollywood', Icons.movie_filter_outlined, Icons.movie_filter_rounded, '/movies'),
    _MorePage('Hollywood', Icons.theaters_outlined, Icons.theaters_rounded, '/tv'),
    _MorePage('Downloads', Icons.download_outlined, Icons.download_rounded, '/downloads'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12, left: 16, right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Page buttons in a 4-column grid
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: _pages.map((page) {
              final isActive = currentRoute == page.route;
              return GestureDetector(
                onTap: () {
                  onClose();
                  context.go(page.route);
                },
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isActive ? page.activeIcon : page.icon,
                      color: isActive ? AppColors.primary : Colors.white,
                      size: 26,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      page.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive 
                            ? AppColors.primary 
                            : Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _MorePage {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;
  const _MorePage(this.label, this.icon, this.activeIcon, this.route);
}
