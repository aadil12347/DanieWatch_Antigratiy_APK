import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../providers/search_provider.dart';

/// Content for the "More" expandable section above the bottom navbar.
/// Shows navigation buttons in a single row matching the navbar style exactly.
class MoreModalContent extends ConsumerWidget {
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
    _MorePage('Bollywood', Icons.movie_filter_outlined, Icons.movie_filter_rounded, '/bollywood'),
    _MorePage('Hollywood', Icons.theaters_outlined, Icons.theaters_rounded, '/hollywood'),
    _MorePage('Downloads', Icons.download_outlined, Icons.download_rounded, '/downloads'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _pages.take(4).map((p) => _buildPageButton(context, ref, p)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPageButton(context, ref, _pages.last),
              const SizedBox(width: 64),
              const SizedBox(width: 64),
              const SizedBox(width: 64),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(BuildContext context, WidgetRef ref, _MorePage page) {
    final isActive = currentRoute == page.route;
    return GestureDetector(
      onTap: () {
        // Clear filters when navigating to prevent bleed
        ref.read(searchProvider.notifier).clear();
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
              color: isActive ? AppColors.primary : AppColors.textMuted,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              page.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: isActive ? AppColors.primary : AppColors.textMuted,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.2,
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
