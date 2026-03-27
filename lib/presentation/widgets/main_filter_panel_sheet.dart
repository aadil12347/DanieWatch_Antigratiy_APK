import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/search_provider.dart';
import '../providers/filter_modal_provider.dart';

class MainFilterPanelContent extends ConsumerStatefulWidget {
  const MainFilterPanelContent({super.key});

  @override
  ConsumerState<MainFilterPanelContent> createState() =>
      _MainFilterPanelContentState();
}

class _MainFilterPanelContentState
    extends ConsumerState<MainFilterPanelContent> {
  // Temporary filter state so changes only apply on "Apply"
  late SearchFilters _pendingFilters;

  @override
  void initState() {
    super.initState();
    _pendingFilters = ref.read(searchProvider).filters;
  }

  // ── Categories ──
  static const _categories = ['Movie', 'TV Shows', 'K-Drama', 'Anime'];

  // ── Regions ──
  static const _regions = [
    'US',
    'South Korea',
    'China',
    'Japan',
    'India',
    'UK'
  ];

  // ── Genres ──
  static const _genres = [
    'Action',
    'Comedy',
    'Romance',
    'Thriller',
    'Drama',
    'Horror',
    'Sci-Fi',
    'Fantasy',
    'Animation',
    'Documentary'
  ];

  // ── Years ──
  static const _years = [
    '2026',
    '2025',
    '2024',
    '2023',
    '2022',
    '2021',
    '2020',
    '2019',
    '2018'
  ];

  // ── Sort ──
  static const _sorts = ['Popularity', 'Latest Release'];

  Widget _buildMultiSelectSection(String title, List<String> options,
      Set<String> selectedValues, void Function(String) onToggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((option) {
            final isSelected = selectedValues.contains(option);
            return GestureDetector(
              onTap: () => onToggle(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSingleSelectSection(String title, List<String> options,
      String selectedValue, void Function(String) onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((option) {
            final isSelected = option == selectedValue;
            return GestureDetector(
              onTap: () => onTap(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final isCategoryPage = location == '/anime' || 
                          location == '/korean' || 
                          location == '/movies' || 
                          location == '/tv';

    final categoriesToDisplay = isCategoryPage ? ['Movie', 'Season'] : _categories;
    final sortsToDisplay = isCategoryPage ? ['Latest', 'Top Rated', 'Popularity'] : _sorts;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Title ──
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              'Sort & Filter',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // ── Scrollable filter options ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categories
                  _buildMultiSelectSection(
                    'Categories',
                    categoriesToDisplay,
                    _pendingFilters.categories,
                    (val) => setState(() {
                      final newSet =
                          Set<String>.from(_pendingFilters.categories);
                      if (newSet.contains(val)) {
                        newSet.remove(val);
                      } else {
                        newSet.add(val);
                      }
                      _pendingFilters =
                          _pendingFilters.copyWith(categories: newSet);
                    }),
                  ),

                  // Regions (Only on Explore page)
                  if (!isCategoryPage)
                    _buildMultiSelectSection(
                      'Regions',
                      _regions,
                      _pendingFilters.regions,
                      (val) => setState(() {
                        final newSet = Set<String>.from(_pendingFilters.regions);
                        if (newSet.contains(val)) {
                          newSet.remove(val);
                        } else {
                          newSet.add(val);
                        }
                        _pendingFilters =
                            _pendingFilters.copyWith(regions: newSet);
                      }),
                    ),

                  // Genre
                  _buildMultiSelectSection(
                    'Genre',
                    _genres,
                    _pendingFilters.genres,
                    (val) => setState(() {
                      final newSet = Set<String>.from(_pendingFilters.genres);
                      if (newSet.contains(val)) {
                        newSet.remove(val);
                      } else {
                        newSet.add(val);
                      }
                      _pendingFilters =
                          _pendingFilters.copyWith(genres: newSet);
                    }),
                  ),

                  // Time/Periods
                  _buildMultiSelectSection(
                    'Time/Periods',
                    _years,
                    _pendingFilters.years,
                    (val) => setState(() {
                      final newSet = Set<String>.from(_pendingFilters.years);
                      if (newSet.contains(val)) {
                        newSet.remove(val);
                      } else {
                        newSet.add(val);
                      }
                      _pendingFilters = _pendingFilters.copyWith(years: newSet);
                    }),
                  ),

                  // Sort
                  _buildSingleSelectSection(
                    'Sort',
                    sortsToDisplay,
                    _pendingFilters.sortBy,
                    (val) => setState(() {
                      _pendingFilters = _pendingFilters.copyWith(sortBy: val);
                    }),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Reset + Apply buttons ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                // Reset
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _pendingFilters = const SearchFilters();
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Apply
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        ref
                            .read(searchProvider.notifier)
                            .updateFilters(_pendingFilters);
                        ref.read(filterModalProvider.notifier).state =
                            const FilterModalState(view: FilterView.none);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Apply',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
