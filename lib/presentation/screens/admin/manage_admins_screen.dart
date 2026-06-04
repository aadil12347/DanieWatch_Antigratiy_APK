import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../providers/admin_provider.dart';

/// Screen for managing admin users — add/remove admins by email.
class ManageAdminsScreen extends ConsumerStatefulWidget {
  const ManageAdminsScreen({super.key});

  @override
  ConsumerState<ManageAdminsScreen> createState() => _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends ConsumerState<ManageAdminsScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _addAdmin() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      CustomToast.show(context, 'Enter a valid email', type: ToastType.error);
      return;
    }

    setState(() => _isAdding = true);
    try {
      final success = await AdminService.instance.addAdmin(email);
      if (mounted) {
        if (success) {
          CustomToast.show(context, 'Admin added: $email', type: ToastType.success);
          _emailController.clear();
          ref.invalidate(adminListProvider);
        } else {
          CustomToast.show(context, 'User not found with this email', type: ToastType.error);
        }
      }
    } catch (e) {
      if (mounted) {
        CustomToast.show(context, 'Error: $e', type: ToastType.error);
      }
    }
    setState(() => _isAdding = false);
  }

  Future<void> _removeAdmin(String adminId, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Admin?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Remove admin privileges from $email?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AdminService.instance.removeAdmin(adminId);
        ref.invalidate(adminListProvider);
        if (mounted) {
          CustomToast.show(context, 'Admin removed', type: ToastType.info);
        }
      } catch (e) {
        if (mounted) {
          CustomToast.show(context, 'Error: $e', type: ToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminsAsync = ref.watch(adminListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Manage Admins',
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
            const SizedBox(height: 24),

            // Add Admin Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ADD NEW ADMIN',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'User must have a registered account',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'user@gmail.com',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _isAdding ? null : _addAdmin,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _isAdding
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.person_add_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Current Admins List
            Text(
              'CURRENT ADMINS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            adminsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.error)),
              data: (admins) {
                if (admins.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.group_off_rounded, color: AppColors.textMuted, size: 40),
                        SizedBox(height: 12),
                        Text('No admins found', style: TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  );
                }

                return Column(
                  children: admins.map((admin) {
                    final email = admin['email'] ?? '';
                    final adminId = admin['id'] ?? '';
                    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'A';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Email
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  email,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Admin',
                                  style: GoogleFonts.inter(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Remove button
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 22),
                            onPressed: () => _removeAdmin(adminId, email),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
