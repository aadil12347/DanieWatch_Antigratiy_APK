import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/security_service.dart';

final securityServiceProvider = Provider<SecurityService>((ref) => SecurityService());

class SecurityState {
  final bool isLockEnabled;
  final bool isBiometricEnabled;
  final bool hasPin;
  final bool canUseBiometrics;

  SecurityState({
    this.isLockEnabled = false,
    this.isBiometricEnabled = false,
    this.hasPin = false,
    this.canUseBiometrics = false,
  });

  SecurityState copyWith({
    bool? isLockEnabled,
    bool? isBiometricEnabled,
    bool? hasPin,
    bool? canUseBiometrics,
  }) {
    return SecurityState(
      isLockEnabled: isLockEnabled ?? this.isLockEnabled,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      hasPin: hasPin ?? this.hasPin,
      canUseBiometrics: canUseBiometrics ?? this.canUseBiometrics,
    );
  }
}

class SecurityNotifier extends AutoDisposeAsyncNotifier<SecurityState> {
  late final SecurityService _service;

  @override
  Future<SecurityState> build() async {
    _service = ref.watch(securityServiceProvider);
    
    final isLock = await _service.isLockEnabled();
    final isBio = await _service.isBiometricEnabled();
    final pin = await _service.getPin();
    final canBio = await _service.canCheckBiometrics();

    return SecurityState(
      isLockEnabled: isLock,
      isBiometricEnabled: isBio,
      hasPin: pin != null && pin.isNotEmpty,
      canUseBiometrics: canBio,
    );
  }

  Future<void> toggleAppLock(bool enabled) async {
    await _service.setLockEnabled(enabled);
    ref.invalidateSelf();
  }

  Future<void> toggleBiometrics(bool enabled) async {
    await _service.setBiometricEnabled(enabled);
    ref.invalidateSelf();
  }

  Future<void> updatePin(String pin) async {
    await _service.setPin(pin);
    // If setting PIN, we might implicitly want to enable lock if not already?
    // User might just be changing it.
    ref.invalidateSelf();
  }

  Future<bool> verifyPin(String pin) async {
    return await _service.verifyPin(pin);
  }

  Future<bool> authenticateWithBiometrics() async {
    return await _service.authenticate();
  }

  Future<void> clearAll() async {
    await _service.clearAll();
    ref.invalidateSelf();
  }
}

final securityProvider = AsyncNotifierProvider.autoDispose<SecurityNotifier, SecurityState>(
  () => SecurityNotifier(),
);
