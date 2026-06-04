import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConfirmationModalState {
  final bool isOpen;
  final String title;
  final String message;
  final String confirmLabel;
  final bool showDeviceDeleteToggle;
  final void Function(bool alsoDeleteFile)? onConfirm;
  final void Function()? onCancel;

  const ConfirmationModalState({
    this.isOpen = false,
    this.title = '',
    this.message = '',
    this.confirmLabel = 'Confirm',
    this.showDeviceDeleteToggle = false,
    this.onConfirm,
    this.onCancel,
  });

  ConfirmationModalState copyWith({
    bool? isOpen,
    String? title,
    String? message,
    String? confirmLabel,
    bool? showDeviceDeleteToggle,
    void Function(bool)? onConfirm,
    void Function()? onCancel,
  }) {
    return ConfirmationModalState(
      isOpen: isOpen ?? this.isOpen,
      title: title ?? this.title,
      message: message ?? this.message,
      confirmLabel: confirmLabel ?? this.confirmLabel,
      showDeviceDeleteToggle: showDeviceDeleteToggle ?? this.showDeviceDeleteToggle,
      onConfirm: onConfirm ?? this.onConfirm,
      onCancel: onCancel ?? this.onCancel,
    );
  }
}

final confirmationModalProvider =
    StateProvider<ConfirmationModalState>((ref) => const ConfirmationModalState());
