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
  final ScrollController _outerScrollController = ScrollController();

  late TabController _tabController;

  /// Tracks whether we are programmatically changing tabs (to avoid circular updates)
  bool _isProgrammatic = false;

  /// Tracks the last tab index we synced to filters, to avoid redundant updates
  int _lastSyncedTabIndex = 0;



  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: TopNavbar.items.length,
      vsync: this,
      initialIndex: 0,
      animationDuration: const Duration(milliseconds: 300), // Smooth red line slide
    );

    // Sync tab changes → update search provider filters
    _tabController.addListener(_onTabChanged);

    final currentQuery = ref.read(searchProvider('explore')).query;
    if (currentQuery.isNotEmpty) {
      _searchController.text = currentQuery;
    }
    _searchFocus.addListener(_onFocusChange);

    // Register outer scroll controller for scroll-to-top (Explore = bottom nav index 1)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scrollProvider).register(1, _outerScrollController);
      // Handle initial sync from external navigation (e.g. Home "See All")
      _syncTabToFiltersOnce();
    });
  }

  /// One-time sync on init for external filter changes (e.g. Home "See All")
  void _syncTabToFiltersOnce() {
    final searchState = ref.read(searchProvider('explore'));
    final cats = searchState.filters.categories;
    int targetIndex = 0;

    if (cats.isNotEmpty) {
      var cat = cats.first;
      if (cat == 'K-Drama') cat = 'Korean';
      final idx = TopNavbar.items.indexOf(cat);
      if (idx >= 0) targetIndex = idx;
    }

    if (_tabController.index != targetIndex) {
      _isProgrammatic = true;
      _tabController.animateTo(targetIndex);
      _lastSyncedTabIndex = targetIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isProgrammatic = false;
      });
    }
  }

  void _onTabChanged() {
    if (_isProgrammatic) return;

    // Only sync when the tab has settled (animation complete)
    if (!_tabController.indexIsChanging) {
      final newIndex = _tabController.index;
      if (newIndex != _lastSyncedTabIndex) {
        _lastSyncedTabIndex = newIndex;
        _syncFiltersToTab(newIndex);
      }
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
    ref.read(scrollProvider).unregister(1);
    _outerScrollController.dispose();
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

    // NOTE: We do NOT call _syncTabToFilters here in build() anymore.
    // That was causing the tab to fight user swipes. External sync is
    // handled once in initState via _syncTabToFiltersOnce().

    final bool isSearchBarOpen = ref.watch(searchBarOpenProvider);
    final bool isSearchActive = isSearchBarOpen ||
        _searchFocus.hasFocus ||
        _searchController.text.isNotEmpty;

    return PopScope(
      canPop: !isSearchActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isSearchActive) {
          // Close search instead of navigating back
          _searchController.clear();
          _onSearchChanged('');
          _searchFocus.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: GestureDetector(
            onTap: () => _searchFocus.unfocus(),
            child: Column(
              children: [
                // ── Pinned header — always visible ──
                MorphingSearchHeaderRow(
                  title: activeTitle,
                  searchController: _searchController,
                  searchFocus: _searchFocus,
                  onSearchChanged: _onSearchChanged,
                  contextId: 'explore',
                  showFilterButton: true,
                ),
                // Extra padding so cards don't appear too close behind the header
                Container(
                  height: 6,
                  color: AppColors.background,
                ),
                // ── Scrollable content: TopNavbar scrolls away, content stays ──
                Expanded(
                  child: NestedScrollView(
                    controller: _outerScrollController,
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      // Top navbar — scrolls with content (NOT pinned)
                      SliverToBoxAdapter(
                        child: TopNavbar(tabController: _tabController),
                      ),
                      // Filter chips — scrolls with content
                      const SliverToBoxAdapter(
                        child: CategoryFilterChips(),
                      ),
                      // Small gap between navbar area and grid content
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 8),
                      ),
                    ],
                    // Instant tab switch — no slide animation, pages kept alive
                    body: TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: TopNavbar.items.map((label) {
                        return _CategoryPage(
                          key: PageStorageKey('cat_$label'),
                          categoryLabel: label,
                          searchController: _searchController,
                          searchFocus: _searchFocus,
                          onSearchChanged: _onSearchChanged,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    super.key,
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
  @override
  bool get wantKeepAlive => true;

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
        slivers: [_buildShimmerGrid()],
      ),
      error: (err, _) => CustomScrollView(
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
          // Let NestedScrollView manage the scroll controller
          key: PageStorageKey('scroll_${widget.categoryLabel}'),
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
