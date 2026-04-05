import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../widgets/settings_tile.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Account Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionHeader('Profile Information'),
          const SizedBox(height: 12),
          SettingsTile(
            icon: Icons.email_rounded,
            title: 'Email Address',
            subtitle: profile?.email ?? 'Not set',
            onTap: () => _showUpdateEmailSheet(context, ref, profile?.email ?? ''),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('Security & Credentials'),
          const SizedBox(height: 12),
          SettingsTile(
            icon: Icons.lock_reset_rounded,
            title: 'Change Password',
            subtitle: 'Update your login credentials',
            onTap: () => _showPasswordOptionsSheet(context, ref),
          ),
          SettingsTile(
            icon: Icons.send_to_mobile_rounded,
            title: 'Password Reset Link',
            subtitle: 'Send a secure link to your email',
            onTap: () async {
              if (profile?.email != null) {
                try {
                  await ref.read(profileProvider.notifier).resetPassword(profile!.email!);
                  if (context.mounted) {
                    CustomToast.show(
                      context, 
                      'Reset link sent to ${profile.email}', 
                      type: ToastType.success,
                    );
                  }
                } catch (e) {
                  if (context.mounted) CustomToast.show(context, 'Failed to send reset link', type: ToastType.error);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showUpdateEmailSheet(BuildContext context, WidgetRef ref, String currentEmail) {
    final controller = TextEditingController(text: currentEmail);
    _showCustomBottomSheet(
      context,
      title: 'Update Email',
      description: 'Enter your new email address. You will need to confirm the change via email.',
      controller: controller,
      hint: 'New Email Address',
      icon: Icons.email_rounded,
      buttonText: 'Update Email',
      onConfirm: () async {
        final email = controller.text.trim();
        if (email.isEmpty || !email.contains('@')) {
          CustomToast.show(context, 'Please enter a valid email', type: ToastType.warning);
          return;
        }
        try {
          await ref.read(profileProvider.notifier).updateEmail(email);
          if (context.mounted) {
            Navigator.pop(context);
            CustomToast.show(context, 'Confirmation email sent!', type: ToastType.success);
          }
        } catch (e) {
          if (context.mounted) CustomToast.show(context, 'Failed to update email', type: ToastType.error);
        }
      },
    );
  }

  void _showPasswordOptionsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Change Password',
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 24),
            SettingsTile(
              icon: Icons.edit_note_rounded,
              title: 'Update Manually',
              subtitle: 'Requires your current password',
              onTap: () {
                Navigator.pop(context);
                _showManualPasswordUpdateSheet(context, ref);
              },
            ),
            SettingsTile(
              icon: Icons.alternate_email_rounded,
              title: 'Use Reset Link',
              subtitle: 'Send a link to your registered email',
              onTap: () async {
                Navigator.pop(context);
                final profile = ref.read(profileProvider).valueOrNull;
                if (profile?.email != null) {
                  await ref.read(profileProvider.notifier).resetPassword(profile!.email!);
                  if (context.mounted) {
                    CustomToast.show(context, 'Reset link sent!', type: ToastType.success);
                  }
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showManualPasswordUpdateSheet(BuildContext context, WidgetRef ref) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Update Password',
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 24),
            _buildPasswordField(currentPasswordController, 'Current Password', Icons.lock_outline_rounded),
            const SizedBox(height: 16),
            _buildPasswordField(newPasswordController, 'New Password', Icons.lock_clock_rounded),
            const SizedBox(height: 16),
            _buildPasswordField(confirmPasswordController, 'Confirm New Password', Icons.lock_reset_rounded),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                final current = currentPasswordController.text;
                final next = newPasswordController.text;
                final confirm = confirmPasswordController.text;

                if (current.isEmpty || next.isEmpty) {
                  CustomToast.show(context, 'Please fill all fields', type: ToastType.warning);
                  return;
                }
                if (next != confirm) {
                  CustomToast.show(context, 'Passwords do not match', type: ToastType.warning);
                  return;
                }
                if (next.length < 6) {
                  CustomToast.show(context, 'Password must be at least 6 characters', type: ToastType.warning);
                  return;
                }

                try {
                  // Verify current password by attempting a silent sign-in
                  final profile = ref.read(profileProvider).valueOrNull;
                  if (profile?.email != null) {
                    await ref.read(profileProvider.notifier).signIn(
                      email: profile!.email!,
                      password: current,
                    );
                    
                    // If successful, update the password
                    await ref.read(profileProvider.notifier).updatePassword(next);
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      CustomToast.show(context, 'Password updated!', type: ToastType.success);
                    }
                  }
                } catch (e) {
                  if (context.mounted) CustomToast.show(context, 'Invalid current password', type: ToastType.error);
                }
              },
              child: const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String hint, IconData icon) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.white24, size: 20),
      ),
    );
  }

  void _showCustomBottomSheet(
    BuildContext context, {
    required String title,
    required String description,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required String buttonText,
    required VoidCallback onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: Icon(icon, color: Colors.white24, size: 20),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onConfirm,
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}
