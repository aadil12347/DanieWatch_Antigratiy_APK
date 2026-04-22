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
import '../../widgets/morphing_search.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  late TabController _tabController;

  /// Tracks whether we are programmatically changing tabs (to avoid circular updates)
  bool _isProgrammatic = false;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: TopNavbar.items.length,
      vsync: this,
      initialIndex: 0, // Explore is default
    );

    // Sync tab changes → update search provider filters
    _tabController.addListener(_onTabChanged);

    final currentQuery = ref.read(searchProvider('explore')).query;
    if (currentQuery.isNotEmpty) {
      _searchController.text = currentQuery;
    }
    _searchFocus.addListener(_onFocusChange);

    // Register scroll for Explore tab (index 1 in bottom nav)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scrollProvider).register(1, ScrollController());
    });
  }

  void _onTabChanged() {
    if (_isProgrammatic) return;
    // Fires on both tap and animation completion
    if (!_tabController.indexIsChanging) {
      _syncFiltersToTab(_tabController.index);
    }
  }

  /// Update search provider filters based on the currently active tab
  void _syncFiltersToTab(int index) {
    final label = TopNavbar.items[index];
    ref.read(searchProvider('explore').notifier).setNavCategory(label);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
      ref.read(searchFocusProvider.notifier).state = _searchFocus.hasFocus;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.removeListener(_onFocusChange);
    ref.read(searchFocusProvider.notifier).state = false;
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider('explore').notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider('explore'));
    final activeCategories = searchState.filters.categories;

    // Determine the active title
    final activeTitle = activeCategories.isNotEmpty
        ? activeCategories.first
        : searchState.filters.genres.isNotEmpty
            ? searchState.filters.genres.first
            : 'Explore';

    // Sync tab controller to match external filter changes (e.g. from Home screen "See All")
    _syncTabToFilters(searchState);

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: Column(
            children: [
              // Fixed header — pinned above everything
              MorphingSearchHeaderRow(
                title: activeTitle,
                searchController: _searchController,
                searchFocus: _searchFocus,
                onSearchChanged: _onSearchChanged,
                contextId: 'explore',
                showFilterButton: true,
              ),
              // Top navbar — pinned below header
              TopNavbar(tabController: _tabController),
              // Filter chips — pinned below navbar (only shows user-applied filters)
              const CategoryFilterChips(),
              // Padding between header area and content
              const SizedBox(height: 8),
              // Swipeable page content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: TopNavbar.items.map((label) {
                    return _CategoryPage(
                      categoryLabel: label,
                      searchController: _searchController,
                      searchFocus: _searchFocus,
                      onSearchChanged: _onSearchChanged,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Keep tab controller in sync if filters were changed externally
  /// (e.g. navigating from Home → See All for a category).
  void _syncTabToFilters(SearchState searchState) {
    final cats = searchState.filters.categories;
    int targetIndex = 0; // default to Explore

    if (cats.isNotEmpty) {
      var cat = cats.first;
      // Map alternative names to navbar labels
      if (cat == 'K-Drama') cat = 'Korean';
      final idx = TopNavbar.items.indexOf(cat);
      if (idx >= 0) targetIndex = idx;
    }

    if (_tabController.index != targetIndex && !_tabController.indexIsChanging) {
      _isProgrammatic = true;
      _tabController.animateTo(targetIndex);
      // Reset flag after animation completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isProgrammatic = false;
      });
    }
  }
}

/// Individual content page for each category tab.
/// Each page has its own scroll controller and shows a grid of items.
class _CategoryPage extends ConsumerStatefulWidget {
  final String categoryLabel;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;

  const _CategoryPage({
    required this.categoryLabel,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
  });

  @override
  ConsumerState<_CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<_CategoryPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (widget.searchFocus.hasFocus) {
      widget.searchFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin

    final searchState = ref.watch(searchProvider('explore'));
    final index = ref.watch(manifestIndexProvider);

    final hasSearch = searchState.query.trim().isNotEmpty;
    final hasFilters = searchState.filters.hasActiveFilters;
    final showResults = hasSearch || hasFilters;

    // Get the correct data source for this category
    final categoryItems = _getCategoryItems(widget.categoryLabel);

    return categoryItems.when(
      loading: () => CustomScrollView(
        controller: _scrollController,
        slivers: [_buildShimmerGrid()],
      ),
      error: (err, _) => CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(child: Center(child: Text('Error: $err'))),
        ],
      ),
      data: (items) {
        // Determine enforced category for FilterUtils
        String? enforceCategory;
        const categoryPages = {
          'Anime', 'Korean', 'K-Drama', 'Bollywood',
          'Hollywood', 'Chinese', 'Punjabi', 'Pakistani',
        };
        final filterCat = searchState.filters.categories;
        if (filterCat.isNotEmpty && categoryPages.contains(filterCat.first)) {
          enforceCategory = filterCat.first;
        }

        // Apply filters when any filter or search is active
        final itemsToDisplay = showResults
            ? FilterUtils.getFilteredItems(
                allItems: items,
                searchState: searchState,
                index: index,
                enforceCategory: enforceCategory,
              )
            : items;

        return CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _buildContentSlivers(
            searchState,
            hasSearch,
            showResults,
            itemsToDisplay,
            items,
          ),
        );
      },
    );
  }

  AsyncValue<List<ManifestItem>> _getCategoryItems(String label) {
    if (label == 'Korean') return ref.watch(koreanProvider);
    if (label == 'Anime') return ref.watch(animeProvider);
    if (label == 'Bollywood') return ref.watch(bollywoodProvider);
    if (label == 'Hollywood') return ref.watch(hollywoodProvider);
    if (label == 'Chinese') return ref.watch(chineseProvider);
    if (label == 'Punjabi') return ref.watch(punjabiProvider);
    // Explore — show all items
    return ref.watch(globalItemsProvider);
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

    // Filters or search active but no matching results
    if (showResults && itemsToDisplay.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyResultsView(),
        ),
      ];
    }

    // Active search or filter with results → show ONLY filtered items
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
          gridPad, r.h(4), gridPad, MediaQuery.paddingOf(context).bottom + r.h(100)),
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
      padding: EdgeInsets.fromLTRB(gridPad, r.h(4), gridPad, r.h(24)),
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
