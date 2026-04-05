import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/env.dart';
import '../../domain/models/user_profile.dart';
import '../../data/local/database.dart';

final supabaseClient = Supabase.instance.client;

/// Provides the current Supabase User
final authStateProvider = StreamProvider<User?>((ref) {
  return supabaseClient.auth.onAuthStateChange.map((event) => event.session?.user);
});

/// Provides the current session
final sessionProvider = Provider<Session?>((ref) {
  return supabaseClient.auth.currentSession;
});

/// Notifier for the User Profile
class ProfileNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return null;

    return _fetchProfile(user.id);
  }

  Future<UserProfile?> _fetchProfile(String userId) async {
    try {
      final data = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return UserProfile.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// Check if a username is unique
  Future<bool> isUsernameUnique(String username) async {
    final res = await supabaseClient
        .from('profiles')
        .select('username')
        .eq('username', username)
        .maybeSingle();
    return res == null;
  }

  /// Signup with Email and Password
  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final unique = await isUsernameUnique(username);
    if (!unique) {
      throw Exception('Username already taken.');
    }

    // 1. Sign up the user
    final response = await supabaseClient.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );

    // 2. If signup is successful and we have a session, it means email confirmation is OFF.
    // If we have a user but NO session, it means "Confirm Email" is ON.
    if (response.user != null) {
      if (response.session != null) {
        // Confirmation OFF: User is already logged in. 
        // Set flag for security setup (requested by user for post-signup flow)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('needs_security_setup', true);
      } else {
        // Confirmation ON: User needs to check email. 
        // We do NOT attempt auto-login here because it would fail.
        print('Signup successful, but session is null - email confirmation required.');
      }
    }

    ref.invalidateSelf();
  }

  /// Sign In with Email and Password
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      ref.invalidateSelf();
    } catch (e) {
      print('Sign In Error: $e');
      rethrow;
    }
  }

  /// sign In with Google (Native Modal)
  Future<void> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: Env.googleWebClientId,
      );
      
      // Always sign out of Google first to force account picker
      await googleSignIn.signOut();
      
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return; // User canceled

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('No ID Token found.');
      }

      await supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      
      ref.invalidateSelf();
    } catch (e) {
      rethrow;
    }
  }

  /// Verify OTP for signup or login
  Future<void> verifyOtp({
    required String email,
    required String token,
    OtpType type = OtpType.signup,
  }) async {
    try {
      await supabaseClient.auth.verifyOTP(
        email: email,
        token: token,
        type: type,
      );
      ref.invalidateSelf();
    } catch (e) {
      print('OTP Verification Error: $e');
      rethrow;
    }
  }

  /// Sign Out with full data wipe (Fresh Start)
  Future<void> signOut() async {
    try {
      // Wipe all data
      await clearAllAppData();
    } catch (e) {
      print('Sign out error: $e');
      ref.invalidateSelf();
    }
  }

  /// Full app data wipe (DB, Prefs, Security, Auth)
  Future<void> clearAllAppData() async {
    try {
      // 1. Supabase Sign Out
      await supabaseClient.auth.signOut();

      // 2. Google Sign Out
      final googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }

      // 3. SQLite Wipe
      await AppDatabase.instance.clearAll();

      // 4. Shared Preferences Wipe
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      ref.invalidateSelf();
    } catch (e) {
      print('Error during clearAllAppData: $e');
    }
  }

  /// Reset Password
  Future<void> resetPassword(String email) async {
    await supabaseClient.auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? null : 'io.supabase.daniewatch://login-callback/');
  }

  /// Update Password (specifically for recovery or manual change)
  Future<void> updatePassword(String newPassword) async {
    await supabaseClient.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    ref.invalidateSelf();
  }

  /// Update Email
  Future<void> updateEmail(String newEmail) async {
    await supabaseClient.auth.updateUser(
      UserAttributes(email: newEmail),
    );
    ref.invalidateSelf();
  }

  /// Update Username
  Future<void> updateUsername(String newUsername) async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) return;

    final unique = await isUsernameUnique(newUsername);
    if (!unique) {
      throw Exception('Username already taken.');
    }

    await supabaseClient
        .from('profiles')
        .update({'username': newUsername})
        .eq('id', user.id);
    
    ref.invalidateSelf();
  }

  /// Upload Avatar
  Future<void> uploadAvatar(String filePath) async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) return;

    final file = File(filePath);
    final fileExt = filePath.split('.').last;
    final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    // 1. Upload to Storage
    await supabaseClient.storage.from('avatars').upload(
          fileName,
          file,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );

    // 2. Get Public URL
    final avatarUrl = supabaseClient.storage.from('avatars').getPublicUrl(fileName);

    // 3. Update Profile
    await supabaseClient
        .from('profiles')
        .update({'avatar_url': avatarUrl})
        .eq('id', user.id);
    
    ref.invalidateSelf();
  }

  /// Delete Avatar
  Future<void> deleteAvatar() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) return;

    final profile = state.valueOrNull;
    if (profile?.avatarUrl == null) return;

    // Extract file path from URL (Supabase Specific)
    final uri = Uri.parse(profile!.avatarUrl!);
    final pathSegments = uri.pathSegments;
    // Expected format: /storage/v1/object/public/avatars/USER_ID/FILENAME
    final fileName = pathSegments.sublist(pathSegments.indexOf('avatars') + 1).join('/');

    // 1. Delete from Storage
    await supabaseClient.storage.from('avatars').remove([fileName]);

    // 2. Update Profile
    await supabaseClient
        .from('profiles')
        .update({'avatar_url': null})
        .eq('id', user.id);
    
    ref.invalidateSelf();
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfile?>(
  () => ProfileNotifier(),
);
