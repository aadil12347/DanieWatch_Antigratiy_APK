import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).matchedLocation;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Drawer(
          backgroundColor: AppColors.background.withValues(alpha: 0.95), // ~95% opaque dark Claude bg
          width: MediaQuery.sizeOf(context).width * 0.72,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Branding Header ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Brand icon pill
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                           Row(
                            children: [
                              Text(
                                'Danie',
                                style: GoogleFonts.lora(
                                  color: AppColors.textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                'Watch',
                                style: GoogleFonts.lora(
                                  color: AppColors.primary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your streaming companion',
                        style: TextStyle(
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // Subtle divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                    height: 1,
                    thickness: 0.5,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Navigation Section Label ─────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    'BROWSE',
                    style: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),

                // ── Nav Items ────────────────────────────────────
                Expanded(
                  child: ListView(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                    children: [
                      _NavItem(
                          label: 'Home',
                          icon: Icons.home_rounded,
                          route: '/home',
                          currentRoute: currentRoute),
                      _NavItem(
                          label: 'Watchlist',
                          icon: Icons.bookmark_rounded,
                          route: '/watchlist',
                          currentRoute: currentRoute),
                      _NavItem(
                          label: 'Downloads',
                          icon: Icons.download_rounded,
                          route: '/downloads',
                          currentRoute: currentRoute),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        child: Divider(
                          color: Colors.white.withValues(alpha: 0.07),
                          height: 1,
                          thickness: 0.5,
                        ),
                      ),
                      _NavItem(
                          label: 'Search',
                          icon: Icons.search_rounded,
                          route: '/search',
                          currentRoute: currentRoute),
                    ],
                  ),
                ),

                // ── Footer ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13,
                          color: AppColors.textMuted.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Text(
                        'DanieWatch v1.0.0',
                        style: TextStyle(
                          color: AppColors.textMuted.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.currentRoute,
  });

  final String label;
  final IconData icon;
  final String route;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final isSelected = currentRoute == route ||
        (route != '/home' && currentRoute.startsWith(route)) ||
        (route == '/home' && currentRoute == '/home');

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            if (!isSelected) {
              if (route == '/search' || route == '/downloads') {
                context.push(route);
              } else {
                context.go(route);
              }
            }
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: AppColors.primary.withValues(alpha: 0.12),
          highlightColor: AppColors.primary.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      width: 0.8,
                    )
                  : null,
            ),
            child: Row(
              children: [
                // Active indicator strip
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  icon,
                  size: 20,
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: isSelected ? 0.1 : 0.0,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
