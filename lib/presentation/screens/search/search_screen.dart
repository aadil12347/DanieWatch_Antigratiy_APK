import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';

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
    } else if (searchState.filters.genres.isNotEmpty) {
      final g = searchState.filters.genres.first;
      final idx = TopNavbar.items.indexOf(g);
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
    if (query.trim().isNotEmpty && _tabController.index != 0) {
      _isProgrammatic = true;
      _tabController.animateTo(0);
      _lastSyncedTabIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isProgrammatic = false;
      });
    }
    ref.read(searchProvider('explore').notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    // Listen for external filter updates (e.g. from Home See All)
    ref.listen(searchProvider('explore'), (previous, next) {
      if (previous?.filters != next.filters) {
        _syncTabToFiltersOnce();
      }
    });

    final searchState = ref.watch(searchProvider('explore'));
    final activeCategories = searchState.filters.categories;

    // Determine the active title
    final activeTitle = _tabController.index == 0
        ? 'Search'
        : (activeCategories.isNotEmpty
            ? activeCategories.first
            : searchState.filters.genres.isNotEmpty
                ? searchState.filters.genres.first
                : TopNavbar.items[_tabController.index]);

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
/// Supports infinite scroll — loads more pages as user scrolls down.
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

  /// The catalog slug for this category tab.
  String get _slug => categoryLabelToSlug(widget.categoryLabel);

  /// Trigger loading the next page when scroll is near the bottom.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      // Trigger when within 400px of the bottom
      if (metrics.pixels >= metrics.maxScrollExtent - 400) {
        ref.read(paginatedCategoryProvider(_slug).notifier).loadNextPage();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final searchState = ref.watch(searchProvider('explore'));

    // ── Dedicated Search Tab Landing & Results ──
    if (widget.categoryLabel == 'Search') {
      final hasSearch = searchState.query.trim().isNotEmpty;

      if (searchState.isSearching) {
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [_buildShimmerGrid()],
        );
      }

      if (!hasSearch) {
        // Landing state: clean empty landing with search prompt & quick suggestion tags
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _SearchLandingView(
                onTagSelected: (tag) {
                  widget.searchController.text = tag;
                  widget.onSearchChanged(tag);
                },
              ),
            ),
          ],
        );
      }

      if (searchState.results.isEmpty) {
        return const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyResultsView(),
            ),
          ],
        );
      }

      return CustomScrollView(
        key: const PageStorageKey('scroll_search_results'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildResultsGrid(searchState.results),
        ],
      );
    }

    final paginatedState = ref.watch(paginatedCategoryProvider(_slug));

    final hasSearch = searchState.query.trim().isNotEmpty;
    // Check for user-applied filters BEYOND the nav category.
    // The nav category alone should NOT trigger FilterUtils re-sorting,
    // because category providers already supply correctly filtered + sorted data
    // (with posting-record priority order preserved).
    final f = searchState.filters;
    final hasUserFilters = f.regions.isNotEmpty ||
        f.originalLanguages.isNotEmpty ||
        f.genres.isNotEmpty ||
        f.years.isNotEmpty ||
        f.sortBy != 'Popularity' ||
        f.categories.any((c) => c != searchState.navCategory && c != widget.categoryLabel);
    final showResults = hasSearch || hasUserFilters;

    return paginatedState.when(
      loading: () => CustomScrollView(
        slivers: [_buildShimmerGrid()],
      ),
      error: (err, _) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: Center(child: Text('Error: $err'))),
        ],
      ),
      data: (pagState) {
        final rawItems = pagState.items;

        // Determine enforced category for FilterUtils
        String? enforceCategory;
        const categoryPages = {
          'Action', 'Korean', 'K-Drama', 'Chinese', 'Anime', 'Comedy',
          'Thriller', 'Horror', 'Sci-Fi', 'Romance', 'Indian', 'Bollywood',
          'Hollywood', 'Punjabi', 'Pakistani',
        };
        final filterCat = searchState.filters.categories;
        if (filterCat.isNotEmpty && categoryPages.contains(filterCat.first)) {
          enforceCategory = filterCat.first;
        }

        // Apply filters across category list if search or custom filter is active
        final List<ManifestItem> itemsToDisplay;
        if (showResults) {
          final allSortedItems = ref.watch(sortedManifestItemsProvider).valueOrNull ?? [];
          final categoryItems = _slug == 'all'
              ? (allSortedItems.isNotEmpty ? allSortedItems : rawItems)
              : (rawItems.isNotEmpty
                  ? rawItems
                  : allSortedItems.where((item) => FilterUtils.matchesCategorySlug(item, _slug)).toList());
          itemsToDisplay = FilterUtils.getFilteredItems(
            allItems: categoryItems,
            searchState: searchState,
            enforceCategory: enforceCategory,
          );
        } else {
          itemsToDisplay = rawItems;
        }


        return NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: CustomScrollView(
            // Let NestedScrollView manage the scroll controller
            key: PageStorageKey('scroll_${widget.categoryLabel}'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: _buildContentSlivers(
              searchState,
              hasSearch,
              showResults,
              itemsToDisplay,
              rawItems,
              pagState,
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildContentSlivers(
    SearchState searchState,
    bool hasSearch,
    bool showResults,
    List<ManifestItem> itemsToDisplay,
    List<ManifestItem> allItems,
    PaginatedCategoryState pagState,
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
    // (no infinite scroll for filtered results — filters apply on loaded data)
    if (showResults && itemsToDisplay.isNotEmpty) {
      return [_buildResultsGrid(itemsToDisplay)];
    }

    // No search or filter active → grid of all items + loading indicator
    return [
      _buildResultsGrid(allItems),
      // Loading indicator for infinite scroll
      if (pagState.isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      // "No more items" indicator
      if (!pagState.hasMore && allItems.isNotEmpty && !pagState.isLoadingMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Center(
              child: Text(
                'You\'ve reached the end',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
    ];
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

/// Clean, elegant landing state when user opens the Search tab with an empty query.
class _SearchLandingView extends StatelessWidget {
  final ValueChanged<String> onTagSelected;

  const _SearchLandingView({required this.onTagSelected});

  static const _popularTags = [
    'Korean',
    'Dual Audio',
    'Chinese',
    'Anime',
    'Action',
    'Sci-Fi',
    'Bollywood',
    'Comedy',
    'Thriller',
    'Horror',
    '2026',
    'Romance',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing circular icon container
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.search_rounded,
                  size: 36,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Search Movies & Series',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search across Vegamovies & Rogmovies in real-time',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 28),
            // Quick search tags section
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'QUICK SEARCH',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: _popularTags.map((tag) {
                return InkWell(
                  onTap: () => onTagSelected(tag),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.trending_up_rounded,
                          size: 14,
                          color: AppColors.primary.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tag,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
