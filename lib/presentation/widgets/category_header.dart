import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/search_provider.dart';
import '../providers/filter_modal_provider.dart';

/// The page title row — scrolls naturally with content.
class CategoryTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const CategoryTitle({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.lora(
              color: AppColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The search bar + filter button — used inside a floating SliverPersistentHeader.
class CategorySearchBar extends ConsumerWidget {
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;

  const CategorySearchBar({
    super.key,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider);
    final hasSearch = searchState.query.isNotEmpty;

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: searchFocus.hasFocus 
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : AppColors.border,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: searchController,
                focusNode: searchFocus,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 15),
                  prefixIcon: Icon(Icons.search,
                      color: Colors.white.withValues(alpha: 0.4), size: 22),
                  suffixIcon: hasSearch
                      ? GestureDetector(
                          onTap: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                          child: Icon(Icons.close,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 20),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: onSearchChanged,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              searchFocus.unfocus();
              final currentState = ref.read(filterModalProvider);
              if (currentState.isOpen) {
                ref.read(filterModalProvider.notifier).state =
                    const FilterModalState(view: FilterView.none);
              } else {
                ref.read(filterModalProvider.notifier).state =
                    const FilterModalState(view: FilterView.mainPanel);
              }
            },
            child: Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

/// Active filter chips row — scrolls with content.
class CategoryFilterChips extends ConsumerWidget {
  const CategoryFilterChips({super.key});

  List<String> _getActiveFilterLabels(SearchState s) {
    final labels = <String>[];
    final f = s.filters;

    labels.addAll(f.categories);
    labels.addAll(f.regions);
    labels.addAll(f.genres);
    labels.addAll(f.years);
    if (f.sortBy != 'Popularity') labels.add(f.sortBy);
    return labels;
  }

  void _removeFilter(String label, SearchState state, WidgetRef ref) {
    final f = state.filters;
    if (f.categories.contains(label)) {
      final newSet = Set<String>.from(f.categories)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(categories: newSet));
    } else if (f.regions.contains(label)) {
      final newSet = Set<String>.from(f.regions)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(regions: newSet));
    } else if (f.genres.contains(label)) {
      final newSet = Set<String>.from(f.genres)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(genres: newSet));
    } else if (f.years.contains(label)) {
      final newSet = Set<String>.from(f.years)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(years: newSet));
    } else if (f.sortBy == label) {
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(sortBy: 'Popularity'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider);
    final activeFilterLabels = _getActiveFilterLabels(searchState);

    if (activeFilterLabels.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        itemCount: activeFilterLabels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activeFilterLabels[idx],
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeFilter(
                      activeFilterLabels[idx], searchState, ref),
                  child: const Icon(Icons.close,
                      color: Colors.white54, size: 14),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// SliverPersistentHeader delegate for the floating search bar.
/// Shows/hides based on scroll direction (floating behavior).
class FloatingSearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;

  FloatingSearchBarDelegate({
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
  });

  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return CategorySearchBar(
      searchController: searchController,
      searchFocus: searchFocus,
      onSearchChanged: onSearchChanged,
    );
  }

  @override
  bool shouldRebuild(covariant FloatingSearchBarDelegate oldDelegate) => false;
}

/// Legacy combined CategoryHeader for backward compatibility.
/// @deprecated Use CategoryTitle + FloatingSearchBarDelegate + CategoryFilterChips instead.
class CategoryHeader extends ConsumerWidget {
  final String title;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;
  final Widget? trailing;

  const CategoryHeader({
    super.key,
    required this.title,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.trailing,
  });

  List<String> _getActiveFilterLabels(SearchState s) {
    final labels = <String>[];
    final f = s.filters;

    labels.addAll(f.categories);
    labels.addAll(f.regions);
    labels.addAll(f.genres);
    labels.addAll(f.years);
    if (f.sortBy != 'Popularity') labels.add(f.sortBy);
    return labels;
  }

  void _removeFilter(String label, SearchState state, WidgetRef ref) {
    final f = state.filters;
    if (f.categories.contains(label)) {
      final newSet = Set<String>.from(f.categories)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(categories: newSet));
    } else if (f.regions.contains(label)) {
      final newSet = Set<String>.from(f.regions)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(regions: newSet));
    } else if (f.genres.contains(label)) {
      final newSet = Set<String>.from(f.genres)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(genres: newSet));
    } else if (f.years.contains(label)) {
      final newSet = Set<String>.from(f.years)..remove(label);
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(years: newSet));
    } else if (f.sortBy == label) {
      ref.read(searchProvider.notifier).updateFilters(f.copyWith(sortBy: 'Popularity'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider);
    final activeFilterLabels = _getActiveFilterLabels(searchState);
    final hasSearch = searchState.query.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Elegant Heading
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.lora(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        
        // Search bar + Filter icon
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: searchFocus.hasFocus
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.border,
                    width: 1,
                  ),
                  ),
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 15),
                      prefixIcon: Icon(Icons.search,
                          color: Colors.white.withValues(alpha: 0.4), size: 22),
                      suffixIcon: hasSearch
                          ? GestureDetector(
                              onTap: () {
                                searchController.clear();
                                onSearchChanged('');
                              },
                              child: Icon(Icons.close,
                                  color: Colors.white.withValues(alpha: 0.4),
                                  size: 20),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: onSearchChanged,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  searchFocus.unfocus();
                  final currentState = ref.read(filterModalProvider);
                  if (currentState.isOpen) {
                    ref.read(filterModalProvider.notifier).state =
                        const FilterModalState(view: FilterView.none);
                  } else {
                    ref.read(filterModalProvider.notifier).state =
                        const FilterModalState(view: FilterView.mainPanel);
                  }
                },
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),

        // Active Filter chips
        if (activeFilterLabels.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              itemCount: activeFilterLabels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        activeFilterLabels[idx],
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _removeFilter(
                            activeFilterLabels[idx], searchState, ref),
                        child: const Icon(Icons.close,
                            color: Colors.white54, size: 14),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
