import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      // encryptedSharedPreferences is deprecated but and ignored in v11+, but useful for older versions if supported.
      // However, we'll remove it to satisfy lint as requested.
    ),
  );
  final _localAuth = LocalAuthentication();

  static const _pinKey = 'app_lock_pin';
  static const _lockEnabledKey = 'app_lock_enabled';
  static const _biometricEnabledKey = 'biometric_enabled';

  /// Save the PIN to secure storage
  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  /// Get the PIN from secure storage
  Future<String?> getPin() async {
    return await _storage.read(key: _pinKey);
  }

  /// Verify if the provided PIN matches the stored PIN
  Future<bool> verifyPin(String pin) async {
    final storedPin = await getPin();
    return storedPin == pin;
  }

  /// Check if App Lock is enabled
  Future<bool> isLockEnabled() async {
    final val = await _storage.read(key: _lockEnabledKey);
    return val == 'true';
  }

  /// Enable or disable App Lock
  Future<void> setLockEnabled(bool enabled) async {
    await _storage.write(key: _lockEnabledKey, value: enabled.toString());
    if (!enabled) {
      // If disabling lock, also disable biometrics and clear PIN?
      // Usually better to keep PIN but disable the wall.
      await setBiometricEnabled(false);
    }
  }

  /// Check if Biometrics is enabled for app unlock
  Future<bool> isBiometricEnabled() async {
    final val = await _storage.read(key: _biometricEnabledKey);
    return val == 'true';
  }

  /// Enable or disable Biometric unlock
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricEnabledKey, value: enabled.toString());
  }

  /// Check if the device supports biometrics
  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (_) {
      return <BiometricType>[];
    }
  }

  /// Authenticate using biometrics
  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock DanieWatch',
        // version 2.0.0+ uses AuthenticationOptions but let's see if 
        // we can get away with defaults first to ensure compilation.
      );
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Clear all security settings (e.g., on logout if desired, but usually keep local app lock)
  Future<void> clearAll() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _lockEnabledKey);
    await _storage.delete(key: _biometricEnabledKey);
  }
}
