import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Content for the "More" expandable section above the bottom navbar.
/// Shows navigation buttons in a single row matching the navbar style exactly.
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _pages.take(4).map((p) => _buildPageButton(context, p)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPageButton(context, _pages.last),
              const SizedBox(width: 64),
              const SizedBox(width: 64),
              const SizedBox(width: 64),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(BuildContext context, _MorePage page) {
    final isActive = currentRoute == page.route;
    return GestureDetector(
      onTap: () {
        onClose();
        context.go(page.route);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? page.activeIcon : page.icon,
              color: isActive ? AppColors.primary : AppColors.textPrimary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              page.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textPrimary,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
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
