import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../providers/admin_provider.dart';

/// Admin Controls Hub — redesigned with 3 main action cards.
class AdminConsoleScreen extends ConsumerWidget {
  const AdminConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestCountAsync = ref.watch(notificationEntriesProvider('newly_added'));
    final recentCountAsync = ref.watch(notificationEntriesProvider('recently_released'));

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
            const SizedBox(height: 12),

            // ── Admin Badge ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.25),
                    AppColors.primary.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOTIFICATION CENTER',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Manage & send push notifications',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Notification Sections ────────────────────────────
            _buildSectionTitle('PUSH NOTIFICATIONS'),
            const SizedBox(height: 12),

            // 1. Latest Released
            _ActionCard(
              icon: Icons.new_releases_rounded,
              title: 'Latest Released',
              subtitle: 'Manually curate & send new releases',
              gradient: const [Color(0xFF7C3AED), Color(0xFF5B21B6)],
              badge: latestCountAsync.whenOrNull(
                data: (entries) => entries.isNotEmpty ? '${entries.length}' : null,
              ),
              onTap: () => context.push('/admin-console/manage-entries/newly_added'),
            ),

            const SizedBox(height: 10),

            // 2. Recently Added
            _ActionCard(
              icon: Icons.movie_filter_rounded,
              title: 'Recently Added',
              subtitle: 'Auto-add from index changes & send',
              gradient: const [Color(0xFF0891B2), Color(0xFF0E7490)],
              badge: recentCountAsync.whenOrNull(
                data: (entries) => entries.isNotEmpty ? '${entries.length}' : null,
              ),
              onTap: () => context.push('/admin-console/manage-entries/recently_released'),
            ),

            const SizedBox(height: 10),

            // 3. Admin Message
            _ActionCard(
              icon: Icons.campaign_rounded,
              title: 'Admin Message',
              subtitle: 'Send custom message with optional image',
              gradient: const [Color(0xFFD97706), Color(0xFFB45309)],
              onTap: () => context.push('/admin-console/admin-message'),
            ),

            const SizedBox(height: 32),

            // ── Admin Settings ───────────────────────────────────
            _buildSectionTitle('SETTINGS'),
            const SizedBox(height: 12),

            _ActionCard(
              icon: Icons.group_rounded,
              title: 'Manage Admins',
              subtitle: 'Add or remove admin users',
              gradient: const [Color(0xFF475569), Color(0xFF334155)],
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
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

/// Premium action card with gradient, icon, badge, and instant tap feedback.
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final String? badge;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: gradient[0].withValues(alpha: 0.1),
        highlightColor: gradient[0].withValues(alpha: 0.05),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gradient[0].withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [gradient[0].withValues(alpha: 0.25), gradient[1].withValues(alpha: 0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: gradient[0], size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: gradient[0].withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: gradient[0],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
