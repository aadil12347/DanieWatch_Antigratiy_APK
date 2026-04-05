import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/user_avatar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isEditing = false;
  late TextEditingController _usernameController;
  final FocusNode _usernameFocusNode = FocusNode();
  bool? _isUnique;
  bool _isValidating = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).valueOrNull;
    _usernameController = TextEditingController(text: profile?.username);
    _usernameFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_usernameFocusNode.hasFocus && _isEditing) {
      _saveUsername();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _usernameFocusNode.removeListener(_onFocusChange);
    _usernameFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    
    if (value.trim().isEmpty || value == ref.read(profileProvider).valueOrNull?.username) {
      setState(() {
        _isUnique = null;
        _isValidating = false;
      });
      return;
    }

    setState(() => _isValidating = true);
    
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final isUnique = await ref.read(profileProvider.notifier).isUsernameUnique(value.trim());
      if (mounted) {
        setState(() {
          _isUnique = isUnique;
          _isValidating = false;
        });
      }
    });
  }

  Future<void> _saveUsername() async {
    final profile = ref.read(profileProvider).valueOrNull;
    final oldName = profile?.username ?? '';
    final newName = _usernameController.text.trim();

    if (newName.isEmpty || newName == oldName) {
      setState(() => _isEditing = false);
      return;
    }

    if (_isUnique == true) {
      try {
        await ref.read(profileProvider.notifier).updateUsername(newName);
        if (mounted) setState(() => _isEditing = false);
      } catch (e) {
        // Revert and show error
        _usernameController.text = oldName;
        if (mounted) {
          setState(() {
            _isEditing = false;
            _isUnique = null;
          });
          CustomToast.show(
            context,
            'Failed to update username',
            type: ToastType.error,
          );
        }
      }
    } else {
      // Revert if not unique or invalid
      _usernameController.text = oldName;
      setState(() {
        _isEditing = false;
        _isUnique = null;
      });
      if (newName.isNotEmpty) {
        CustomToast.show(
          context,
          'Username is taken or already in use',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;

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
          'Profile Settings',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Avatar Top Center
            const Center(
              child: Hero(
                tag: 'profile-avatar',
                child: UserAvatar(
                  size: 100, // Balanced size: not very small
                  canEdit: true,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Username Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TapRegion(
                onTapOutside: (_) {
                  if (_isEditing) _saveUsername();
                },
                child: Column(
                  children: [
                    _isEditing 
                      ? _buildUsernameEditor()
                      : GestureDetector(
                          onTap: () => setState(() {
                            _usernameController.text = profile?.username ?? '';
                            _isEditing = true;
                            _isUnique = null;
                            _usernameFocusNode.requestFocus();
                          }),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                profile?.username ?? 'User',
                                style: GoogleFonts.outfit(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                            ],
                          ),
                        ),
                    const SizedBox(height: 8),
                    Text(
                      profile?.email ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 10),
            
            // Account Settings Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildActionTile(
                context,
                icon: Icons.manage_accounts_outlined,
                title: 'Account Settings',
                onTap: () => context.push('/account-settings'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ElevatedButton(
            onPressed: () => _handleLogout(context, ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout_rounded, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Logout',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsernameEditor() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              controller: _usernameController,
              focusNode: _usernameFocusNode,
              autofocus: true,
              onChanged: _onUsernameChanged,
              onSubmitted: (_) => _saveUsername(),
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'Username',
                hintStyle: const TextStyle(color: Colors.white24),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 40),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
            if (_isValidating)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_isUnique != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: _isUnique! ? null : () => CustomToast.show(
                    context,
                    'Username is already taken',
                    type: ToastType.error,
                  ),
                  child: Icon(
                    _isUnique! ? Icons.check_circle_outline : Icons.cancel_outlined,
                    color: _isUnique! ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 24),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  // _showEditUsernameDialog removed as per request

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Logout', style: GoogleFonts.outfit(color: Colors.white)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(profileProvider.notifier).signOut();
      // Router will handle redirection based on auth state
    }
  }
}
