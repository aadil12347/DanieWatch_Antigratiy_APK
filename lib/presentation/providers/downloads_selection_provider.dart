import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which section the selection originated from
enum SelectionSection { downloading, downloaded }

class DownloadsSelectionState {
  final Set<String> selectedIds;
  final bool isSelectionMode;
  final SelectionSection? section;

  const DownloadsSelectionState({
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.section,
  });

  DownloadsSelectionState copyWith({
    Set<String>? selectedIds,
    bool? isSelectionMode,
    SelectionSection? section,
  }) {
    return DownloadsSelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      section: section ?? this.section,
    );
  }
}

class DownloadsSelectionNotifier extends StateNotifier<DownloadsSelectionState> {
  DownloadsSelectionNotifier() : super(const DownloadsSelectionState());

  void toggleItem(String id, {SelectionSection? section}) {
    final newSelectedIds = Set<String>.from(state.selectedIds);
    if (newSelectedIds.contains(id)) {
      newSelectedIds.remove(id);
    } else {
      newSelectedIds.add(id);
    }

    if (newSelectedIds.isEmpty) {
      state = const DownloadsSelectionState();
    } else {
      state = state.copyWith(
        selectedIds: newSelectedIds,
        isSelectionMode: true,
      );
    }
  }

  void activate(String id, {required SelectionSection section}) {
    state = DownloadsSelectionState(
      isSelectionMode: true,
      selectedIds: {id},
      section: section,
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
