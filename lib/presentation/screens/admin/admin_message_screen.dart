import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../providers/admin_provider.dart';
import '../../../domain/models/app_notification.dart';

/// Admin Message screen — compose and send custom messages with optional image.
class AdminMessageScreen extends ConsumerStatefulWidget {
  const AdminMessageScreen({super.key});

  @override
  ConsumerState<AdminMessageScreen> createState() => _AdminMessageScreenState();
}

class _AdminMessageScreenState extends ConsumerState<AdminMessageScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _imageUrlController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final imageUrl = _imageUrlController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      CustomToast.show(context, 'Title and Body required', type: ToastType.error);
      return;
    }

    setState(() => _isSending = true);

    final success = await AdminService.instance.sendNotification(
      type: 'admin_message',
      title: title,
      body: body,
      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
      data: imageUrl.isNotEmpty ? {'image_url': imageUrl} : null,
    );

    setState(() => _isSending = false);

    if (mounted) {
      if (success) {
        CustomToast.show(context, 'Message sent!', type: ToastType.success);
        ref.invalidate(notificationHistoryProvider);
        _titleController.clear();
        _bodyController.clear();
        _imageUrlController.clear();
      } else {
        CustomToast.show(context, 'Failed to send', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(notificationHistoryProvider);
    const accentColor = Color(0xFFD97706);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Admin Message', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _isSending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: accentColor)),
                )
              : IconButton(
                  icon: const Icon(Icons.send_rounded, color: accentColor),
                  tooltip: 'Send Message',
                  onPressed: _sendMessage,
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),

            // ── Compose Card ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accentColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Compose Message',
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text('Title', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'e.g. Server Maintenance',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Body
                  Text('Body', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _bodyController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Your message to all users...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Image URL (optional)
                  Text('Image URL (optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _imageUrlController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'https://example.com/image.jpg',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: AppColors.surface,
                      prefixIcon: const Icon(Icons.image_outlined, color: Colors.white24, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Send button (inline)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendMessage,
                      icon: _isSending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isSending ? 'Sending...' : 'Send Message',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Recent Admin Messages ────────────────────────────
            Text(
              'RECENT MESSAGES',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),

            historyAsync.when(
              loading: () => const Center(
                child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: accentColor)),
              ),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.error)),
              data: (notifications) {
                final adminMessages = notifications.where((n) => n.type == 'admin_message').toList();
                if (adminMessages.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      children: [
                        const Icon(Icons.campaign_outlined, color: AppColors.textMuted, size: 40),
                        const SizedBox(height: 12),
                        Text('No messages sent yet', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14)),
                      ],
                    ),
                  );
                }

                return Column(
                  children: adminMessages.take(20).map((n) => _buildHistoryItem(n)).toList(),
                );
              },
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(AppNotification notification) {
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
              color: const Color(0xFFD97706).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.campaign_rounded, color: Color(0xFFD97706), size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(notification.title,
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text(notification.timeAgo, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(notification.body,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
