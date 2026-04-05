import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_screen.dart'; // For FloatingParticles
import '../../providers/security_provider.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';

class PinScreen extends ConsumerStatefulWidget {
  final bool isConfirmMode;
  final String? initialPin;
  final Function(String)? onComplete;

  const PinScreen({
    super.key,
    this.isConfirmMode = false,
    this.initialPin,
    this.onComplete,
  });

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  String _enteredPin = '';
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    // Auto-trigger biometrics if enabled and not in setup mode
    if (!widget.isConfirmMode && widget.onComplete == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkBiometrics());
    }
  }

  Future<void> _checkBiometrics() async {
    final state = ref.read(securityProvider).valueOrNull;
    if (state?.isBiometricEnabled ?? false) {
      final success = await ref.read(securityProvider.notifier).authenticateWithBiometrics();
      if (success && mounted) {
        context.go('/home');
      }
    }
  }

  void _onKeyPress(String key) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += key;
        _isError = false;
      });
      
      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onDelete() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _isError = false;
      });
    }
  }

  Future<void> _verifyPin() async {
    if (widget.onComplete != null) {
        widget.onComplete!(_enteredPin);
        return;
    }

    final isValid = await ref.read(securityProvider.notifier).verifyPin(_enteredPin);
    if (isValid) {
      if (mounted) context.go('/home');
    } else {
      setState(() {
        _isError = true;
        _enteredPin = '';
      });
      if (mounted) CustomToast.show(context, 'Incorrect PIN', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: FloatingParticles()),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 60),
                // Header
                Text(
                  widget.isConfirmMode ? 'Confirm PIN' : 'Enter PIN',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isConfirmMode 
                      ? 'Re-enter the 4 digits to confirm'
                      : 'Security verification required',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white60,
                  ),
                ),
                
                const Spacer(),
                
                // PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final isFilled = index < _enteredPin.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFilled 
                            ? (_isError ? Colors.red : AppColors.primary)
                            : Colors.white12,
                        border: Border.all(
                          color: isFilled ? Colors.transparent : Colors.white24,
                          width: 1,
                        ),
                      ),
                    );
                  }),
                ),
                
                const Spacer(),
                
                // Keypad
                _buildKeypad(),
                
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['1', '2', '3'].map((k) => _buildKey(k)).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['4', '5', '6'].map((k) => _buildKey(k)).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['7', '8', '9'].map((k) => _buildKey(k)).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSpecialKey(Icons.fingerprint_rounded, () => _checkBiometrics()),
              _buildKey('0'),
              _buildSpecialKey(Icons.backspace_outlined, _onDelete),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label) {
    return GestureDetector(
      onTap: () => _onKeyPress(label),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialKey(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white70, size: 28),
      ),
    );
  }
}
