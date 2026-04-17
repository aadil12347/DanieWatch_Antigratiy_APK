import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../widgets/settings_tile.dart';

/// Admin Controls Hub — the main admin page showing all admin features.
class AdminConsoleScreen extends ConsumerWidget {
  const AdminConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Admin Controls',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Admin Badge
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.3),
                    AppColors.primary.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ADMIN PANEL',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage content, notifications & users',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Content Management ───────────────────────────────
            _buildSectionTitle('MANAGE CONTENT'),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.new_releases_rounded,
              title: 'Newly Added',
              subtitle: 'Add/remove newly added content entries',
              onTap: () => context.push('/admin-console/manage-entries/newly_added'),
            ),
            SettingsTile(
              icon: Icons.movie_filter_rounded,
              title: 'Recently Released',
              subtitle: 'Add/remove recently released content',
              onTap: () => context.push('/admin-console/manage-entries/recently_released'),
            ),

            const SizedBox(height: 32),

            // ── Notifications ────────────────────────────────────
            _buildSectionTitle('NOTIFICATIONS'),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.notifications_active_rounded,
              title: 'Send Notifications',
              subtitle: 'Blast push notifications to users',
              onTap: () => context.push('/admin-console/send-notifications'),
            ),

            const SizedBox(height: 32),

            // ── Admin Settings ───────────────────────────────────
            _buildSectionTitle('ADMIN SETTINGS'),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.group_rounded,
              title: 'Manage Admins',
              subtitle: 'Add or remove admin users',
              onTap: () => context.push('/admin-console/manage-admins'),
            ),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
