import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the key of the currently hovered MovieCard.
/// Only one card can be active at a time across the whole app.
final activeCardProvider = StateProvider<String?>((ref) => null);
