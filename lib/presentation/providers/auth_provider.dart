import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/config/env.dart';
import '../../domain/models/user_profile.dart';

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

    // 2. If signup is successful and we have a user but no session (confirm email might be on),
    // or even if we have a session, we'll try to sign in explicitly to be sure.
    // NOTE: This will fail if "Confirm Email" is enabled in Supabase, but it's what the user requested.
    if (response.user != null && response.session == null) {
      try {
        await signIn(email: email, password: password);
      } catch (e) {
        // If it fails here, it's likely due to email confirmation being required.
        // We don't rethrow because the signup itself succeeded.
        print('Auto-login after signup failed: $e');
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

  /// Sign Out
  Future<void> signOut() async {
    try {
      // 1. Sign out of Supabase
      await supabaseClient.auth.signOut();
      
      // 2. Sign out of Google to ensure account selection next time
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      
      // 3. Close the app to prevent session residue and lifecycle crashes
      // This is a "Fresh Start" workaround requested by the user
      await SystemNavigator.pop();
    } catch (e) {
      print('Sign out error: $e');
      // If closing fails, we still want to ensure state is invalidated
      ref.invalidateSelf();
    }
  }

  /// Reset Password
  Future<void> resetPassword(String email) async {
    await supabaseClient.auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? null : 'io.supabase.daniewatch://login-callback/');
  }

  /// Update Password (specifically for recovery)
  Future<void> updatePassword(String newPassword) async {
    await supabaseClient.auth.updateUser(
      UserAttributes(password: newPassword),
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
