import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/security_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final securityState = ref.watch(securityProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Account Settings',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Authentication'),
            const SizedBox(height: 16),
            _buildSettingTile(
              context,
              icon: Icons.email_outlined,
              title: 'Email Address',
              subtitle: profile?.email ?? 'Loading...',
              onTap: () => _showUpdateEmailSheet(context, ref, profile?.email ?? ''),
            ),
            const SizedBox(height: 12),
            _buildSettingTile(
              context,
              icon: Icons.lock_outline_rounded,
              title: 'Change Password',
              subtitle: 'Last changed: Recently',
              onTap: () => _showUpdatePasswordSheet(context, ref),
            ),
            
            const SizedBox(height: 32),
            _buildSectionHeader('Security'),
            const SizedBox(height: 16),
            
            // App Lock Toggle
            _buildSwitchTile(
              context,
              icon: Icons.phonelink_lock_rounded,
              title: 'App Lock PIN',
              subtitle: 'Require PIN to open the app',
              value: securityState?.isLockEnabled ?? false,
              onChanged: (val) async {
                if (val && !(securityState?.hasPin ?? false)) {
                  _showSetPinSheet(context, ref);
                } else {
                  await ref.read(securityProvider.notifier).toggleAppLock(val);
                  if (context.mounted) {
                    CustomToast.show(
                      context, 
                      val ? 'App Lock Enabled' : 'App Lock Disabled',
                      type: val ? ToastType.success : ToastType.info,
                    );
                  }
                }
              },
            ),
            
            if (securityState?.isLockEnabled ?? false) ...[
              const SizedBox(height: 12),
              _buildSettingTile(
                context,
                icon: Icons.pin_rounded,
                title: 'Change PIN',
                subtitle: 'Update your security code',
                onTap: () => _showSetPinSheet(context, ref, isChange: true),
              ),
              
              if (securityState?.canUseBiometrics ?? false) ...[
                const SizedBox(height: 12),
                _buildSwitchTile(
                  context,
                  icon: Icons.fingerprint_rounded,
                  title: 'Biometric Unlock',
                  subtitle: 'Use fingerprint or face recognition',
                  value: securityState?.isBiometricEnabled ?? false,
                  onChanged: (val) async {
                    await ref.read(securityProvider.notifier).toggleBiometrics(val);
                    if (context.mounted) {
                      CustomToast.show(
                        context, 
                        val ? 'Biometrics Enabled' : 'Biometrics Disabled',
                        type: val ? ToastType.success : ToastType.info,
                      );
                    }
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white70, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  void _showUpdateEmailSheet(BuildContext context, WidgetRef ref, String currentEmail) {
    final controller = TextEditingController(text: currentEmail);
    _showCustomBottomSheet(
      context,
      title: 'Update Email',
      description: 'A confirmation link will be sent to your new email.',
      controller: controller,
      hint: 'New Email Address',
      icon: Icons.email_outlined,
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
            CustomToast.show(context, 'Recovery link sent to $email', type: ToastType.success);
          }
        } catch (e) {
          if (context.mounted) CustomToast.show(context, 'Failed to update email', type: ToastType.error);
        }
      },
    );
  }

  void _showUpdatePasswordSheet(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    _showCustomBottomSheet(
      context,
      title: 'Update Password',
      description: 'Enter a strong new password (min 6 characters).',
      controller: controller,
      hint: 'New Password',
      isPassword: true,
      icon: Icons.lock_outline_rounded,
      buttonText: 'Update Password',
      onConfirm: () async {
        final password = controller.text.trim();
        if (password.length < 6) {
          CustomToast.show(context, 'Password too short', type: ToastType.warning);
          return;
        }
        try {
          await ref.read(profileProvider.notifier).updatePassword(password);
          if (context.mounted) {
            Navigator.pop(context);
            CustomToast.show(context, 'Password updated successfully!', type: ToastType.success);
          }
        } catch (e) {
          if (context.mounted) CustomToast.show(context, 'Failed to update password', type: ToastType.error);
        }
      },
    );
  }

  void _showSetPinSheet(BuildContext context, WidgetRef ref, {bool isChange = false}) {
    final controller = TextEditingController();
    _showCustomBottomSheet(
      context,
      title: isChange ? 'Change App PIN' : 'Set App PIN',
      description: 'Enter 4 digits to secure your application.',
      controller: controller,
      hint: '4-Digit PIN',
      isPin: true,
      icon: Icons.pin_rounded,
      buttonText: isChange ? 'Update PIN' : 'Enable Pin Lock',
      onConfirm: () async {
        final pin = controller.text.trim();
        if (pin.length != 4 || int.tryParse(pin) == null) {
          CustomToast.show(context, 'Enter exactly 4 digits', type: ToastType.warning);
          return;
        }
        await ref.read(securityProvider.notifier).updatePin(pin);
        if (!isChange) {
          await ref.read(securityProvider.notifier).toggleAppLock(true);
        }
        if (context.mounted) {
          Navigator.pop(context);
          CustomToast.show(context, isChange ? 'PIN updated' : 'App Lock enabled', type: ToastType.success);
        }
      },
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
    bool isPassword = false,
    bool isPin = false,
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
              obscureText: isPassword || isPin,
              keyboardType: isPin ? TextInputType.number : TextInputType.emailAddress,
              maxLength: isPin ? 4 : null,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: Icon(icon, color: Colors.white24, size: 20),
                counterText: '',
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
