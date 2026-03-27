import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadsSelectionState {
  final Set<String> selectedIds;
  final bool isSelectionMode;

  const DownloadsSelectionState({
    this.selectedIds = const {},
    this.isSelectionMode = false,
  });

  DownloadsSelectionState copyWith({
    Set<String>? selectedIds,
    bool? isSelectionMode,
  }) {
    return DownloadsSelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    );
  }
}

class DownloadsSelectionNotifier extends StateNotifier<DownloadsSelectionState> {
  DownloadsSelectionNotifier() : super(const DownloadsSelectionState());

  void toggleItem(String id) {
    final newSelectedIds = Set<String>.from(state.selectedIds);
    if (newSelectedIds.contains(id)) {
      newSelectedIds.remove(id);
    } else {
      newSelectedIds.add(id);
    }

    if (newSelectedIds.isEmpty) {
      state = state.copyWith(selectedIds: {}, isSelectionMode: false);
    } else {
      state = state.copyWith(selectedIds: newSelectedIds, isSelectionMode: true);
    }
  }

  void activate(String id) {
    state = state.copyWith(
      isSelectionMode: true,
      selectedIds: {id},
    );
  }

  void clear() {
    state = const DownloadsSelectionState();
  }
}

final downloadsSelectionProvider =
    StateNotifierProvider<DownloadsSelectionNotifier, DownloadsSelectionState>((ref) {
  return DownloadsSelectionNotifier();
});
