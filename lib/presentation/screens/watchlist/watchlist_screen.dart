import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/manifest_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/empty_results_view.dart';
import '../../widgets/category_header.dart';
import '../../../core/utils/search_utils.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final watchlistAsync = ref.watch(watchlistProvider);
    final searchState = ref.watch(searchProvider);
    final index = ref.watch(manifestIndexProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Title scrolls with content
              const SliverToBoxAdapter(
                child: CategoryTitle(title: 'Favourites'),
              ),
              // Search bar floats (hides on scroll down, shows on scroll up)
              SliverPersistentHeader(
                floating: true,
                delegate: FloatingSearchBarDelegate(
                  searchController: _searchController,
                  searchFocus: _searchFocus,
                  onSearchChanged: _onSearchChanged,
                ),
              ),
              // Filter chips
              const SliverToBoxAdapter(
                child: CategoryFilterChips(),
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
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          16, 4, 16, MediaQuery.paddingOf(context).bottom + 100),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.6,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
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
                    ),
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
