import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _SearchScreenState extends ConsumerState<SearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _outerScrollController = ScrollController();

  late TabController _tabController;

  /// Tracks whether we are programmatically changing tabs (to avoid circular updates)
  bool _isProgrammatic = false;

  /// Tracks the last tab index we synced to filters, to avoid redundant updates
  int _lastSyncedTabIndex = 0;

  /// Persisted recent searches (up to 6)
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();

    _loadRecentSearches();

    _tabController = TabController(
      length: TopNavbar.items.length,
      vsync: this,
      initialIndex: 0,
      animationDuration: const Duration(milliseconds: 300), // Smooth red line slide
    );

    // Sync tab changes → update search provider filters & rebuild header
    _tabController.addListener(_onTabChanged);
    _tabController.animation?.addListener(() {
      if (mounted) setState(() {});
    });

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

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('recent_searches_list') ?? [];
      if (mounted) {
        setState(() {
          _recentSearches = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('recent_searches_list') ?? [];
      list.remove(q);
      list.insert(0, q);
      final capped = list.take(6).toList();
      await prefs.setStringList('recent_searches_list', capped);
      if (mounted) {
        setState(() {
          _recentSearches = capped;
        });
      }
    } catch (_) {}
  }

  Future<void> _removeRecentSearch(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('recent_searches_list') ?? [];
      list.remove(query);
      await prefs.setStringList('recent_searches_list', list);
      if (mounted) {
        setState(() {
          _recentSearches = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _clearAllRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recent_searches_list');
      if (mounted) {
        setState(() {
          _recentSearches = [];
        });
      }
    } catch (_) {}
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
    if (mounted) setState(() {});
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

  void _onSearchChanged(String query, {bool immediate = false}) {
    if (query.trim().isNotEmpty && _tabController.index != 0) {
      _isProgrammatic = true;
      _tabController.animateTo(0);
      _lastSyncedTabIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isProgrammatic = false;
      });
    }
    ref.read(searchProvider('explore').notifier).search(query, immediate: immediate);
  }

  Widget _buildDedicatedSearchBar(Responsive r) {
    final isActive = _searchFocus.hasFocus;
    final hasText = _searchController.text.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF1E1E22).withValues(alpha: 0.88)
                  : const Color(0xFF161619).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(35),
              border: Border.all(
                color: isActive
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.12),
                width: isActive ? 1.8 : 1.2,
              ),
              boxShadow: [
                // Active aura glow behind search bar
                if (isActive)
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                // Deep 3D elevation shadow
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: isActive ? 22 : 12,
                  offset: const Offset(0, 6),
                  spreadRadius: 1,
                ),
                // Accent glow shadow
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: isActive ? 0.45 : 0.15),
                  blurRadius: isActive ? 16 : 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                AnimatedScale(
                  scale: isActive ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.search_rounded,
                    color: isActive ? AppColors.primary : Colors.white.withValues(alpha: 0.45),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    textAlignVertical: TextAlignVertical.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search movies & series...',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (val) {
                      _saveRecentSearch(val);
                      _onSearchChanged(val, immediate: true);
                      _searchFocus.unfocus();
                    },
                    onChanged: (val) {
                      _onSearchChanged(val);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                if (hasText)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _onSearchChanged('', immediate: true);
                      if (mounted) setState(() {});
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      final q = _searchController.text.trim();
                      if (q.isNotEmpty) {
                        _saveRecentSearch(q);
                        _onSearchChanged(q, immediate: true);
                        _searchFocus.unfocus();
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 20,
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

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);

    // Listen for external filter updates (e.g. from Home See All)
    ref.listen(searchProvider('explore'), (previous, next) {
      if (previous?.filters != next.filters) {
        _syncTabToFiltersOnce();
      }
    });

    final isSearchTab = _tabController.index == 0;
    final bool isSearchActive = isSearchTab &&
        (_searchFocus.hasFocus || _searchController.text.isNotEmpty);

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
                // ── Scrollable content: TopNavbar slider at top, search bar below it on Search tab ──
                Expanded(
                  child: NestedScrollView(
                    controller: _outerScrollController,
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      // Top navbar slider — at the top
                      SliverToBoxAdapter(
                        child: TopNavbar(tabController: _tabController),
                      ),
                      // Dedicated search bar on Search tab — BELOW the top tab slider!
                      if (isSearchTab)
                        SliverToBoxAdapter(
                          child: _buildDedicatedSearchBar(r),
                        ),
                      // Filter chips — on category tabs (hidden on dedicated Search tab)
                      if (!isSearchTab)
                        const SliverToBoxAdapter(
                          child: CategoryFilterChips(),
                        ),
                      // Small gap between navbar area and grid content
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 6),
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
                          recentSearches: _recentSearches,
                          onSaveRecentSearch: _saveRecentSearch,
                          onRemoveRecentSearch: _removeRecentSearch,
                          onClearAllRecentSearches: _clearAllRecentSearches,
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
  final void Function(String query, {bool immediate}) onSearchChanged;
  final List<String> recentSearches;
  final Function(String) onSaveRecentSearch;
  final Function(String) onRemoveRecentSearch;
  final VoidCallback onClearAllRecentSearches;

  const _CategoryPage({
    super.key,
    required this.categoryLabel,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.recentSearches,
    required this.onSaveRecentSearch,
    required this.onRemoveRecentSearch,
    required this.onClearAllRecentSearches,
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
      // Trigger when within 600px of the bottom
      if (metrics.pixels >= metrics.maxScrollExtent - 600) {
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
        // Landing state: clean empty landing matching save & download empty pages with recent searches
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _SearchLandingView(
                recentSearches: widget.recentSearches,
                onTagSelected: (tag) {
                  widget.searchController.text = tag;
                  widget.onSearchChanged(tag, immediate: true);
                  widget.onSaveRecentSearch(tag);
                },
                onRemoveRecent: widget.onRemoveRecentSearch,
                onClearAll: widget.onClearAllRecentSearches,
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

    final isSearchTab = widget.categoryLabel == 'Search';
    final hasSearch = isSearchTab && searchState.query.trim().isNotEmpty;
    // Check for user-applied filters BEYOND the nav category.
    // The nav category alone should NOT trigger FilterUtils re-sorting,
    // because category providers already supply correctly filtered + sorted data
    final f = searchState.filters;
    final hasUserFilters = f.regions.isNotEmpty ||
        f.originalLanguages.isNotEmpty ||
        f.genres.isNotEmpty ||
        f.years.isNotEmpty ||
        f.sortBy != 'Popularity' ||
        f.categories.any((c) => c != searchState.navCategory && c != widget.categoryLabel);
    final showResults = hasSearch || hasUserFilters;

    return paginatedState.when(
      loading: () {
        final allSortedItems = ref.watch(sortedManifestItemsProvider).valueOrNull ?? [];
        final categoryFallback = _slug == 'all' || _slug == 'search'
            ? allSortedItems
            : allSortedItems.where((item) => FilterUtils.matchesCategorySlug(item, _slug)).toList();
        if (categoryFallback.isNotEmpty) {
          return CustomScrollView(
            key: PageStorageKey('scroll_${widget.categoryLabel}'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildResultsGrid(categoryFallback),
            ],
          );
        }
        return CustomScrollView(
          slivers: [_buildShimmerGrid()],
        );
      },
      error: (err, _) {
        final allSortedItems = ref.watch(sortedManifestItemsProvider).valueOrNull ?? [];
        final categoryFallback = _slug == 'all' || _slug == 'search'
            ? allSortedItems
            : allSortedItems.where((item) => FilterUtils.matchesCategorySlug(item, _slug)).toList();
        if (categoryFallback.isNotEmpty) {
          return CustomScrollView(
            key: PageStorageKey('scroll_${widget.categoryLabel}'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildResultsGrid(categoryFallback),
            ],
          );
        }
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: Center(child: Text('Error: $err'))),
          ],
        );
      },
      data: (pagState) {
        final rawItems = pagState.items;
        final allSortedItems = ref.watch(sortedManifestItemsProvider).valueOrNull ?? [];
        final categoryFallback = _slug == 'all' || _slug == 'search'
            ? allSortedItems
            : allSortedItems.where((item) => FilterUtils.matchesCategorySlug(item, _slug)).toList();
        final effectiveItems = rawItems.isNotEmpty ? rawItems : categoryFallback;

        // Determine enforced category for FilterUtils
        String? enforceCategory;
        const categoryPages = {
          'Action', 'Korean', 'K-Drama', 'Chinese', 'Anime', 'Comedy',
          'Thriller', 'Horror', 'Sci-Fi', 'Romance', 'Indian', 'Bollywood',
          'Hollywood', 'Punjabi', 'Pakistani', 'Dual Audio', 'Adventure',
          'Crime', 'Drama', 'Mystery', 'Fantasy', 'Animation',
        };
        final filterCat = searchState.filters.categories;
        if (filterCat.isNotEmpty && categoryPages.contains(filterCat.first)) {
          enforceCategory = filterCat.first;
        }

        // Apply filters across category list if search or custom filter is active
        final List<ManifestItem> itemsToDisplay;
        if (showResults) {
          itemsToDisplay = FilterUtils.getFilteredItems(
            allItems: effectiveItems,
            searchState: searchState,
            enforceCategory: enforceCategory,
          );
        } else {
          itemsToDisplay = effectiveItems;
        }

        return NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: CustomScrollView(
            key: PageStorageKey('scroll_${widget.categoryLabel}'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: _buildContentSlivers(
              searchState,
              hasSearch,
              showResults,
              itemsToDisplay,
              effectiveItems,
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
    if (showResults && itemsToDisplay.isNotEmpty) {
      return [_buildResultsGrid(itemsToDisplay)];
    }

    if (itemsToDisplay.isEmpty) {
      if (pagState.isLoadingMore) {
        return [_buildShimmerGrid()];
      }
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyResultsView(),
        ),
      ];
    }

    // No search or filter active → grid of items + loading indicator
    return [
      _buildResultsGrid(itemsToDisplay),
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
      if (!pagState.hasMore && itemsToDisplay.isNotEmpty && !pagState.isLoadingMore)
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
              onTap: () {
                widget.onSaveRecentSearch(widget.searchController.text);
                context
                    .push('/details/${items[idx].mediaType}/${items[idx].id}');
              },
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
/// Matches the design of the watchlist (save) and download empty pages.
class _SearchLandingView extends StatelessWidget {
  final List<String> recentSearches;
  final ValueChanged<String> onTagSelected;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearAll;

  const _SearchLandingView({
    required this.recentSearches,
    required this.onTagSelected,
    required this.onRemoveRecent,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Subtle circular icon matching Watchlist & Downloads EmptyResultsView
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 32),

              // Title matching Watchlist / Downloads empty state
              Text(
                'Search Movies & Series',
                textAlign: TextAlign.center,
                style: GoogleFonts.lora(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Search across Vegamovies & Rogmovies in real-time',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 14,
                  height: 1.6,
                  letterSpacing: 0.1,
                ),
              ),

              // Minimalist Red Accent Dash
              const SizedBox(height: 32),
              Container(
                width: 24,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),

              // Recent Searches: Up to 6 recent searches. If none, show NOTHING!
              if (recentSearches.isNotEmpty) ...[
                const SizedBox(height: 36),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RECENT SEARCHES',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      GestureDetector(
                        onTap: onClearAll,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          'Clear all',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: recentSearches.take(6).map((term) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => onTagSelected(term),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history_rounded,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    term,
                                    style: GoogleFonts.inter(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => onRemoveRecent(term),
                                    behavior: HitTestBehavior.opaque,
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
