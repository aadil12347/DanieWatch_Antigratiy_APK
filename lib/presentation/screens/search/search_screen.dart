import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/filter_modal_provider.dart';
import '../../widgets/filter_selector_sheet.dart';
import '../../widgets/movie_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final currentQuery = ref.read(searchProvider).query;
    if (currentQuery.isNotEmpty) {
      _searchController.text = currentQuery;
    }
    _searchFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // If the user taps away, unfocus. If they tap the text field, focus.
    // Trigger a rebuild so the animated layout changes happen smoothly.
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.removeListener(_onFocusChange);
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).search(query);
  }

  List<ManifestItem> _getFilteredItems(List<ManifestItem> allItems, SearchState searchState, Map<String, ManifestItem> index) {
    List<ManifestItem> baseList;
    
    if (searchState.query.trim().isNotEmpty) {
      // Use FTS results mapping
      baseList = searchState.results
          .map((r) => index['${r.itemId}-${r.mediaType}'])
          .whereType<ManifestItem>()
          .toList();
    } else {
      // Use all items if query is empty
      baseList = List.from(allItems);
    }

    final f = searchState.filters;

    // Filter by Category
    if (f.category != 'All') {
      baseList = baseList.where((item) {
        if (f.category == 'Movies' && item.mediaType == 'movie') return true;
        if (f.category == 'TV Shows' && item.mediaType == 'tv') return true;
        if (f.category == 'Anime' && item.mediaType == 'anime') return true;
        return false;
      }).toList();
    }

    // Filter by Genre
    if (f.genre != 'All Genres') {
      final genreMap = {
        'Action': 28,
        'Animation': 16,
        'Comedy': 35,
        'Crime': 80,
        'Documentary': 99,
        'Drama': 18,
        'Family': 10751,
        'Fantasy': 14,
        'History': 36,
        'Horror': 27,
        'Music': 10402,
        'Mystery': 9648,
        'Romance': 10749,
        'Science Fiction': 878,
        'Thriller': 53,
        'War': 10752,
        'Western': 37,
      };

      if (genreMap.containsKey(f.genre)) {
         final genreId = genreMap[f.genre]!;
         baseList = baseList.where((item) => item.genreIds.contains(genreId)).toList();
      }
    }

    // Filter by Year
    if (f.year != 'All Years') {
       baseList = baseList.where((item) {
          if (item.releaseYear == null) return false;
          return item.releaseYear.toString() == f.year;
       }).toList();
    }

    // Sort By
    if (f.sortBy == 'Popularity (High to Low)') {
       baseList.sort((a, b) => b.voteCount.compareTo(a.voteCount));
    } else if (f.sortBy == 'Popularity (Low to High)') {
       baseList.sort((a, b) => a.voteCount.compareTo(b.voteCount));
    } else if (f.sortBy == 'Rating (High to Low)') {
       baseList.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    } else if (f.sortBy == 'Rating (Low to High)') {
       baseList.sort((a, b) => a.voteAverage.compareTo(b.voteAverage));
    } else if (f.sortBy == 'Release Date (Newest)') {
       baseList.sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
    }

    return baseList;
  }

  void _showSelectionModal(String title, String currentValue, List<String> options, Function(String) onChanged) {
    _searchFocus.unfocus(); // Ensure search keyboard goes away
    
    // The Category selector is outside the filter panel, so it acts as standard modal
    ref.read(filterModalProvider.notifier).state = FilterModalState(
      view: FilterView.optionsList,
      title: title,
      currentValue: currentValue,
      options: options,
      onChanged: onChanged,
      isSubMenu: false, // Cancel should close the modal completely
    );
  }

  Widget _buildModalSelector({
    required String title,
    required String value,
    required List<String> options,
    required Function(String) onChanged,
    bool isExpandedWidth = false,
  }) {
    return GestureDetector(
      onTap: () => _showSelectionModal(title, value, options, onChanged),
      child: Container(
        height: 48,
        width: isExpandedWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isExpandedWidth ? Colors.black.withOpacity(0.3) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: isExpandedWidth ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
        ),
        child: Row(
          mainAxisSize: isExpandedWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            if (isExpandedWidth) const Spacer(),
            if (!isExpandedWidth) const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final allItems = ref.watch(allItemsProvider);
    final trending = ref.watch(trendingProvider);
    final index = ref.watch(manifestIndexProvider);

    final showResults = searchState.query.isNotEmpty || searchState.filters.hasActiveFilters;
    final itemsToDisplay = showResults ? _getFilteredItems(allItems, searchState, index) : trending;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          // Unfocus when tapping anywhere outside
          onTap: () => _searchFocus.unfocus(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Text(
                    'Search All Content',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              // Search Bar Row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                       Expanded(
                         child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                               controller: _searchController,
                               focusNode: _searchFocus,
                               style: const TextStyle(color: Colors.white, fontSize: 16),
                               decoration: InputDecoration(
                                  hintText: 'Search all content...',
                                  hintStyle: TextStyle(color: AppColors.textMuted),
                                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                               ),
                               onChanged: _onSearchChanged,
                            ),
                         ),
                       ),
                       // Animated Size handles expanding/collapsing of buttons naturally
                       AnimatedSize(
                         duration: const Duration(milliseconds: 200),
                         curve: Curves.easeInOut,
                         child: Row(
                           mainAxisSize: MainAxisSize.min,
                           children: _searchFocus.hasFocus ? [] : [
                             const SizedBox(width: 12),
                             Container(
                               height: 48,
                               width: 48,
                               decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                               ),
                               child: IconButton(
                                  icon: const Icon(Icons.tune_rounded, color: Colors.white),
                                  onPressed: () {
                                    _searchFocus.unfocus();
                                    final currentState = ref.read(filterModalProvider);
                                    if (currentState.isOpen) {
                                      ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.none);
                                    } else {
                                      ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.mainPanel);
                                    }
                                  },
                               ),
                             ),
                             const SizedBox(width: 12),
                             // Type Modal Selector
                             _buildModalSelector(
                               title: 'Select Category',
                               value: searchState.filters.category,
                               options: ['All', 'Movies', 'TV Shows', 'Anime'],
                               onChanged: (val) {
                                  ref.read(searchProvider.notifier).updateFilters(searchState.filters.copyWith(category: val));
                               },
                             ),
                           ],
                         ),
                       ),
                    ],
                  ),
                ),
              ),
          
              // Expanding Filters Panel (Removed)
          
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
          
              // Content Title
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    showResults 
                      ? (searchState.query.isNotEmpty ? 'Search Results for "${searchState.query}"' : 'Search Results')
                      : 'Trending Now',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
          
              // Grid Content
              _buildGridContent(searchState, itemsToDisplay),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridContent(SearchState searchState, List<ManifestItem> items) {
    if (searchState.isSearching) {
       return _buildShimmerSliverGrid(3);
    }
    
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.search_off_rounded, size: 72, color: Colors.white30),
              SizedBox(height: 16),
              Text('No results found', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Try adjusting your filters or search terms.', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.paddingOf(context).bottom + 100),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return MovieCard(
              key: ValueKey('${items[index].id}_$index'),
              item: items[index],
              onTap: () => context.push('/search-details/${items[index].mediaType}/${items[index].id}'),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildShimmerSliverGrid(int crossAxisCount) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => Shimmer.fromColors(
            baseColor: AppColors.surface,
            highlightColor: AppColors.surfaceElevated.withAlpha(100),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          childCount: crossAxisCount * 4,
        ),
      ),
    );
  }
}
