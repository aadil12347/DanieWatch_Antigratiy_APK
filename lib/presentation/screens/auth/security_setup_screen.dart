import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/security_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import './pin_screen.dart';
import './auth_screen.dart'; // For FloatingParticles

class SecuritySetupScreen extends ConsumerStatefulWidget {
  const SecuritySetupScreen({super.key});

  @override
  ConsumerState<SecuritySetupScreen> createState() => _SecuritySetupScreenState();
}

class _SecuritySetupScreenState extends ConsumerState<SecuritySetupScreen> {
  int _step = 0; // 0: Welcome, 1: Set PIN, 2: Confirm PIN, 3: Biometrics
  String _tempPin = '';

  void _nextStep() {
    setState(() => _step++);
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('needs_security_setup', false);
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: FloatingParticles()),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return PinScreen(
          isConfirmMode: false,
          onComplete: (pin) {
            setState(() {
              _tempPin = pin;
              _step = 2;
            });
          },
        );
      case 2:
        return PinScreen(
          isConfirmMode: true,
          initialPin: _tempPin,
          onComplete: (pin) async {
            if (pin == _tempPin) {
              await ref.read(securityProvider.notifier).updatePin(pin);
              await ref.read(securityProvider.notifier).toggleAppLock(true);
              _nextStep();
            } else {
              CustomToast.show(context, 'PINs do not match', type: ToastType.error);
              setState(() => _step = 1);
            }
          },
        );
      case 3:
        return _buildBiometricStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.security_rounded, color: AppColors.primary, size: 64),
          ),
          const SizedBox(height: 40),
          Text(
            'Secure your account',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Add an extra layer of protection to your DanieWatch account with a PIN or biometrics.',
            style: GoogleFonts.inter(fontSize: 16, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Setup Security'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _skip,
            child: const Text('Skip for now', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricStep() {
    final securityState = ref.watch(securityProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.1),
              border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.fingerprint_rounded, color: Colors.green, size: 64),
          ),
          const SizedBox(height: 40),
          Text(
            'Enable Biometrics',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Unlock DanieWatch instantly using your fingerprint or facial recognition.',
            style: GoogleFonts.inter(fontSize: 16, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          if (securityState?.canUseBiometrics ?? false) ...[
            ElevatedButton(
              onPressed: () async {
                final success = await ref.read(securityProvider.notifier).authenticateWithBiometrics();
                if (success) {
                   await ref.read(securityProvider.notifier).toggleBiometrics(true);
                   final prefs = await SharedPreferences.getInstance();
                   await prefs.setBool('needs_security_setup', false);
                   if (mounted) context.go('/home');
                }
              },
              child: const Text('Enable Biometrics'),
            ),
            const SizedBox(height: 16),
          ],
          TextButton(
            onPressed: _skip,
            child: Text(
              (securityState?.canUseBiometrics ?? false) ? 'Maybe Later' : 'Complete Setup',
              style: const TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}
