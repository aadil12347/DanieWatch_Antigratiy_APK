import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../providers/admin_provider.dart';
import '../../../domain/models/app_notification.dart';

/// Screen for sending push notifications to users.
/// Shows 3 blast buttons + custom message + notification history.
class SendNotificationScreen extends ConsumerStatefulWidget {
  const SendNotificationScreen({super.key});

  @override
  ConsumerState<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends ConsumerState<SendNotificationScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _sendNotification(String type, String title, String body) async {
    setState(() => _isSending = true);
    final success = await AdminService.instance.sendNotification(
      type: type,
      title: title,
      body: body,
    );
    setState(() => _isSending = false);

    if (mounted) {
      if (success) {
        CustomToast.show(context, 'Notification sent!', type: ToastType.success);
        ref.invalidate(notificationHistoryProvider);
        _titleController.clear();
        _bodyController.clear();
      } else {
        CustomToast.show(context, 'Failed to send', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(notificationHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Send Notifications',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // ── Quick Blast Buttons ──────────────────────────────
            _buildSectionTitle('QUICK ANNOUNCEMENTS'),
            const SizedBox(height: 12),
            _buildBlastButton(
              icon: Icons.new_releases_rounded,
              label: 'Send "Newly Added" Notification',
              color: const Color(0xFF7C3AED),
              onTap: () => _sendNotification(
                'newly_added',
                '🎬 New Content Added!',
                'Check out the latest movies and shows added to DanieWatch!',
              ),
            ),
            const SizedBox(height: 10),
            _buildBlastButton(
              icon: Icons.movie_filter_rounded,
              label: 'Send "Recently Released" Notification',
              color: const Color(0xFF0891B2),
              onTap: () => _sendNotification(
                'recently_released',
                '🔥 Fresh Releases!',
                'New releases are now available on DanieWatch. Don\'t miss out!',
              ),
            ),

            const SizedBox(height: 32),

            // ── Custom Message ───────────────────────────────────
            _buildSectionTitle('CUSTOM ADMIN MESSAGE'),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Notification Title (e.g. Server Maintenance)',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Notification Body...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSending
                  ? null
                  : () {
                      final title = _titleController.text.trim();
                      final body = _bodyController.text.trim();
                      if (title.isEmpty || body.isEmpty) {
                        CustomToast.show(context, 'Title and Body required', type: ToastType.error);
                        return;
                      }
                      _sendNotification('admin_message', title, body);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Send Admin Message',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),

            const SizedBox(height: 36),

            // ── Notification History ─────────────────────────────
            _buildSectionTitle('RECENT HISTORY (7 DAYS)'),
            const SizedBox(height: 12),
            historyAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.error)),
              data: (notifications) {
                if (notifications.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.notifications_off_outlined, color: AppColors.textMuted, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'No notifications sent yet',
                          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: notifications.map((n) => _buildHistoryItem(n)).toList(),
                );
              },
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildBlastButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isSending ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(Icons.send_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(AppNotification notification) {
    IconData typeIcon;
    Color typeColor;
    switch (notification.type) {
      case 'newly_added':
        typeIcon = Icons.new_releases_rounded;
        typeColor = const Color(0xFF7C3AED);
        break;
      case 'recently_released':
        typeIcon = Icons.movie_filter_rounded;
        typeColor = const Color(0xFF0891B2);
        break;
      default:
        typeIcon = Icons.message_rounded;
        typeColor = AppColors.primary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(typeIcon, color: typeColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      notification.timeAgo,
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notification.body,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}
