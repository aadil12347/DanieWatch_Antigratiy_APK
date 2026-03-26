import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FilterView { none, mainPanel, optionsList }

class FilterModalState {
  final FilterView view;
  final String title;
  final String currentValue;
  final List<String> options;
  final void Function(String)? onChanged;
  final bool isSubMenu; // If true, cancel returns to mainPanel instead of none

  bool get isOpen => view != FilterView.none;

  const FilterModalState({
    this.view = FilterView.none,
    this.title = '',
    this.currentValue = '',
    this.options = const [],
    this.onChanged,
    this.isSubMenu = false,
  });

  FilterModalState copyWith({
    FilterView? view,
    String? title,
    String? currentValue,
    List<String>? options,
    void Function(String)? onChanged,
    bool? isSubMenu,
  }) {
    return FilterModalState(
      view: view ?? this.view,
      title: title ?? this.title,
      currentValue: currentValue ?? this.currentValue,
      options: options ?? this.options,
      onChanged: onChanged ?? this.onChanged,
      isSubMenu: isSubMenu ?? this.isSubMenu,
    );
  }
}

final filterModalProvider = StateProvider<FilterModalState>((ref) {
  return const FilterModalState();
});
