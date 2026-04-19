import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/settings_tile.dart';
import '../../../domain/models/user_profile.dart';
import '../../providers/watch_history_provider.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/utils/restart_widget.dart';

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
        _usernameController.text = oldName;
        if (mounted) {
          setState(() {
            _isEditing = false;
            _isUnique = null;
          });
          CustomToast.show(context, 'Failed to update username', type: ToastType.error);
        }
      }
    } else {
      _usernameController.text = oldName;
      setState(() {
        _isEditing = false;
        _isUnique = null;
      });
      if (newName.isNotEmpty) {
        CustomToast.show(context, 'Username is taken or already in use', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Profile Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildHeader(profile),
            const SizedBox(height: 28),
            _buildAllSettings(context, profile),
            const SizedBox(height: 40),
            _buildLogoutButton(context),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(UserProfile? profile) {
    return Column(
      children: [
        const Hero(
          tag: 'profile-avatar',
          child: UserAvatar(size: 100, canEdit: true),
        ),
        SizedBox(height: Responsive(context).h(24)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive(context).w(24)),
          child: TapRegion(
            onTapOutside: (_) {
              if (_isEditing) _saveUsername();
            },
            child: Column(
              children: [
                _isEditing ? _buildUsernameEditor() : _buildUsernameDisplay(profile),
                const SizedBox(height: 8),
                Text(
                  profile?.email ?? '',
                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameDisplay(UserProfile? profile) {
    return GestureDetector(
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
            style: GoogleFonts.plusJakartaSans(
                fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.0),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
        ],
      ),
    );
  }

  Widget _buildUsernameEditor() {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        TextField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          autofocus: true,
          onChanged: _onUsernameChanged,
          onSubmitted: (_) => _saveUsername(),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.0),
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
          _buildValidationIcon(),
      ],
    );
  }

  Widget _buildValidationIcon() {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: _isUnique! ? null : () => CustomToast.show(context, 'Username is already taken', type: ToastType.error),
        child: Icon(
          _isUnique! ? Icons.check_circle_outline : Icons.cancel_outlined,
          color: _isUnique! ? Colors.green : Colors.red,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildAllSettings(BuildContext context, UserProfile? profile) {
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.valueOrNull ?? false;
    final historyEnabled = ref.watch(continueWatchingSettingsProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Responsive(context).w(20)),
      child: Column(
        children: [
          if (isAdmin)
            SettingsTile(
              icon: Icons.admin_panel_settings_rounded,
              title: 'Admin Controls',
              infoText: 'Manage app content, send push notifications and control user access.',
              onTap: () => context.push('/admin-console'),
            ),
          SettingsTile(
            icon: Icons.person_outline_rounded,
            title: 'Account Settings',
            infoText: 'Update your email, change password, and manage login credentials.',
            onTap: () => context.push('/account-settings'),
          ),
          SettingsTile(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            infoText: 'Choose which push notifications you want to receive.',
            onTap: () => context.push('/notification-settings'),
          ),
          SettingsTile(
            icon: Icons.file_download_outlined,
            title: 'Downloads',
            infoText: 'View and manage your saved offline content.',
            onTap: () => CustomToast.show(context, 'Coming soon', type: ToastType.info),
          ),
          SettingsTile(
            icon: Icons.send_outlined,
            title: 'Requests',
            infoText: 'Submit content requests or report issues to the team.',
            onTap: () => CustomToast.show(context, 'Coming soon', type: ToastType.info),
          ),
          SettingsTile(
            icon: Icons.history_rounded,
            title: 'Watch History',
            infoText: 'Toggle to show or hide your recently watched titles on the homepage.',
            trailing: Switch.adaptive(
              value: historyEnabled,
              activeTrackColor: AppColors.primary,
              onChanged: (v) => ref.read(continueWatchingSettingsProvider.notifier).toggle(v),
            ),
            onTap: () => CustomToast.show(context, 'Coming soon', type: ToastType.info),
          ),
        ],
      ),
    );
  }



  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Responsive(context).w(24)),
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
            const Icon(Icons.logout_rounded, size: 20, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              'Logout',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Logout', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;

      // Start Logout Process with Cinematic Overlay
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black, // Initial black overlay
        transitionDuration: const Duration(milliseconds: 1500), // Slow cinematic fade
        pageBuilder: (context, anim1, anim2) {
          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: FadeTransition(
                opacity: anim1,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        strokeWidth: 2,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'RESETTING SESSION...',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      // Give time for animation to start
      await Future.delayed(const Duration(milliseconds: 1000));

      // NUCLEAR RESET
      await ref.read(profileProvider.notifier).signOut();

      // Final Delay for cinematic effect
      await Future.delayed(const Duration(milliseconds: 2000));

      // Restart the app from scratch using RestartWidget (will show the splash screen)
      if (context.mounted) {
        RestartWidget.restartApp(context);
      }
    }
  }
}
