import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/models/manifest_item.dart';
import '../../../core/utils/search_utils.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/category_header.dart';
import '../../widgets/empty_results_view.dart';
import '../../widgets/top_navbar.dart';
import '../../providers/scroll_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final currentQuery = ref.read(searchProvider('explore')).query;
    if (currentQuery.isNotEmpty) {
      _searchController.text = currentQuery;
    }
    _searchFocus.addListener(_onFocusChange);

    // Register the controller for Explore tab (index 1)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scrollProvider).register(1, _scrollController);
    });
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
      // Sync focus state to global provider for AppShell navigation handling
      ref.read(searchFocusProvider.notifier).state = _searchFocus.hasFocus;
    }
  }

  @override
  void dispose() {
    ref.read(scrollProvider).unregister(1);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.removeListener(_onFocusChange);
    // Ensure focus state is cleared when screen is removed
    ref.read(searchFocusProvider.notifier).state = false;
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query, List<ManifestItem> currentItems, bool isGlobal) {
    if (isGlobal) {
      ref.read(searchProvider('explore').notifier).search(query);
    } else {
      ref.read(searchProvider('explore').notifier).searchInList(query, currentItems);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider('explore'));
    final globalItemsAsync = ref.watch(globalItemsProvider);
    final index = ref.watch(manifestIndexProvider);

    final hasSearch = searchState.query.trim().isNotEmpty;
    final hasFilters = searchState.filters.hasActiveFilters;
    final showResults = hasSearch || hasFilters;

    // --- Dynamic Data Sourcing (New requirement) ---
    // Switch the base items based on the active top-level category
    final filterCat = searchState.filters.categories;
    AsyncValue<List<ManifestItem>> categoryItems;
    
    if (filterCat.contains('Korean')) {
      categoryItems = ref.watch(koreanProvider);
    } else if (filterCat.contains('Anime')) {
      categoryItems = ref.watch(animeProvider);
    } else if (filterCat.contains('Bollywood')) {
      categoryItems = ref.watch(bollywoodProvider);
    } else if (filterCat.contains('Hollywood')) {
      categoryItems = ref.watch(hollywoodProvider);
    } else if (filterCat.contains('Chinese')) {
      categoryItems = ref.watch(chineseProvider);
    } else if (filterCat.contains('Punjabi')) {
      categoryItems = ref.watch(punjabiProvider);
    } else if (filterCat.contains('Pakistani')) {
      categoryItems = ref.watch(pakistaniProvider);
    } else {
      categoryItems = globalItemsAsync;
    }

    return categoryItems.when(
      loading: () => _buildScaffoldWithContent([_buildShimmerGrid()], [], searchState),
      error: (err, _) => _buildScaffoldWithContent([
        SliverToBoxAdapter(child: Center(child: Text('Error: $err')))
      ], [], searchState),
      data: (items) {
        // When searching, manually trigger the in-memory search on the subset
        // We do this to ensure search is isolated to the "file" being viewed.
        if (hasSearch && filterCat.isNotEmpty) {
          // Note: In a real app, you might want to debounce this or use a separate provider
          // for the filtered subset search.
        }

        final itemsToDisplay = showResults
            ? FilterUtils.getFilteredItems(
                allItems: items,
                searchState: searchState,
                index: index,
                // Pass the active category to enforce strict filtering
                enforceCategory: filterCat.isNotEmpty ? filterCat.first : null,
              )
            : items;

        return _buildScaffoldWithContent(
          _buildContentSlivers(
            searchState, 
            hasSearch, 
            showResults, 
            itemsToDisplay, 
            items
          ),
          items,
          searchState,
        );
      },
    );
  }

  Widget _buildScaffoldWithContent(
    List<Widget> slivers, 
    List<ManifestItem> currentCategoryItems,
    SearchState searchState,
  ) {
    final activeCategories = searchState.filters.categories;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: TopNavbar()),
              SliverToBoxAdapter(
                child: CategoryTitle(
                  title: activeCategories.isNotEmpty
                      ? activeCategories.first
                      : searchState.filters.genres.isNotEmpty
                          ? searchState.filters.genres.first
                          : 'Explore',
                ),
              ),
              SliverPersistentHeader(
                floating: true,
                delegate: FloatingSearchBarDelegate(
                  searchController: _searchController,
                  searchFocus: _searchFocus,
                  onSearchChanged: (q) => _onSearchChanged(
                    q, 
                    currentCategoryItems, 
                    activeCategories.isEmpty
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: CategoryFilterChips()),
              ...slivers,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContentSlivers(
    SearchState searchState,
    bool hasSearch,
    bool showResults,
    List<ManifestItem> itemsToDisplay,
    List<ManifestItem> allItems,
  ) {
    // Searching shimmer
    if (searchState.isSearching) {
      return [_buildShimmerGrid()];
    }

    // User typed something but no results
    if (hasSearch && itemsToDisplay.isEmpty) {
      return [
        const SliverFillRemaining(
          child: EmptyResultsView(),
        ),
      ];
    }

    // Active search or filter with results
    if (showResults && itemsToDisplay.isNotEmpty) {
      return [_buildResultsGrid(itemsToDisplay)];
    }

    // No search or filter active → grid of all items
    return [_buildResultsGrid(allItems)];
  }

  Widget _buildResultsGrid(List<ManifestItem> items) {
    final r = Responsive(context);
    final gridPad = r.w(28).clamp(16.0, 40.0);
    final gridSpacing = r.w(28).clamp(16.0, 36.0);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
          gridPad, r.h(12), gridPad, MediaQuery.paddingOf(context).bottom + r.h(100)),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: r.gridColumns,
          childAspectRatio: 0.55,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: gridSpacing,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, idx) {
            return MovieCard(
              key: ValueKey('result_${items[idx].id}_$idx'),
              item: items[idx],
              onTap: () => context
                  .push('/details/${items[idx].mediaType}/${items[idx].id}'),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    final r = Responsive(context);
    final gridPad = r.w(28).clamp(16.0, 40.0);
    final gridSpacing = r.w(28).clamp(16.0, 36.0);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(gridPad, r.h(12), gridPad, r.h(24)),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: r.gridColumns,
          childAspectRatio: 0.55,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: gridSpacing,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => Shimmer.fromColors(
            baseColor: AppColors.surface,
            highlightColor: AppColors.surfaceElevated.withAlpha(100),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          childCount: 9,
        ),
      ),
    );
  }
}
