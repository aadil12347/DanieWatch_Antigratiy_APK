import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls the support modal open/closed state.
/// When true, the bottom navbar morphs into the support request modal.
final supportModalProvider = StateProvider<bool>((ref) => false);
