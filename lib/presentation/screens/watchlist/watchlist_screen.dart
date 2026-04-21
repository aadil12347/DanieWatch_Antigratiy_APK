import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/manifest_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/empty_results_view.dart';
import '../../widgets/category_header.dart';
import '../../../core/utils/search_utils.dart';
import '../../providers/scroll_provider.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final currentQuery = ref.read(searchProvider('watchlist')).query;
    if (currentQuery.isNotEmpty) {
      _searchController.text = currentQuery;
    }
    _searchFocus.addListener(_onFocusChange);

    // Auto-dismiss keyboard on scroll
    _scrollController.addListener(_onScroll);

    // Register the controller for Favorites tab (index 2)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scrollProvider).register(2, _scrollController);
    });
  }

  void _onScroll() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
    }
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
      // Sync focus state to global provider
      ref.read(searchFocusProvider.notifier).state = _searchFocus.hasFocus;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    ref.read(scrollProvider).unregister(2);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.removeListener(_onFocusChange);
    ref.read(searchFocusProvider.notifier).state = false;
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider('watchlist').notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final watchlistAsync = ref.watch(watchlistProvider);
    final searchState = ref.watch(searchProvider('watchlist'));
    final index = ref.watch(manifestIndexProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Pinned header row — same style as Explore page
              SliverPersistentHeader(
                pinned: true,
                delegate: PinnedHeaderDelegate(
                  title: 'Favourites',
                  searchController: _searchController,
                  searchFocus: _searchFocus,
                  onSearchChanged: _onSearchChanged,
                  contextId: 'watchlist',
                ),
              ),
              // Filter chips — scroll normally behind pinned header
              const SliverToBoxAdapter(
                child: CategoryFilterChips(contextId: 'watchlist'),
              ),
              // Content
              ...watchlistAsync.when(
                loading: () => [
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    child: Center(
                      child: Text('Error: $e',
                          style: const TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
                ],
                data: (items) {
                  if (items.isEmpty) {
                    return [
                      const SliverFillRemaining(
                        child: EmptyResultsView(
                          title: 'Your List is Empty',
                          message: "It seems that you haven't added any movies or shows to your list yet.",
                          icon: Icons.bookmark_border_rounded,
                        ),
                      ),
                    ];
                  }

                  // Map watchlist items to ManifestItems for filtering
                  final manifestItems = items.map((item) => ManifestItem(
                        id: item.tmdbId,
                        mediaType: item.mediaType,
                        title: item.title,
                        posterUrl: item.posterPath,
                        voteAverage: item.voteAverage,
                      )).toList();

                  // Apply filters
                  final filteredItems = FilterUtils.getFilteredItems(
                    allItems: manifestItems,
                    searchState: searchState,
                    index: index,
                  );

                  if (filteredItems.isEmpty && (searchState.query.isNotEmpty || searchState.filters.hasActiveFilters)) {
                    return [
                      const SliverFillRemaining(
                        child: EmptyResultsView(),
                      ),
                    ];
                  }

                  if (filteredItems.isEmpty) {
                    return [
                      const SliverFillRemaining(
                        child: EmptyResultsView(
                          title: 'Your List is Empty',
                          message: "It seems that you haven't added any movies or shows to your list yet.",
                          icon: Icons.bookmark_border_rounded,
                        ),
                      ),
                    ];
                  }

                  return [
                    Builder(builder: (context) {
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
                            (context, index) {
                              return MovieCard(
                                key: ValueKey('fav_${filteredItems[index].id}'),
                                item: filteredItems[index],
                              );
                            },
                            childCount: filteredItems.length,
                          ),
                        ),
                      );
                    }),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
