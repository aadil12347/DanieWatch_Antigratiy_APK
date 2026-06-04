import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global state provider for "Continue Watching" delete mode.
/// This allows other widgets (like HomeScreen) to reset the mode 
/// when clicking on the background.
final continueWatchingDeleteModeProvider = StateProvider<bool>((ref) => false);
