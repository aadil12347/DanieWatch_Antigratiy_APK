import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to manage ScrollControllers for the main navigation branches.
/// Each branch (Home, Explore, Favorite, Downloads) can register its controller here.
final scrollProvider = Provider((ref) => ScrollControllerManager());

class ScrollControllerManager {
  final Map<int, ScrollController> _controllers = {};

  /// Register a controller for a specific tab index.
  void register(int index, ScrollController controller) {
    _controllers[index] = controller;
  }

  /// Unregister a controller for a specific tab index.
  void unregister(int index) {
    _controllers.remove(index);
  }

  /// Smoothly scroll the controller at the given index to the top.
  void scrollToTop(int index) {
    final controller = _controllers[index];
    if (controller != null && controller.hasClients) {
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }
}
