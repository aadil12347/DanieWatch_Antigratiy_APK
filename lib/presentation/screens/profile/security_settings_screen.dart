import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/security_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../widgets/settings_tile.dart';

class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final securityStateAsync = ref.watch(securityProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Security Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: securityStateAsync.when(
        data: (state) => _buildContent(context, ref, state),
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, SecurityState state) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader('App Protection'),
        const SizedBox(height: 12),
        SettingsTile(
          icon: Icons.phonelink_lock_rounded,
          title: 'App Lock',
          subtitle: state.isLockEnabled ? 'Enabled' : 'Disabled',
          trailing: Switch.adaptive(
            value: state.isLockEnabled,
            activeColor: AppColors.primary,
            onChanged: (value) async {
              if (value && !state.hasPin) {
                _showSetPinSheet(context, ref);
              } else {
                await ref.read(securityProvider.notifier).toggleAppLock(value);
                if (context.mounted) {
                  CustomToast.show(
                    context, 
                    value ? 'App Lock enabled' : 'App Lock disabled',
                    type: ToastType.success,
                  );
                }
              }
            },
          ),
          onTap: () {}, // Handled by switch
        ),
        if (state.isLockEnabled) ...[
          SettingsTile(
            icon: Icons.pin_rounded,
            title: 'Change PIN',
            subtitle: 'Update your 4-digit security code',
            onTap: () => _showSetPinSheet(context, ref, isChange: true),
          ),
          if (state.canUseBiometrics)
            SettingsTile(
              icon: Icons.fingerprint_rounded,
              title: 'Biometric Unlock',
              subtitle: 'Use Fingerprint or Face Lock',
              trailing: Switch.adaptive(
                value: state.isBiometricEnabled,
                activeTrackColor: AppColors.primary,
                onChanged: (value) async {
                  await ref.read(securityProvider.notifier).toggleBiometrics(value);
                  if (context.mounted) {
                    CustomToast.show(
                      context, 
                      value ? 'Biometrics enabled' : 'Biometrics disabled',
                      type: ToastType.success,
                    );
                  }
                },
              ),
              onTap: () {},
            ),
        ],
        const SizedBox(height: 32),
        _buildSectionHeader('Danger Zone'),
        const SizedBox(height: 12),
        SettingsTile(
          icon: Icons.delete_forever_rounded,
          title: 'Reset Security',
          subtitle: 'Clear PIN and disable all locks',
          isDestructive: true,
          onTap: () => _showResetConfirmation(context, ref),
        ),
      ],
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

  void _showSetPinSheet(BuildContext context, WidgetRef ref, {bool isChange = false}) {
    final controller = TextEditingController();
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
              isChange ? 'Update App PIN' : 'Set App PIN',
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter 4 digits to secure your application.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '4-Digit PIN',
                prefixIcon: const Icon(Icons.pin_rounded, color: Colors.white24, size: 20),
                counterText: '',
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
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
              child: Text(isChange ? 'Update PIN' : 'Enable Pin Lock'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Reset Security?', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'This will disable App Lock and clear your current PIN. Are you sure?',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(securityProvider.notifier).clearAll();
              if (context.mounted) {
                Navigator.pop(context);
                CustomToast.show(context, 'Security settings reset', type: ToastType.info);
              }
            },
            child: const Text('Reset', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
