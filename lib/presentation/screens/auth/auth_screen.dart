import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

enum AuthMode { select, login, signup, forgot, checkEmail, resetPassword }

class AuthScreen extends ConsumerStatefulWidget {
  final bool isLogin;
  final VoidCallback onToggle;

  const AuthScreen({
    super.key,
    required this.isLogin,
    this.onToggle = _dummyToggle,
  });

  static void _dummyToggle() {}

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with TickerProviderStateMixin {
  late AuthMode _mode;
  final _formKey = GlobalKey<FormState>();
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _showPassword = false;
  String _sentEmail = '';

  late StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _mode = widget.isLogin ? AuthMode.login : AuthMode.signup;
    // However, per the new design, we start with 'select' unless already specific
    _mode = AuthMode.select;

    // Detect password recovery mode
    _authSubscription = supabaseClient.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _mode = AuthMode.resetPassword);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode newMode) {
    setState(() {
      _mode = newMode;
      _errorMessage = null;
      _showPassword = false;
    });
  }

  String _getFriendlyErrorMessage(Object error) {
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('email not confirmed')) {
      return 'Please confirm your email address before signing in. Check your inbox!';
    }
    if (errStr.contains('invalid login credentials') || errStr.contains('400')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (errStr.contains('user_already_exists') || errStr.contains('422')) {
      return 'An account with this email already exists.';
    }
    if (errStr.contains('network') || errStr.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    }
    if (errStr.contains('weak-password')) {
      return 'Password is too weak. Use a stronger password.';
    }
    return 'Authentication failed. Please try again.';
  }

  Future<void> _handleEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authNotifier = ref.read(profileProvider.notifier);
      
      if (_mode == AuthMode.login) {
        await authNotifier.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else if (_mode == AuthMode.signup) {
        await authNotifier.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          username: _usernameController.text.trim(),
        );
        
        // After signup, if we are still here (no auto-redirect), 
        // it means email confirmation is required.
        if (supabaseClient.auth.currentSession == null) {
          setState(() {
            _sentEmail = _emailController.text.trim();
            _mode = AuthMode.checkEmail;
          });
        }
      } else if (_mode == AuthMode.forgot) {
        await authNotifier.resetPassword(_emailController.text.trim());
        setState(() {
          _sentEmail = _emailController.text.trim();
          _mode = AuthMode.checkEmail;
        });
      } else if (_mode == AuthMode.resetPassword) {
        await authNotifier.updatePassword(_newPasswordController.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully!')),
          );
          _switchMode(AuthMode.login);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _getFriendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(profileProvider.notifier).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _getFriendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by SplashScreen overlay
      body: Stack(
        children: [
          // Particle layer
          const Positioned.fill(child: FloatingParticles()),
          
          // Main Content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Auth Card (Branding removed)
                  _buildAuthCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildAuthCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF121212).withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Accent Line
              Container(
                height: 2,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFFFF3B30).withValues(alpha: 0.8),
                      const Color(0xFFFF3B30).withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildCurrentModeView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentModeView() {
    switch (_mode) {
      case AuthMode.select:
        return _buildSelectView();
      case AuthMode.checkEmail:
        return _buildCheckEmailView();
      default:
        return _buildFormView();
    }
  }

  Widget _buildSelectView() {
    return Column(
      key: const ValueKey('select'),
      children: [
        Text(
          'Welcome!',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose how you\'d like to continue',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 32),
        
        // Google Button
        _buildSocialButton(
          label: 'Continue with Google',
          icon: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'G',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  fontFamily: 'Roboto', // Standard Google font look
                ),
              ),
            ),
          ),
          onPressed: _handleGoogleSignIn,
          isPrimary: true,
        ),
        
        const SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR', style: TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 1)),
            ),
            Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Email Button
        _buildSocialButton(
          label: 'Continue with Email',
          icon: const Icon(Icons.email_outlined, color: Colors.white, size: 20),
          onPressed: () => _switchMode(AuthMode.login),
          isPrimary: false,
        ),
      ],
    );
  }

  Widget _buildCheckEmailView() {
    final isSignupMode = _emailController.text.isNotEmpty && _mode == AuthMode.checkEmail && _usernameController.text.isNotEmpty;
    
    return Column(
      key: const ValueKey('checkEmail'),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
          ),
          child: Icon(
            isSignupMode ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded, 
            color: const Color(0xFFFF3B30), 
            size: 48
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isSignupMode ? 'Verify your email' : 'Check your email',
          style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          isSignupMode 
            ? 'We\'ve sent a verification link to:' 
            : 'We\'ve sent a recovery link to:',
          style: GoogleFonts.inter(fontSize: 14, color: Colors.white60),
        ),
        const SizedBox(height: 4),
        Text(
          _sentEmail,
          style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 32),
        
        if (isSignupMode) ...[
          ElevatedButton(
            onPressed: _isLoading ? null : () => _handleEmailAuth(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white10,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Resend Verification Email'),
          ),
          const SizedBox(height: 16),
        ],

        TextButton.icon(
          onPressed: () => _switchMode(AuthMode.login),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to Sign In'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30)),
        ),
      ],
    );
  }

  Widget _buildFormView() {
    final isSignup = _mode == AuthMode.signup;
    final isReset = _mode == AuthMode.resetPassword;
    final isForgot = _mode == AuthMode.forgot;

    return Form(
      key: _formKey,
      child: Column(
        key: ValueKey(_mode),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode Tabs (Login / Signup)
          if (!isForgot && !isReset) ...[
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _buildTab('Sign In', _mode == AuthMode.login, () => _switchMode(AuthMode.login)),
                  _buildTab('Sign Up', _mode == AuthMode.signup, () => _switchMode(AuthMode.signup)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Title & Description
          Text(
            isForgot ? 'Forgot Password?' : (isReset ? 'Set New Password' : (isSignup ? 'Create Account' : 'Welcome Back')),
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isForgot ? 'Enter your email to receive a reset link' : (isReset ? 'Choose a strong password' : (isSignup ? 'Join DanieWatch for free' : 'Sign in to continue watching')),
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.2)),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13)),
            ),
            const SizedBox(height: 16),
          ],

          if (isSignup) ...[
            _buildTextField(
              controller: _usernameController,
              hint: 'Username',
              icon: Icons.person_outline,
              validator: (v) => v?.isEmpty ?? true ? 'Enter username' : null,
            ),
            const SizedBox(height: 16),
          ],

          if (!isReset) ...[
            _buildTextField(
              controller: _emailController,
              hint: 'Email Address',
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v?.isEmpty ?? true) return 'Enter email';
                if (!v!.contains('@')) return 'Invalid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          if (!isForgot && !isReset) ...[
            _buildTextField(
              controller: _passwordController,
              hint: 'Password',
              icon: Icons.lock_outline,
              obscure: !_showPassword,
              suffix: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white30, size: 18),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              validator: (v) => (v?.length ?? 0) < 6 ? 'Min 6 characters' : null,
            ),
            if (!isSignup) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _switchMode(AuthMode.forgot),
                  child: const Text('Forgot password?', style: TextStyle(color: Color(0xFFFF3B30), fontSize: 12)),
                ),
              ),
            ],
          ],

          if (isReset) ...[
             _buildTextField(
              controller: _newPasswordController,
              hint: 'New Password',
              icon: Icons.key_outlined,
              obscure: !_showPassword,
              validator: (v) => (v?.length ?? 0) < 6 ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _confirmPasswordController,
              hint: 'Confirm Password',
              icon: Icons.lock_outline,
              obscure: !_showPassword,
              validator: (v) => v != _newPasswordController.text ? 'Passwords match required' : null,
            ),
          ],

          const SizedBox(height: 24),

          // Submit Button
          ElevatedButton(
            onPressed: _isLoading ? null : _handleEmailAuth,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              overlayColor: Colors.white24,
            ).copyWith(
              elevation: WidgetStateProperty.all(8),
              shadowColor: WidgetStateProperty.all(const Color(0xFFFF3B30).withValues(alpha: 0.4)),
            ),
            child: _isLoading
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(isForgot ? 'Send Reset Link' : (isReset ? 'Update Password' : (isSignup ? 'Create Account' : 'Sign In')), 
                       style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          
          const SizedBox(height: 16),
          
          // Back button
          TextButton.icon(
            onPressed: () => _switchMode(AuthMode.select),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Other options', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF3B30) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : Colors.white60,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white24, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: const Color(0xFFFF3B30).withValues(alpha: 0.5)),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFF3B30), fontSize: 11),
      ),
    );
  }

  Widget _buildSocialButton({
    required String label,
    required Widget icon,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isPrimary ? [
           BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ] : [],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.white : Colors.white.withValues(alpha: 0.05),
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          side: isPrimary ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class FloatingParticles extends StatefulWidget {
  const FloatingParticles({super.key});

  @override
  State<FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<FloatingParticles> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = List.generate(20, (index) => _Particle());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ParticlePainter(_particles, _controller.value),
        );
      },
    );
  }
}

class _Particle {
  double x = math.Random().nextDouble();
  double y = math.Random().nextDouble();
  double size = math.Random().nextDouble() * 3 + 1;
  double speed = math.Random().nextDouble() * 0.1 + 0.05;
  double opacity = math.Random().nextDouble() * 0.2 + 0.1;
  double angle = math.Random().nextDouble() * math.pi * 2;
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    for (var particle in particles) {
      final x = (particle.x * size.width + math.sin(progress * math.pi * 2 + particle.angle) * 20) % size.width;
      final y = (particle.y * size.height - progress * size.height * particle.speed) % size.height;
      
      paint.color = const Color(0xFFFF3B30).withValues(alpha: particle.opacity);
      canvas.drawCircle(Offset(x, y), particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
